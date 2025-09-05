# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

## The `writer` module contains utilities for implementing custom CBOR output,
## both when implementing `writeValue` to provide custom serialization of a type
## and when streaming CBOR directly without first creating Nim objects.
##
## CBOR values are generally written using `writeValue`. It is also possible to
## stream the members and elements of objects/arrays using the
## `writeArray`/`writeObject` templates - alternatively, the low-level
## `begin{Array,Object}` and `end{Array,Object}` helpers provide fine-grained
## writing access.
##
## Finally, `streamElement` can be used when direct access to the stream is
## needed, for example to efficiently encode a value without intermediate
## allocations.

{.push raises: [], gcsafe.}

import
  std/[math], faststreams/[outputs], stew/[endians2], serialization, ./[format, types]

export outputs, format, types, DefaultFlavor

type
  CollectionKind = enum
    Array
    Object

  CborWriter*[Flavor = DefaultFlavor] = object
    stream: OutputStream
    stack: seq[CollectionKind] # Stack that keeps track of nested arrays/objects
    wantName: bool # The next output should be a name (for an object member)

Cbor.setWriter CborWriter, PreferredOutput = seq[byte]

func init*(W: type CborWriter, stream: OutputStream): W =
  ## Initialize a new CborWriter with the given output stream.
  ##
  ## The writer generally does not need closing or flushing, which instead is
  ## managed by the stream itself.
  W(stream: stream)

proc writeValue*[V: not void](w: var CborWriter, value: V) {.raises: [IOError].}
  ## Write value as Cbor - this is the main entry point for converting "anything"
  ## to Cbor.
  ##
  ## See also `writeMember`.

proc writeMember*[V: not void](
  w: var CborWriter, name: string, value: V
) {.raises: [IOError].}
  ## Write `name` and `value` as a Cbor member / field of an object.

template shouldWriteObjectField*[FieldType](field: FieldType): bool =
  ## Template to determine if an object field should be written.
  ## Called when `omitsOptionalField` is enabled - the field is omitted if the
  ## template returns `false`.
  true

func initialByte(major, minor: uint8): byte =
  assert major <= 7
  assert minor <= 31
  (major shl 5) or minor

func toMinorLen(val: uint64): uint8 =
  if val < minorLen1:
    val.uint8
  elif val <= uint8.high:
    minorLen1
  elif val <= uint16.high:
    minorLen2
  elif val <= uint32.high:
    minorLen4
  else:
    minorLen8

proc writeHead(
    w: var CborWriter, majorType: uint8, argument: uint64
) {.raises: [IOError].} =
  let minor = argument.toMinorLen()
  w.stream.write initialByte(majorType, minor)
  case minor
  of minorLen1:
    w.stream.write argument.uint8
  of minorLen2:
    w.stream.write argument.uint16.toBytesBE()
  of minorLen4:
    w.stream.write argument.uint32.toBytesBE()
  of minorLen8:
    w.stream.write argument.toBytesBE()
  else:
    discard

func inObject(w: CborWriter): bool =
  w.stack.len > 0 and w.stack[^1] == Object

proc beginElement(w: var CborWriter) =
  ## Start writing an array element or the value part of an object member.
  ##
  ## Must be closed with a corresponding `endElement`.
  ##
  ## The framework takes care to call `beginElement`/`endElement` as necessary
  ## as part of `writeValue` and `streamElement`.
  doAssert not w.wantName

proc endElement(w: var CborWriter) =
  ## Matching `end` call for `beginElement`
  w.wantName = w.inObject

proc beginObject*(w: var CborWriter, length = -1) {.raises: [IOError].} =
  ## Start writing an object, to be followed by member fields.
  ##
  ## Must be closed with a matching `endObject`.
  ##
  ## See also `writeObject`.
  ##
  ## Use `writeMember` to add member fields to the object.
  w.beginElement()

  if length >= 0:
    w.writeHead(majorMap, length.uint64)
  else:
    w.stream.write initialByte(majorMap, minorIndef)

  w.wantName = true

  w.stack.add(Object)

proc endObject*(w: var CborWriter, stopCode = true) {.raises: [IOError].} =
  ## Finish writing an object started with `beginObject`.
  doAssert w.stack.pop() == Object

  if stopCode:
    w.stream.write breakStopCode

  w.endElement()

