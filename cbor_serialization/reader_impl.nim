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
  ./[format, types, parser, reader_desc]

export enumutils, inputs, format, types, errors, parser, reader_desc

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
  mixin flavorAllowsUnknownFields, flavorRequiresAllFields
  type
    ReaderType = typeof(r)
    Flavor = ReaderType.Flavor
    T = typeof(value)

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
      elif flavorAllowsUnknownFields(Flavor):
        r.skipSingleValue()
      else:
        r.parser.raiseUnexpectedField(key, cstring typeName)

    if flavorRequiresAllFields(Flavor) and
        not expectedFields.isBitwiseSubsetOf(encounteredFields):
      r.parser.raiseIncompleteObject(typeName)
  else:
    r.parseObject(key):
      # avoid bloat by putting this if inside parseObject
      if flavorAllowsUnknownFields(Flavor):
        r.skipSingleValue()
      else:
        r.parser.raiseUnexpectedField(key, cstring typeName)

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

proc readValue*(
    r: var CborReader, value: var auto
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
    r.parseValue(value)
  elif value is CborNumber:
    r.parseNumber(value)
  elif value is CborTag:
    r.parseTag(value.tag):
      readValue(r, value.val)
  elif value is CborVoid:
    r.skipSingleValue()
  elif value is CborBytes:
    r.parseValue(value)
  elif value is string:
    value = r.parseString()
  elif value is seq[char]:
    let val = r.parseString()
    value.setLen(val.len)
    for i in 0 ..< val.len:
      value[i] = val[i]
  elif isCharArray(value):
    let val = r.parseString()
    if val.len != value.len:
      r.parser.raiseUnexpectedValue("string of wrong length")
    for i in 0 ..< value.len:
      value[i] = val[i]
  elif value is seq[byte]:
    value = r.parseByteString()
  elif value is bool:
    value = r.parseBool()
  elif value is ref:
    readValueRefOrPtr(r, value)
  elif value is ptr:
    readValueRefOrPtr(r, value)
  elif value is CborSimpleValue:
    value = r.parseSimpleValue()
  elif value is enum:
    r.parseEnum(value)
  elif value is SomeInteger:
    value = r.parseInt(typeof value)
  elif value is SomeFloat:
    value = r.parseFloat(typeof value)
  elif value is seq:
    r.parseArray:
      let lastPos = value.len
      value.setLen(lastPos + 1)
      readValue(r, value[lastPos])
  elif value is array:
    type IDX = typeof low(value)
    r.parseArray(idx):
      if idx < value.len:
        let i = IDX(idx + low(value).int)
        readValue(r, value[i])
      else:
        r.parser.raiseUnexpectedValue("Too many items for " & $(typeof(value)))
  elif value is object:
    readValueObjectOrTuple(Flavor, r, value)
  elif value is tuple:
    readValueObjectOrTuple(Flavor, r, value)
  else:
    const
      typeName = typetraits.name(typeof(value))
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
