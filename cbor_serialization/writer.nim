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
## stream the fields and elements of objects/arrays using the
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

type CborWriter*[Flavor = DefaultFlavor] = object
  stream: OutputStream
  stack: seq[CborMajor] # Stack that keeps track of nested collections
  wantName: bool # The next output should be a name (for an object field)
  wantBytesElm, wantBytes: bool # The next output should be text/bytes

Cbor.setWriter CborWriter, PreferredOutput = seq[byte]
Cbor.defaultWriters()

func init*(W: type CborWriter, stream: OutputStream): W =
  ## Initialize a new CborWriter with the given output stream.
  ##
  ## The writer generally does not need closing or flushing, which instead is
  ## managed by the stream itself.
  W(stream: stream)

template shouldWriteObjectField*[FieldType](F: type Cbor, field: FieldType): bool =
  ## Template to determine if an object field should be written.
  ## Called when `omitsOptionalField` is enabled - the field is omitted if the
  ## template returns `false`.
  true

# https://www.rfc-editor.org/rfc/rfc8949#section-3-2
func initialByte(major: CborMajor, minor: uint8): byte =
  assert minor <= 31
  (major.uint8 shl 5) or minor

# https://www.rfc-editor.org/rfc/rfc8949#section-3-3.2
func minorVal(argument: uint64): uint8 =
  if argument < cborMinorLen1:
    argument.uint8
  elif argument <= uint8.high:
    cborMinorLen1
  elif argument <= uint16.high:
    cborMinorLen2
  elif argument <= uint32.high:
    cborMinorLen4
  else:
    cborMinorLen8

proc writeHead(
    w: var CborWriter, majorType: CborMajor, argument: uint64
) {.raises: [IOError].} =
  # https://www.rfc-editor.org/rfc/rfc8949#section-4.1
  let minor = argument.minorVal()
  w.stream.write initialByte(majorType, minor)
  case minor
  of cborMinorLen1:
    w.stream.write argument.uint8
  of cborMinorLen2:
    w.stream.write argument.uint16.toBytesBE()
  of cborMinorLen4:
    w.stream.write argument.uint32.toBytesBE()
  of cborMinorLen8:
    w.stream.write argument.toBytesBE()
  else:
    discard

proc writeHead(w: var CborWriter, majorType: CborMajor) {.raises: [IOError].} =
  w.stream.write initialByte(majorType, cborMinorIndef)

func inObject(w: CborWriter): bool =
  w.stack.len > 0 and w.stack[^1] == CborMajor.Map

func inText(w: CborWriter): bool =
  w.stack.len > 0 and w.stack[^1] == CborMajor.Text

func inBytes(w: CborWriter): bool =
  w.stack.len > 0 and w.stack[^1] == CborMajor.Bytes

proc beginElement(w: var CborWriter) =
  ## Start writing an array element or the value part of an object field.
  ##
  ## Must be closed with a corresponding `endElement`.
  ##
  ## The framework takes care to call `beginElement`/`endElement` as necessary
  ## as part of `writeValue` and `streamElement`.
  doAssert not w.wantName
  doAssert not w.wantBytesElm
  doAssert not w.wantBytes

proc endElement(w: var CborWriter) =
  ## Matching `end` call for `beginElement`
  w.wantName = w.inObject
  w.wantBytesElm = w.inText or w.inBytes
  w.wantBytes = false

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.12
# https://www.rfc-editor.org/rfc/rfc8949#section-3.2.2
proc beginObject*(w: var CborWriter, length = -1) {.raises: [IOError].} =
  ## Start writing an object, to be followed by fields.
  ##
  ## Must be closed with a matching `endObject`.
  ##
  ## See also `writeObject`.
  ##
  ## Use `writeField` to add fields to the object.
  w.beginElement()

  if length >= 0:
    w.writeHead(CborMajor.Map, length.uint64)
  else:
    w.writeHead(CborMajor.Map)

  w.wantName = true
  w.stack.add CborMajor.Map