proc beginArray*(w: var CborWriter, length = -1) {.raises: [IOError].} =
  ## Start writing a Cbor array.
  ## Must be closed with a matching `endArray`.
  w.beginElement()

  if length >= 0:
    w.writeHead(majorArray, length.uint64)
  else:
    w.stream.write initialByte(majorArray, minorIndef)

  w.stack.add(Array)

proc endArray*(w: var CborWriter, stopCode = true) {.raises: [IOError].} =
  ## Finish writing a Cbor array started with `beginArray`.
  doAssert w.stack.pop() == Array

  if stopCode:
    w.stream.write breakStopCode

  w.endElement()

template streamElement*(w: var CborWriter, streamVar: untyped, body: untyped) =
  ## Write an element giving direct access to the underlying stream - each
  ## separate Cbor value needs to be written in its own `streamElement` block.
  ##
  ## Within the `streamElement` block, do not use `writeValue` and other
  ## high-level helpers as these already perform the element tracking done in
  ## `streamElement`.
  w.beginElement()
  let streamVar = w.stream
  body
  w.endElement()

proc write*(w: var CborWriter, val: openArray[char]) {.raises: [IOError].} =
  w.streamElement(s):
    w.writeHead(majorText, val.len.uint64)
    s.write(val)

proc write*(w: var CborWriter, val: seq[byte]) {.raises: [IOError].} =
  w.streamElement(s):
    w.writeHead(majorBytes, val.len.uint64)
    s.write(val)

proc write*(w: var CborWriter, val: CborSimpleValue) {.raises: [IOError].} =
  w.streamElement(_):
    w.writeHead(majorSimple, val.uint64)

# https://www.rfc-editor.org/rfc/rfc8949.html#name-pseudocode-for-encoding-a-s
proc write*[T: SomeSignedInt](w: var CborWriter, val: T) {.raises: [IOError].} =
  w.streamElement(_):
    var ui = uint64(val shr (sizeof(T) * 8 - 1))
    let mt = uint8(ui and 1)
    ui = ui xor uint64(val)
    assert mt in {majorUnsigned, majorNegative}
    w.writeHead(mt, ui)

proc write*[T: SomeUnsignedInt](w: var CborWriter, val: T) {.raises: [IOError].} =
  w.streamElement(_):
    w.writeHead(majorUnsigned, val.uint64)

proc write*(w: var CborWriter, val: SomeFloat) {.raises: [IOError].} =
  w.streamElement(s):
    case val.classify
    of fcNan:
      s.write [initialByte(majorFloat, minorLen2), 0x7E'u8, 0x00'u8]
    of fcInf:
      s.write [initialByte(majorFloat, minorLen2), 0x7C'u8, 0x00'u8]
    of fcNegInf:
      s.write [initialByte(majorFloat, minorLen2), 0xFC'u8, 0x00'u8]
    else:
      # VM requires this cast dance because float32 has 64-bit precision
      #if val == float32(val):
      if val == cast[float32](cast[uint32](val.float32)):
        s.write initialByte(majorFloat, minorLen4)
        s.write cast[uint32](val.float32).toBytesBE()
      else:
        s.write initialByte(majorFloat, minorLen8)
        s.write cast[uint64](val.float64).toBytesBE()

proc write*(w: var CborWriter, val: CborTag) {.raises: [IOError].} =
  w.streamElement(_):
    w.writeHead(majorTag, val.tag)
    w.writeValue(val.val)

proc write*(w: var CborWriter, val: CborBytes) {.raises: [IOError].} =
  w.streamElement(s):
    s.write(seq[byte](val))

proc writeName*(w: var CborWriter, name: string) {.raises: [IOError].} =
  ## Write the name part of the member of an object, to be followed by the value.
  doAssert w.inObject()
  doAssert w.wantName

  w.wantName = false

  w.writeHead(majorText, name.len.uint64)
  w.stream.write(name)

template writeMember*[T: void](w: var CborWriter, name: string, body: T) =
  ## Write a member field of an object, i.e., the name followed by the value.
  ##
  ## Optional field handling is not performed and must be done manually.
  w.writeName(name)
  body

template shouldWriteValue(w: CborWriter, value: untyped): bool =
  mixin flavorOmitsOptionalFields, shouldWriteObjectField

  type
    Writer = typeof w
    Flavor = Writer.Flavor

  when flavorOmitsOptionalFields(Flavor):
    shouldWriteObjectField(value)
  else:
    true

