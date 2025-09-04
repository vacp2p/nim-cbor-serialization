# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.experimental: "notnil".}
{.push raises: [], gcsafe.}

import
  std/[enumutils, tables, macros, typetraits],
  stew/[enums, objects],
  faststreams/inputs,
  serialization/[object_serialization, errors],
  "."/[format, types, parser, reader_desc]

export enumutils, inputs, format, types, errors, parser, reader_desc

func allowUnknownFields(r: CborReader): bool =
  CborReaderFlag.allowUnknownFields in r.parser.flags

func requireAllFields(r: CborReader): bool =
  CborReaderFlag.requireAllFields in r.parser.flags

func allocPtr[T](p: var ptr T) =
  p = create(T)

func allocPtr[T](p: var ref T) =
  p = new(T)

func isNotNilCheck[T](x: ref T not nil) {.compileTime.} =
  discard
func isNotNilCheck[T](x: ptr T not nil) {.compileTime.} =
  discard

func setBitInWord(x: var uint, bit: int) {.inline.} =
  let mask = uint(1) shl bit
  x = x or mask

const bitsPerWord = sizeof(uint) * 8

template setBitInArray[N](data: var array[N, uint], bitIdx: int) =
  when data.len > 1:
    setBitInWord(data[bitIdx div bitsPerWord], bitIdx mod bitsPerWord)
  else:
    setBitInWord(data[0], bitIdx)

func isBitwiseSubsetOf[N](lhs, rhs: array[N, uint]): bool =
  for i in low(lhs) .. high(lhs):
    if (lhs[i] and rhs[i]) != lhs[i]:
      return false

  true

# this construct catches `array[N, char]` which otherwise won't decompose into
# openArray[char] - we treat any array-like thing-of-characters as a string in
# the output
template isCharArray[N](v: array[N, char]): bool =
  true

template isCharArray(v: auto): bool =
  false

func isFieldExpected*(T: type): bool {.compileTime.} =
  T isnot Option

func totalExpectedFields*(T: type): int {.compileTime.} =
  mixin isFieldExpected, enumAllSerializedFields

  enumAllSerializedFields(T):
    if isFieldExpected(FieldType):
      inc result

func expectedFieldsBitmask*(TT: type, fields: static int): auto {.compileTime.} =
  type T = TT

  mixin isFieldExpected, enumAllSerializedFields

  const requiredWords = (fields + bitsPerWord - 1) div bitsPerWord

  var res: array[requiredWords, uint]

  var i = 0
  enumAllSerializedFields(T):
    if isFieldExpected(FieldType):
      res[i div bitsPerWord].setBitInWord(i mod bitsPerWord)
    inc i

  res

proc readRecordValue*[T](
    r: var CborReader, value: var T
) {.raises: [SerializationError, IOError].} =
  type
    ReaderType {.used.} = type r
    T = type value

  const
    fieldsTable = T.fieldReadersTable(ReaderType)
    typeName = typetraits.name(T)

  when fieldsTable.len > 0:
    const expectedFields = T.expectedFieldsBitmask(fieldsTable.len)

    var
      encounteredFields: typeof(expectedFields)
      mostLikelyNextField = 0

    r.parseObject(key):
      when T is tuple:
        let fieldIdx = mostLikelyNextField
        mostLikelyNextField += 1
        discard key
      else:
        let fieldIdx = findFieldIdx(fieldsTable, key, mostLikelyNextField)

      if fieldIdx != -1:
        let reader = fieldsTable[fieldIdx].reader
        reader(value, r)
        encounteredFields.setBitInArray(fieldIdx)
      elif r.allowUnknownFields:
        r.skipSingleValue()
      else:
        r.parser.raiseUnexpectedField(key, cstring typeName)

    if r.requireAllFields and not expectedFields.isBitwiseSubsetOf(encounteredFields):
      r.parser.raiseIncompleteObject(typeName)
  else:
    r.parseObject(key):
      # avoid bloat by putting this if inside parseObject
      if r.allowUnknownFields:
        r.skipSingleValue()
      else:
        r.parser.raiseUnexpectedField(key, cstring typeName)

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
          ": automatic serialization is not enabled or readValue not implemented for `" &
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
          ": automatic serialization is not enabled or readValue not implemented for `" &
          typeName & "` of typeclass `" & typeClassName & "`"
      .}
    else:
      body
  else:
    body