proc endObject*(w: var CborWriter, stopCode = true) {.raises: [IOError].} =
  ## Finish writing an object started with `beginObject`.
  doAssert w.stack.pop() == CborMajor.Map

  if stopCode:
    w.stream.write cborBreakStopCode

  w.endElement()

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.10
# https://www.rfc-editor.org/rfc/rfc8949#section-3.2.2
proc beginArray*(w: var CborWriter, length = -1) {.raises: [IOError].} =
  ## Start writing a Cbor array.
  ## Must be closed with a matching `endArray`.
  w.beginElement()

  if length >= 0:
    w.writeHead(CborMajor.Array, length.uint64)
  else:
    w.writeHead(CborMajor.Array)

  w.stack.add CborMajor.Array

proc endArray*(w: var CborWriter, stopCode = true) {.raises: [IOError].} =
  ## Finish writing a Cbor array started with `beginArray`.
  doAssert w.stack.pop() == CborMajor.Array

  if stopCode:
    w.stream.write cborBreakStopCode

  w.endElement()

proc beginStringLike(
    w: var CborWriter, length: int, kind: CborMajor
) {.raises: [IOError].} =
  doAssert kind in {CborMajor.Text, CborMajor.Bytes}
  doAssert not w.wantBytesElm or length >= 0, "cannot nest indefinite text/bytes"
  doAssert not w.wantBytes, "cannot nest definite text/bytes"
  doAssert not w.inText or kind == CborMajor.Text
  doAssert not w.inBytes or kind == CborMajor.Bytes

  w.wantBytesElm = false
  w.wantBytes = false
  w.beginElement()

  if length >= 0:
    w.writeHead(kind, length.uint64)
    w.wantBytes = true
  else:
    w.writeHead(kind)
    w.wantBytesElm = true

  w.stack.add kind

proc beginText*(w: var CborWriter, length = -1) {.raises: [IOError].} =
  beginStringLike(w, length, CborMajor.Text)

proc beginBytes*(w: var CborWriter, length = -1) {.raises: [IOError].} =
  beginStringLike(w, length, CborMajor.Bytes)

proc endStringLike(w: var CborWriter, stopCode: bool) {.raises: [IOError].} =
  doAssert w.stack.pop() in {CborMajor.Text, CborMajor.Bytes}

  if stopCode:
    w.stream.write cborBreakStopCode

  w.endElement()

proc endBytes*(w: var CborWriter, stopCode = true) {.raises: [IOError].} =
  endStringLike(w, stopCode)

proc endText*(w: var CborWriter, stopCode = true) {.raises: [IOError].} =
  endStringLike(w, stopCode)

proc writeByte*(w: var CborWriter, x: byte) {.raises: [IOError].} =
  doAssert w.wantBytes
  w.stream.write(x)

proc writeChar*(w: var CborWriter, x: char) {.raises: [IOError].} =
  w.writeByte byte(x)

template writeText*(w: var CborWriter, length: int, body: untyped) =
  ## Write a Cbor text; use ``writeChar`` to write the characters.
  beginText(w, length)
  body
  endText(w, length < 0)

template writeText*(w: var CborWriter, body: untyped) =
  writeText(w, -1):
    body

template writeBytes*(w: var CborWriter, length: int, body: untyped) =
  ## Write a Cbor bytes; use ``writeByte`` to write the bytes.
  beginBytes(w, length)
  body
  endBytes(w, length < 0)

template writeBytes*(w: var CborWriter, body: untyped) =
  writeBytes(w, -1):
    body

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

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.8
proc write*(w: var CborWriter, val: openArray[char]) {.raises: [IOError].} =
  doAssert not w.wantBytesElm or w.inText
  w.wantBytesElm = false
  w.streamElement(s):
    w.writeHead(CborMajor.Text, val.len.uint64)
    s.write(val)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.6
proc write*(w: var CborWriter, val: seq[byte]) {.raises: [IOError].} =
  doAssert not w.wantBytesElm or w.inBytes
  w.wantBytesElm = false
  w.streamElement(s):
    w.writeHead(CborMajor.Bytes, val.len.uint64)
    s.write(val)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.3