proc writeMember*[V: not void](
    w: var CborWriter, name: string, value: V
) {.raises: [IOError].} =
  ## Write a member field of an object, i.e., the name followed by the value.
  ##
  ## Optional fields may get omitted depending on the Flavor.
  mixin writeValue

  if w.shouldWriteValue(value):
    w.writeName(name)
    w.writeValue(value)

iterator stepwiseArrayCreation*[C](
    w: var CborWriter, collection: C
): auto {.raises: [IOError].} =
  ## Iterate over the members of a collection, expecting each member to be
  ## written directly to the stream.
  w.beginArray()
  for e in collection:
    yield e
  w.endArray()

proc writeIterable*(w: var CborWriter, collection: auto) {.raises: [IOError].} =
  ## Write each element of a collection as a Cbor array.
  mixin writeValue
  w.beginArray()
  for e in collection:
    w.writeValue(e)
  w.endArray()

template writeArray*[T: void](w: var CborWriter, body: T) =
  ## Write a Cbor array using a code block for its elements.
  w.beginArray()
  body
  w.endArray()

proc writeArray*[C: not void](w: var CborWriter, values: C) {.raises: [IOError].} =
  ## Write a collection as a Cbor array.
  mixin writeValue
  w.beginArray(values.len)
  for v in values:
    w.writeValue(v)
  w.endArray(stopCode = false)

template writeObject*[T: void](w: var CborWriter, body: T) =
  ## Write a Cbor object using a code block for its fields.
  w.beginObject()
  body
  w.endObject()

template writeObjectField*[FieldType, RecordType](
    w: var CborWriter, record: RecordType, fieldName: static string, field: FieldType
) =
  ## Write a field of a record or tuple as a Cbor object member.
  mixin writeFieldIMPL, writeValue

  w.writeName(fieldName)

  w.beginElement()
  when RecordType is tuple:
    w.writeValue(field)
  else:
    type R = type record
    w.writeFieldIMPL(FieldTag[R, fieldName], field, record)
  w.endElement()

proc writeRecordValue*(w: var CborWriter, value: object | tuple) {.raises: [IOError].} =
  ## Write a record or tuple as a Cbor object.
  ##
  ## This function exists to satisfy the nim-serialization API - use `writeValue`
  ## to serialize objects when using `Cborwriter`.
  mixin enumInstanceSerializedFields, writeObjectField
  mixin flavorOmitsOptionalFields, shouldWriteObjectField

  var fieldsCount = 0
  value.enumInstanceSerializedFields(_, fieldValue):
    when fieldValue isnot CborVoid:
      fieldsCount += w.shouldWriteValue(fieldValue).int

  w.beginObject(fieldsCount)
  value.enumInstanceSerializedFields(fieldName, fieldValue):
    when fieldValue isnot CborVoid:
      if w.shouldWriteValue(fieldValue):
        writeObjectField(w, value, fieldName, fieldValue)
    else:
      discard fieldName
  w.endObject(stopCode = false)

proc writeValue*(w: var CborWriter, value: CborNumber) {.raises: [IOError].} =
  w.streamElement(_):
    if value.sign == CborSign.Neg:
      w.writeHead(majorNegative, value.integer)
    else:
      w.writeHead(majorUnsigned, value.integer)

proc writeValue*(w: var CborWriter, value: CborObjectType) {.raises: [IOError].} =
  var fieldCount = 0
  for _, v in value:
    fieldCount += w.shouldWriteValue(v).int
  w.beginObject(fieldCount)
  for name, v in value:
    w.writeMember(name, v)
  w.endObject(stopCode = false)

proc writeValue*(w: var CborWriter, value: CborValue) {.raises: [IOError].} =
  case value.kind
  of CborValueKind.Bytes:
    w.writeValue(value.bytesVal)
  of CborValueKind.String:
    w.writeValue(value.strVal)
  of CborValueKind.Unsigned, CborValueKind.Negative:
    w.writeValue(value.numVal)
  of CborValueKind.Float:
    w.writeValue(value.floatVal)
  of CborValueKind.Object:
    w.writeValue(value.objVal)
  of CborValueKind.Array:
    w.writeValue(value.arrayVal)
  of CborValueKind.Tag:
    w.writeValue(value.tagVal)
  of CborValueKind.Simple:
    w.writeValue(value.simpleVal)
  of CborValueKind.Bool:
    w.writeValue(value.boolVal)
  of CborValueKind.Null:
    w.writeValue(simpleNull.CborSimpleValue)
  of CborValueKind.Undefined:
    w.writeValue(simpleUndefined.CborSimpleValue)

