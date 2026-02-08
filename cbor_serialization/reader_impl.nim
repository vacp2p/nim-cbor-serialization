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

from std/strutils import parseInt

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

func isFieldExpected*(F: type Cbor, T: type): bool {.compileTime.} =
  T isnot Option

func totalExpectedFields*(T: type): int {.compileTime.} =
  mixin isFieldExpected, enumAllSerializedFields

  enumAllSerializedFields(T):
    if isFieldExpected(Cbor, FieldType):
      inc result

func expectedFieldsBitmask*(
    F: type Cbor, TT: type, fields: static int
): auto {.compileTime.} =
  type T = TT

  mixin isFieldExpected, enumAllSerializedFields

  const requiredWords = (fields + bitsPerWord - 1) div bitsPerWord

  var res: array[requiredWords, uint]

  var i = 0
  enumAllSerializedFields(T):
    if isFieldExpected(F, FieldType):
      res[i div bitsPerWord].setBitInWord(i mod bitsPerWord)
    inc i

  res

proc read*[T: object](
    r: var CborReader, value: var T
) {.raises: [SerializationError, IOError].} =
  mixin flavorAllowsUnknownFields, flavorRequiresAllFields
  type
    ReaderType = typeof(r)
    Flavor = ReaderType.Flavor

  const
    fieldsTable = T.fieldReadersTable(ReaderType)
    typeName = typetraits.name(T)

  when fieldsTable.len > 0:
    const expectedFields = Cbor.expectedFieldsBitmask(T, fieldsTable.len)

    var
      encounteredFields: typeof(expectedFields)
      mostLikelyNextField = 0

    r.parseObject(key):
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

type FieldTupleReader[RecordType, Reader] = proc(
  rec: var RecordType, reader: var Reader
) {.gcsafe, nimcall, raises: [IOError, SerializationError].}

proc tupleFieldReaderTable(
    RecordType, ReaderType: distinct type, numFields: static[int]
): array[numFields, FieldTupleReader[RecordType, ReaderType]] =
  mixin enumAllSerializedFields

  enumAllSerializedFields(RecordType):
    const i = fieldName.parseInt
    proc readField(
        obj: var RecordType, reader: var ReaderType
    ) {.gcsafe, nimcall, raises: [IOError, SerializationError].} =
      mixin readValue
      reader.readValue obj[i]

    result[i] = readField

proc read*[T: tuple](
    r: var CborReader, value: var T
) {.raises: [SerializationError, IOError].} =
  mixin flavorAllowsUnknownFields, flavorRequiresAllFields

  type
    ReaderType = typeof(r)
    Flavor = ReaderType.Flavor

  const
    numFields = totalSerializedFields(T)
    fieldsTable = tupleFieldReaderTable(T, ReaderType, numFields)
    typeName = typetraits.name(T)

  var i = 0
  r.parseArray:
    if i < numFields:
      fieldsTable[i](value, r)
    elif flavorAllowsUnknownFields(Flavor):
      r.skipSingleValue()
    else:
      r.parser.raiseUnexpectedField($i, cstring typeName)
    inc i
  if flavorRequiresAllFields(Flavor) and i < numFields:
    r.parser.raiseIncompleteObject(typeName)

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

proc read*(
    r: var CborReader, value: var CborValueRef
) {.raises: [SerializationError, IOError].} =
  r.parseValue(value)

proc read*(
    r: var CborReader, value: var CborNumber
) {.raises: [SerializationError, IOError].} =
  r.parseNumber(value)

proc read*(
    r: var CborReader, value: var CborTag
) {.raises: [SerializationError, IOError].} =
  mixin readValue

  r.parseTag(value.tag):
    readValue(r, value.val)

proc read*(
    r: var CborReader, value: var CborVoid
) {.raises: [SerializationError, IOError].} =
  r.skipSingleValue()

proc read*(
    r: var CborReader, value: var CborBytes
) {.raises: [SerializationError, IOError].} =
  r.parseValue(value)

proc read*(
    r: var CborReader, value: var string
) {.raises: [SerializationError, IOError].} =
  value = r.parseString()

proc read*(
    r: var CborReader, value: var seq[char]
) {.raises: [SerializationError, IOError].} =
  # XXX avoid temp value
  let val = r.parseString()
  value.setLen(val.len)
  for i in 0 ..< val.len:
    value[i] = val[i]

proc read*[N](
    r: var CborReader, value: var array[N, char]
) {.raises: [SerializationError, IOError].} =
  let val = r.parseString()
  if val.len != value.len:
    r.raiseUnexpectedValue("string of wrong length")
  for i in 0 ..< value.len:
    value[i] = val[i]

proc read*(
    r: var CborReader, value: var seq[byte]
) {.raises: [SerializationError, IOError].} =
  value = r.parseByteString()

proc read*(
    r: var CborReader, value: var bool
) {.raises: [SerializationError, IOError].} =
  value = r.parseBool()

proc read*[T](
    r: var CborReader, value: var ref T
) {.raises: [SerializationError, IOError].} =
  readValueRefOrPtr(r, value)

proc read*[T](
    r: var CborReader, value: var ptr T
) {.raises: [SerializationError, IOError].} =
  readValueRefOrPtr(r, value)

proc read*(
    r: var CborReader, value: var CborSimpleValue
) {.raises: [SerializationError, IOError].} =
  value = r.parseSimpleValue()

proc read*[T: enum](
    r: var CborReader, value: var T
) {.raises: [SerializationError, IOError].} =
  r.parseEnum(value)

proc read*[T: SomeInteger](
    r: var CborReader, value: var T
) {.raises: [SerializationError, IOError].} =
  value = r.parseInt(T)

proc read*[T: SomeFloat](
    r: var CborReader, value: var T
) {.raises: [SerializationError, IOError].} =
  value = r.parseFloat(T)

proc read*[T](
    r: var CborReader, value: var seq[T]
) {.raises: [SerializationError, IOError].} =
  mixin readValue

  r.parseArray:
    let lastPos = value.len
    value.setLen(lastPos + 1)
    readValue(r, value[lastPos])

proc read*[T: array](
    r: var CborReader, value: var T
) {.raises: [SerializationError, IOError].} =
  mixin readValue

  type IDX = typeof low(value)
  r.parseArray(idx):
    if idx < value.len:
      let i = IDX(idx + low(value).int)
      readValue(r, value[i])
    else:
      r.raiseUnexpectedValue("Too many items for " & $(T))

template readRecordValue*(r: var CborReader, value: var object) =
  ## This exists for nim-serialization integration
  read(r, value)

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