template readValueRefOrPtr(r, value) =
  mixin readValue
  when compiles(isNotNilCheck(value)):
    allocPtr value
    value[] = readValue(r, type(value[]))
  else:
    if r.parser.cborKind() in {CborValueKind.Null, CborValueKind.Undefined}:
      value = nil
      discard r.parseSimpleValue()
    else:
      allocPtr value
      value[] = readValue(r, type(value[]))

template readValueObjectOrTuple(Flavor, r, value) =
  mixin flavorUsesAutomaticObjectSerialization

  const isAutomatic = flavorUsesAutomaticObjectSerialization(Flavor)

  when not isAutomatic:
    const flavor =
      "CborReader[" & typetraits.name(typeof(r).Flavor) & "], " & typetraits.name(T)
    {.
      error:
        "Missing Cbor serialization import or implementation for readValue(" & flavor &
        ")"
    .}

  readRecordValue(r, value)

proc parseStringEnum[T](
    r: var CborReader, value: var T, stringNormalizer: static[proc(s: string): string]
) {.raises: [IOError, CborReaderError].} =
  let val = r.parseString()
  try:
    value =
      genEnumCaseStmt(T, val, default = nil, ord(T.low), ord(T.high), stringNormalizer)
  except ValueError:
    const typeName = typetraits.name(T)
    r.parser.raiseUnexpectedValue("Invalid value for '" & typeName & "'")

func strictNormalize(s: string): string = # Match enum value exactly
  s

proc parseEnum[T](
    r: var CborReader,
    value: var T,
    allowNumericRepr: static[bool] = false,
    stringNormalizer: static[proc(s: string): string] = strictNormalize,
) {.raises: [IOError, CborReaderError].} =
  const style = T.enumStyle
  case r.parser.cborKind()
  of CborValueKind.String:
    r.parseStringEnum(value, stringNormalizer)
  of CborValueKind.Unsigned, CborValueKind.Negative:
    when allowNumericRepr:
      case style
      of EnumStyle.Numeric:
        if not value.checkedEnumAssign(r.parseInt(int)):
          const typeName = typetraits.name(T)
          r.parser.raiseUnexpectedValue("Out of range for '" & typeName & "'")
      of EnumStyle.AssociatedStrings:
        r.parser.raiseUnexpectedValue("string", $r.parser.cborKind())
    else:
      r.parser.raiseUnexpectedValue("string", $r.parser.cborKind())
  else:
    case style
    of EnumStyle.Numeric:
      when allowNumericRepr:
        r.parser.raiseUnexpectedValue("number or string", $r.parser.cborKind())
      else:
        r.parser.raiseUnexpectedValue("number", $r.parser.cborKind())
    of EnumStyle.AssociatedStrings:
      r.parser.raiseUnexpectedValue("string", $r.parser.cborKind())

iterator readArray*(
    r: var CborReader, ElemType: typedesc
): ElemType {.raises: [IOError, SerializationError].} =
  mixin readValue

  r.parseArray:
    var res: ElemType
    readValue(r, res)
    yield res

iterator readObjectFields*(
    r: var CborReader, KeyType: type
): KeyType {.raises: [IOError, SerializationError].} =
  mixin readValue

  r.parseObjectCustomKey:
    var key: KeyType
    readValue(r, key)
  do:
    yield key

iterator readObjectFields*(
    r: var CborReader
): string {.raises: [IOError, SerializationError].} =
  for key in readObjectFields(r, string):
    yield key

iterator readObject*(
    r: var CborReader, KeyType: type, ValueType: type
): (KeyType, ValueType) {.raises: [IOError, SerializationError].} =
  mixin readValue

  for fieldName in readObjectFields(r, KeyType):
    var value: ValueType
    readValue(r, value)
    yield (fieldName, value)