template writeEnumImpl(w: var CborWriter, value, enumRep) =
  mixin writeValue
  when enumRep == EnumAsString:
    w.writeValue $value
  elif enumRep == EnumAsNumber:
    w.writeValue value.int
  elif enumRep == EnumAsStringifiedNumber:
    w.writeValue $value.int

template writeValue*(w: var CborWriter, value: enum) =
  ## Write an enum value as Cbor according to the flavor's enum representation.
  type Flavor = type(w).Flavor
  writeEnumImpl(w, value, Flavor.flavorEnumRep())

type StringLikeTypes = string | cstring | openArray[char] | seq[char]

template isStringLike(v: StringLikeTypes): bool =
  true

template isStringLike(v: auto): bool =
  false

template isStringLikeArray[N](v: array[N, char]): bool =
  true

template isStringLikeArray(v: auto): bool =
  false

template autoSerializeCheck(F: distinct type, T: distinct type, body) =
  when declared(macrocache.hasKey): # Nim 1.6 have no macrocache.hasKey
    mixin typeAutoSerialize
    when not F.typeAutoSerialize(T):
      const
        typeName = typetraits.name(T)
        flavorName = typetraits.name(F)
      {.
        error:
          flavorName &
          ": automatic serialization is not enabled or writeValue not implemented for `" &
          typeName & "`"
      .}
    else:
      body
  else:
    body

template autoSerializeCheck(
    F: distinct type, TC: distinct type, M: distinct type, body
) =
  when declared(macrocache.hasKey): # Nim 1.6 have no macrocache.hasKey
    mixin typeClassOrMemberAutoSerialize
    when not F.typeClassOrMemberAutoSerialize(TC, M):
      const
        typeName = typetraits.name(M)
        typeClassName = typetraits.name(TC)
        flavorName = typetraits.name(F)
      {.
        error:
          flavorName &
          ": automatic serialization is not enabled or writeValue not implemented for `" &
          typeName & "` of typeclass `" & typeClassName & "`"
      .}
    else:
      body
  else:
    body

template writeValueObjectOrTuple(Flavor, w, value) =
  mixin flavorUsesAutomaticObjectSerialization

  const isAutomatic = flavorUsesAutomaticObjectSerialization(Flavor)

  when not isAutomatic:
    const typeName = typetraits.name(type value)
    {.
      error:
        "Please override writeValue for the " & typeName &
        " type (or import the module where the override is provided)"
    .}

  when value is distinct:
    writeRecordValue(w, distinctBase(value, recursive = false))
  else:
    writeRecordValue(w, value)

template writeValueStringLike(w, value) =
  w.streamElement(_):
    when value is cstring:
      if value == nil:
        w.write(simpleNull.CborSimpleValue)
      else:
        w.write toOpenArray(value, 0, value.len - 1)
    else:
      w.write(value)