proc write*(w: var CborWriter, val: CborSimpleValue) {.raises: [IOError].} =
  w.streamElement(_):
    w.writeHead(CborMajor.SimpleOrFloat, val.uint64)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.2
# https://www.rfc-editor.org/rfc/rfc8949#name-pseudocode-for-encoding-a-s
proc writeInt[T: SomeSignedInt](w: var CborWriter, val: T) {.raises: [IOError].} =
  w.streamElement(_):
    var ui = uint64(val shr (sizeof(typeof(val)) * 8 - 1))
    let mt = CborMajor(ui and 1)
    ui = ui xor uint64(val)
    assert mt in {CborMajor.Unsigned, CborMajor.Negative}
    w.writeHead(mt, ui)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.2
proc writeUint[T: SomeUnsignedInt](w: var CborWriter, val: T) {.raises: [IOError].} =
  w.streamElement(_):
    w.writeHead(CborMajor.Unsigned, val.uint64)

# TODO: https://github.com/nim-lang/Nim/issues/25172
proc write*[T: SomeInteger](w: var CborWriter, val: T) {.raises: [IOError].} =
  when T is SomeSignedInt:
    writeInt(w, val)
  else:
    static:
      assert T is SomeUnsignedInt
    writeUint(w, val)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.3
proc write*[T: SomeFloat](w: var CborWriter, val: T) {.raises: [IOError].} =
  w.streamElement(s):
    case val.classify
    of fcNan:
      w.writeHead(CborMajor.SimpleOrFloat, 0x7E00'u16)
    of fcInf:
      w.writeHead(CborMajor.SimpleOrFloat, 0x7C00'u16)
    of fcNegInf:
      w.writeHead(CborMajor.SimpleOrFloat, 0xFC00'u16)
    else:
      # VM requires this cast dance because float32 has 64-bit precision
      #if val == float32(val):
      if val == cast[float32](cast[uint32](val.float32)):
        s.write initialByte(CborMajor.SimpleOrFloat, cborMinorLen4)
        s.write cast[uint32](val.float32).toBytesBE()
      else:
        s.write initialByte(CborMajor.SimpleOrFloat, cborMinorLen8)
        s.write cast[uint64](val.float64).toBytesBE()

# https://www.rfc-editor.org/rfc/rfc8949#section-3.4
proc write*(w: var CborWriter, val: CborTag) {.raises: [IOError].} =
  w.streamElement(_):
    w.writeHead(CborMajor.Tag, val.tag)
    w.writeValue(val.val)

proc write*(w: var CborWriter, val: CborBytes) {.raises: [IOError].} =
  w.streamElement(s):
    s.write(seq[byte](val))

proc writeName*(w: var CborWriter, name: string) {.raises: [IOError].} =
  ## Write the name part of the field of an object, to be followed by the value.
  doAssert w.inObject()
  doAssert w.wantName

  w.wantName = false

  w.writeHead(CborMajor.Text, name.len.uint64)
  w.stream.write(name)

template writeField*[T: void](w: var CborWriter, name: string, body: T) =
  ## Write a field of an object, i.e., the name followed by the value.
  ##
  ## Optional field handling is not performed and must be done manually.
  w.writeName(name)
  body

template shouldWriteValue(w: CborWriter, value: untyped): bool =
  mixin flavorOmitsOptionalFields, shouldWriteObjectField

  type Flavor = w.Flavor

  when flavorOmitsOptionalFields(Flavor):
    shouldWriteObjectField(Cbor, value)
  else:
    true

proc writeField*[V: not void](
    w: var CborWriter, name: string, value: V
) {.raises: [IOError].} =
  ## Write a field of an object, i.e., the name followed by the value.
  ##
  ## Optional fields may get omitted depending on the Flavor.
  mixin writeValue

  if w.shouldWriteValue(value):
    w.writeName(name)
    w.writeValue(value)

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

proc write*[T](w: var CborWriter, values: openArray[T]) {.raises: [IOError].} =
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

template writeObjectField*[FieldType, ObjectType](
    w: var CborWriter, obj: ObjectType, fieldName: static string, field: FieldType
) =
  ## Write a field of an object.
  mixin writeFieldIMPL, writeValue

  w.writeName(fieldName)

  w.beginElement()
  type R = type obj
  w.writeFieldIMPL(FieldTag[R, fieldName], field, obj)
  w.endElement()

proc write*[T: object](w: var CborWriter, value: T) {.raises: [IOError].} =
  mixin enumInstanceSerializedFields, writeObjectField

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

proc write*[T: tuple](w: var CborWriter, value: T) {.raises: [IOError].} =
  mixin enumInstanceSerializedFields, writeValue

  var fieldsCount = 0
  value.enumInstanceSerializedFields(_, fieldValue):
    when fieldValue isnot CborVoid:
      fieldsCount += w.shouldWriteValue(fieldValue).int

  w.beginArray(fieldsCount)
  value.enumInstanceSerializedFields(_, fieldValue):
    when fieldValue isnot CborVoid:
      if w.shouldWriteValue(fieldValue):
        writeValue(w, fieldValue)
  w.endArray(stopCode = false)

proc write*(w: var CborWriter, value: CborNumber) {.raises: [IOError].} =
  w.streamElement(_):
    if value.sign == CborSign.Neg:
      w.writeHead(CborMajor.Negative, value.integer)
    else:
      w.writeHead(CborMajor.Unsigned, value.integer)

proc writeValue*(w: var CborWriter, value: CborNumber) {.raises: [IOError].} =
  w.write(value)

proc write*(w: var CborWriter, value: CborObjectType) {.raises: [IOError].} =
  var fieldCount = 0
  for _, v in value:
    fieldCount += w.shouldWriteValue(v).int
  w.beginObject(fieldCount)
  for name, v in value:
    w.writeField(name, v)
  w.endObject(stopCode = false)

proc write*(w: var CborWriter, value: CborValue) {.raises: [IOError].} =
  mixin writeValue
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
    w.writeValue(cborNull)
  of CborValueKind.Undefined:
    w.writeValue(cborUndefined)

template writeEnumImpl(w: var CborWriter, value, enumRep) =
  mixin writeValue
  when enumRep == EnumAsString:
    w.writeValue $value
  elif enumRep == EnumAsNumber:
    w.writeValue value.int
  elif enumRep == EnumAsStringifiedNumber:
    w.writeValue $value.int

template write*(w: var CborWriter, value: enum) =
  ## Write an enum value as Cbor according to the flavor's enum representation.
  type Flavor = w.Flavor
  writeEnumImpl(w, value, Flavor.flavorEnumRep())

proc write*(w: var CborWriter, val: CborVoid) {.raises: [IOError].} =
  discard

proc write*[T](w: var CborWriter, val: ref T) {.raises: [IOError].} =
  mixin writeValue
  if val.isNil:
    w.write(cborNull)
  else:
    w.writeValue(val[])

proc write*(w: var CborWriter, val: cstring) {.raises: [IOError].} =
  if val == nil:
    w.write(cborNull)
  else:
    w.write toOpenArray(val, 0, val.len - 1)

proc write*(w: var CborWriter, val: bool) {.raises: [IOError].} =
  w.write if val: cborTrue else: cborFalse

proc write*[T: range](w: var CborWriter, val: T) {.raises: [IOError].} =
  when T.low < 0:
    w.write int64(val)
  else:
    w.write uint64(val)

proc write*[T: distinct](w: var CborWriter, val: T) {.raises: [IOError].} =
  mixin writeValue
  writeValue(w, distinctBase(val, recursive = false))

proc toCbor*(v: auto, Flavor = DefaultFlavor): seq[byte] =
  ## Convert a value to its Cbor byte string representation.
  mixin writeValue

  var
    s = memoryOutput()
    w = CborWriter[Flavor].init(s)
  try:
    w.writeValue v
  except IOError:
    raiseAssert "memoryOutput is exception-free"
  s.getOutput(seq[byte])

template writeRecordValue*(w: var CborWriter, value: object) =
  ## This exists for nim-serialization integration
  write(w, value)

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