proc readValue*[T](
    r: var CborReader, value: var T
) {.raises: [SerializationError, IOError].} =
  ## Master field/object parser. This function relies on
  ## customised sub-mixins for particular object types.
  ##
  ## Customised readValue() examples:
  ## ::
  ##     type
  ##       FancyInt = distinct int
  ##       FancyUInt = distinct uint
  ##
  ##     proc readValue(reader: var CborReader, value: var FancyInt) =
  ##       ## Refer to another readValue() instance
  ##       value = reader.readValue(int).FancyInt
  mixin readValue

  type Flavor = CborReader.Flavor

  when value is CborValueRef:
    autoSerializeCheck(Flavor, CborValueRef):
      r.parseValue(value)
  elif value is CborNumber:
    autoSerializeCheck(Flavor, CborNumber):
      r.parseNumber(value)
  elif value is CborTag:
    autoSerializeCheck(Flavor, CborNumber):
      r.parseTag(value.tag):
        readValue(r, value.val)
  elif value is CborVoid:
    autoSerializeCheck(Flavor, CborVoid):
      r.skipSingleValue()
  elif value is CborRaw:
    autoSerializeCheck(Flavor, CborRaw):
      r.parseValue(value)
  elif value is string:
    autoSerializeCheck(Flavor, string):
      value = r.parseString()
  elif value is seq[char]:
    autoSerializeCheck(Flavor, seq[char]):
      let val = r.parseString()
      value.setLen(val.len)
      for i in 0 ..< val.len:
        value[i] = val[i]
  elif isCharArray(value):
    autoSerializeCheck(Flavor, array, typeof(value)):
      let val = r.parseString()
      if val.len != value.len:
        r.parser.raiseUnexpectedValue("string of wrong length")
      for i in 0 ..< value.len:
        value[i] = val[i]
  elif value is seq[byte]:
    autoSerializeCheck(Flavor, seq[byte]):
      value = r.parseByteString()
  elif value is bool:
    autoSerializeCheck(Flavor, bool):
      value = r.parseBool()
  elif value is ref:
    autoSerializeCheck(Flavor, ref, typeof(value)):
      readValueRefOrPtr(r, value)
  elif value is ptr:
    autoSerializeCheck(Flavor, ptr, typeof(value)):
      readValueRefOrPtr(r, value)
  elif value is CborSimpleValue:
    autoSerializeCheck(Flavor, CborSimpleValue):
      value = r.parseSimpleValue()
  elif value is enum:
    autoSerializeCheck(Flavor, enum, typeof(value)):
      r.parseEnum(value)
  elif value is SomeInteger:
    autoSerializeCheck(Flavor, SomeInteger, typeof(value)):
      value = r.parseInt(typeof value, CborReaderFlag.portableInt in r.parser.flags)
  elif value is SomeFloat:
    autoSerializeCheck(Flavor, SomeFloat, typeof(value)):
      value = r.parseFloat(typeof value)
  elif value is seq:
    autoSerializeCheck(Flavor, seq, typeof(value)):
      r.parseArray:
        let lastPos = value.len
        value.setLen(lastPos + 1)
        readValue(r, value[lastPos])
  elif value is array:
    autoSerializeCheck(Flavor, array, typeof(value)):
      type IDX = typeof low(value)
      r.parseArray(idx):
        if idx < value.len:
          let i = IDX(idx + low(value).int)
          readValue(r, value[i])
        else:
          r.parser.raiseUnexpectedValue("Too many items for " & $(typeof(value)))
  elif value is object:
    when declared(macrocache.hasKey):
      # Nim 1.6 have no macrocache.hasKey and cannot accept `object` param
      autoSerializeCheck(Flavor, object, typeof(value)):
        readValueObjectOrTuple(Flavor, r, value)
    else:
      readValueObjectOrTuple(Flavor, r, value)
  elif value is tuple:
    when declared(macrocache.hasKey):
      # Nim 1.6 have no macrocache.hasKey and cannot accept `tuple` param
      autoSerializeCheck(Flavor, tuple, typeof(value)):
        readValueObjectOrTuple(Flavor, r, value)
    else:
      readValueObjectOrTuple(Flavor, r, value)
  else:
    const
      typeName = typetraits.name(T)
      flavorName = typetraits.name(Flavor)
    {.
      error:
        flavorName & ": Failed to convert from CBOR an unsupported type: " & typeName
    .}

template configureCborDeserialization*(
    T: type[enum],
    allowNumericRepr: static[bool] = false,
    stringNormalizer: static[proc(s: string): string] = strictNormalize,
) =
  proc readValue*(
      r: var CborReader, value: var T
  ) {.raises: [IOError, SerializationError].} =
    static:
      doAssert not allowNumericRepr or enumStyle(T) == EnumStyle.Numeric
    r.parseEnum(value, allowNumericRepr, stringNormalizer)

{.pop.}