proc writeValue*[V: not void](w: var CborWriter, value: V) {.raises: [IOError].} =
  ## Write a generic value as Cbor, using type-based dispatch. Overload this
  ## function to provide custom conversions of your own types.
  mixin writeValue

  type Flavor = CborWriter.Flavor

  when value is CborVoid:
    autoSerializeCheck(Flavor, CborVoid):
      discard
  elif value is CborSimpleValue:
    autoSerializeCheck(Flavor, CborSimpleValue):
      w.write value
  elif value is CborTag:
    autoSerializeCheck(Flavor, CborTag):
      w.write value
  elif value is CborBytes:
    autoSerializeCheck(Flavor, CborBytes):
      w.write value
  elif value is ref:
    autoSerializeCheck(Flavor, ref, typeof(value)):
      if value.isNil:
        w.write(simpleNull.CborSimpleValue)
      else:
        writeValue(w, value[])
  elif isStringLike(value):
    autoSerializeCheck(Flavor, StringLikeTypes, typeof(value)):
      writeValueStringLike(w, value)
  elif isStringLikeArray(value):
    autoSerializeCheck(Flavor, array, typeof(value)):
      writeValueStringLike(w, value)
  elif value is bool:
    autoSerializeCheck(Flavor, bool):
      w.write if value: simpleTrue.CborSimpleValue else: simpleFalse.CborSimpleValue
  elif value is range:
    autoSerializeCheck(Flavor, range, typeof(value)):
      when low(typeof(value)) < 0:
        w.writeValue int64(value)
      else:
        w.writeValue uint64(value)
  elif value is SomeInteger:
    autoSerializeCheck(Flavor, SomeInteger, typeof(value)):
      w.write value
  elif value is SomeFloat:
    autoSerializeCheck(Flavor, SomeFloat, typeof(value)):
      w.write value
  elif value is seq[byte]:
    autoSerializeCheck(Flavor, seq[byte]):
      w.write(value)
  elif value is seq or (value is distinct and distinctBase(value) is seq):
    autoSerializeCheck(Flavor, seq, typeof(value)):
      when value is distinct:
        w.writeArray(distinctBase value)
      else:
        w.writeArray(value)
  elif value is array or (value is distinct and distinctBase(value) is array):
    autoSerializeCheck(Flavor, array, typeof(value)):
      when value is distinct:
        w.writeArray(distinctBase value)
      else:
        w.writeArray(value)
  elif value is openArray or (value is distinct and distinctBase(value) is openArray):
    autoSerializeCheck(Flavor, openArray, typeof(value)):
      when value is distinct:
        w.writeArray(distinctBase value)
      else:
        w.writeArray(value)
  elif value is object:
    when declared(macrocache.hasKey):
      # Nim 1.6 have no macrocache.hasKey and cannot accept `object` param
      autoSerializeCheck(Flavor, object, typeof(value)):
        writeValueObjectOrTuple(Flavor, w, value)
    else:
      writeValueObjectOrTuple(Flavor, w, value)
  elif value is tuple:
    when declared(macrocache.hasKey):
      # Nim 1.6 have no macrocache.hasKey and cannot accept `tuple` param
      autoSerializeCheck(Flavor, tuple, typeof(value)):
        writeValueObjectOrTuple(Flavor, w, value)
    else:
      writeValueObjectOrTuple(Flavor, w, value)
  elif value is distinct:
    autoSerializeCheck(Flavor, distinct, typeof(value)):
      writeValueObjectOrTuple(Flavor, w, value)
  else:
    const
      typeName = typetraits.name(value.type)
      flavorName = typetraits.name(Flavor)
    {.
      error: flavorName & ": Failed to convert to Cbor an unsupported type: " & typeName
    .}

proc toCbor*(v: auto, Flavor = DefaultFlavor): seq[byte] =
  ## Convert a value to its Cbor byte string representation.
  mixin writeValue

  var
    s = memoryOutput()
    w = CborWriter[DefaultFlavor].init(s) # XXX Flavor
  try:
    w.writeValue v
  except IOError:
    raiseAssert "memoryOutput is exception-free"
  s.getOutput(seq[byte])

# nim-serialization integration / naming

template beginRecord*(w: var CborWriter) =
  ## Alias for beginObject, for record serialization.
  beginObject(w)

template beginRecord*(w: var CborWriter, T: type) =
  ## Alias for beginObject with type, for record serialization.
  beginObject(w, T)

template writeFieldName*(w: var CborWriter, name: string) =
  ## Alias for writeName, for record serialization.
  writeName(w, name)

template writeField*(w: var CborWriter, name: string, value: auto) =
  ## Alias for writeMember, for record serialization.
  writeMember(w, name, value)

template endRecord*(w: var CborWriter) =
  ## Alias for endObject, for record serialization.
  w.endObject()

template configureCborSerialization*(
    T: type[enum], enumRep: static[EnumRepresentation]
) =
  ## Configure Cbor serialization for an enum type with a specific representation.
  proc writeValue*(w: var CborWriter, value: T) {.raises: [IOError].} =
    writeEnumImpl(w, value, enumRep)

template configureCborSerialization*(
    Flavor: type, T: type[enum], enumRep: static[EnumRepresentation]
) =
  ## Configure Cbor serialization for an enum type and flavor with a specific representation.
  when Flavor is Cbor:
    proc writeValue*(w: var CborWriter[DefaultFlavor], value: T) {.raises: [IOError].} =
      writeEnumImpl(w, value, enumRep)

  else:
    proc writeValue*(w: var CborWriter[Flavor], value: T) {.raises: [IOError].} =
      writeEnumImpl(w, value, enumRep)

{.pop.}
