# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import ./[reader_desc, utils]

export reader_desc

type
  NumberPart* = enum
    SignPart
    IntegerPart

  CustomNumberHandler* = ##\
    ## Custom number parser, result values need to be captured
    proc(part: NumberPart, dgt: int) {.gcsafe, raises: [].}

  CustomIntHandler* = ##\
    ## Custom integer parser, result values need to be captured
    proc(dgt: int) {.gcsafe, raises: [].}

  CustomStringHandler* = ##\
    ## Custom text or binary parser, result values need to be captured.
    proc(b: char) {.gcsafe, raises: [].}

template peek(p: CborParser): byte =
  if not p.stream.readable:
    raiseUnexpectedValue("unexpected eof")
  inputs.peek(p.stream)

template read(p: CborParser): byte =
  if not p.stream.readable:
    raiseUnexpectedValue("unexpected eof")
  inputs.read(p.stream)

proc read(p: CborParser, n: int): uint64 {.raises: [IOError, CborReaderError].} =
  assert n in 1 .. 8
  result = 0
  for _ in 0 ..< n:
    result = (result shl 8) or p.read()

proc readMinorValue(
    p: CborParser, minor: uint8
): uint64 {.raises: [IOError, CborReaderError].} =
  if minor in minorLen0:
    minor.uint64
  elif minor in minorLens:
    p.read(minor.minorLen())
  else:
    raiseUnexpectedValue("argument len", "value: " & $minor)

func major(x: byte): uint8 =
  return x shr 5

func minor(x: byte): uint8 =
  return x and 0b0001_1111

template parseStringLike(p: var CborParser, majorExpected: uint8, body: untyped) =
  let c = p.read()
  if c.major != majorExpected:
    raiseUnexpectedValue(majorExpected.toMeaning, c.major.toMeaning)
  if c.minor == minorIndef:
    while p.peek() != breakStopCode:
      let c2 = p.read()
      if c2.major != majorExpected:
        raiseUnexpectedValue(majorExpected.toMeaning, c2.major.toMeaning)
      for _ in 0 ..< readMinorValue(p, c2.minor):
        body
    discard p.read() # stop code
  else:
    for _ in 0 ..< readMinorValue(p, c.minor):
      body

iterator parseByteStringIt(
    p: var CborParser, limit: int
): byte {.inline, gcsafe, raises: [IOError, CborReaderError].} =
  var strLen = 0
  parseStringLike(p, majorBytes):
    inc strLen
    if limit > 0 and strLen > limit:
      raiseUnexpectedValue(majorBytes.toMeaning & " length limit reached")
    yield p.read()

proc parseByteString[T](
    p: var CborParser, limit: int, val: var T
) {.gcsafe, raises: [IOError, CborReaderError].} =
  when T isnot (string or seq[byte] or CborVoid):
    {.fatal: "`parseByteString` only accepts string or `seq[byte]` or `CborVoid`".}
  for v in parseByteStringIt(p, limit):
    when T is CborVoid:
      discard v
    else:
      val.add v

proc parseByteString[T](
    p: var CborParser, val: var T
) {.gcsafe, raises: [IOError, CborReaderError].} =
  parseByteString[T](p, p.conf.byteStringLengthLimit, val)

proc parseString[T](
    p: var CborParser, limit: int, val: var T
) {.gcsafe, raises: [IOError, CborReaderError].} =
  when T isnot (string or CborVoid):
    {.fatal: "`parseString` only accepts `string` or `CborVoid`".}
  var strLen = 0
  parseStringLike(p, majorText):
    inc strLen
    if limit > 0 and strLen > limit:
      raiseUnexpectedValue(majorText.toMeaning & " length limit reached")
    when T is CborVoid:
      discard p.read()
    else:
      val.add p.read().char

proc parseString[T](
    p: var CborParser, val: var T
) {.gcsafe, raises: [IOError, CborReaderError].} =
  parseString[T](p, p.conf.stringLengthLimit, val)

template enterNestedStructure(p: CborParser) =
  inc p.currDepth
  if p.conf.nestedDepthLimit > 0 and p.currDepth > p.conf.nestedDepthLimit:
    raiseUnexpectedValue("`nestedDepthLimit` reached")

template exitNestedStructure(p: CborParser) =
  dec p.currDepth

template parseArrayLike(p: var CborParser, majorExpected: uint8, body: untyped) =
  enterNestedStructure(p)
  let c = p.read()
  if c.major != majorExpected:
    raiseUnexpectedValue(majorExpected.toMeaning, c.major.toMeaning)
  if c.minor == minorIndef:
    while p.peek() != breakStopCode:
      body
    discard p.read() # stop code
  else:
    for _ in 0 ..< readMinorValue(p, c.minor):
      body
  exitNestedStructure(p)

template parseArray(p: var CborParser, idx, body: untyped) =
  var idx {.inject.} = 0
  parseArrayLike(p, majorArray):
    if p.conf.arrayElementsLimit > 0 and idx + 1 > p.conf.arrayElementsLimit:
      raiseUnexpectedValue("`arrayElementsLimit` reached")
    body
    inc idx

template parseObjectImpl(p: var CborParser, skipNullFields, keyAction, body: untyped) =
  var numElem = 0
  parseArrayLike(p, majorMap):
    inc numElem
    if p.conf.objectMembersLimit > 0 and numElem > p.conf.objectMembersLimit:
      raiseUnexpectedValue("`objectMembersLimit` reached")
    keyAction
    when skipNullFields:
      if r.parser.cborKind() in {CborValueKind.Null, CborValueKind.Undefined}:
        discard r.parseSimpleValue()
      else:
        body
    else:
      body

template parseObject(p: var CborParser, skipNullFields, key, body: untyped) =
  parseObjectImpl(p, skipNullFields):
    var key {.inject.} = ""
    p.parseString(key)
  do:
    body

template parseTag(p: var CborParser, tag: var uint64, body: untyped) =
  enterNestedStructure(p)
  let c = p.read()
  if c.major != majorTag:
    raiseUnexpectedValue("tag", c.major.toMeaning)
  tag = p.readMinorValue(c.minor)
  body
  exitNestedStructure(p)

proc parseIntTagValue(
    p: var CborParser, tag: uint64, val: var CborVoid
) {.raises: [IOError, CborReaderError].} =
  if tag notin {2, 3}:
    raiseUnexpectedValue("tag number 2 or 3", $tag)
  p.parseByteString(p.conf.integerDigitsLimit, val)

proc parseIntTagValue(
    p: var CborParser, tag: uint64, val: var CborNumber
) {.raises: [IOError, CborReaderError].} =
  val.sign =
    case tag
    of 2:
      CborSign.None
    of 3:
      CborSign.Neg
    else:
      raiseUnexpectedValue("tag number 2 or 3", $tag)
  when val.integer is string:
    when not hasBigints:
      {.fatal: "`bigints` dependency is required for int string support".}
    var bint = initBigInt(0)
    var digits = 1
    let bigint10 = initBigInt(10)
    var threshold = bigint10
    var leadingZero = true
    for v in parseByteStringIt(p, p.conf.integerDigitsLimit):
      leadingZero = leadingZero and v == 0
      if not leadingZero:
        bint = bint shl 8
        inc(bint, v.int)
        if p.conf.integerDigitsLimit > 0:
          while threshold <= bint:
            threshold *= bigint10
            inc digits
            if digits > p.conf.integerDigitsLimit:
              raiseUnexpectedValue("`integerDigitsLimit` reached")
    if val.sign == CborSign.Neg:
      inc(bint, 1)
      if threshold <= bint and digits + 1 > p.conf.integerDigitsLimit:
        raiseUnexpectedValue("`integerDigitsLimit` reached")
    val.integer = $bint
  else:
    var leadingZero = true
    val.integer = 0
    for v in parseByteStringIt(p, p.conf.integerDigitsLimit):
      leadingZero = leadingZero and v == 0
      if not leadingZero:
        if val.integer > uint64.high shr 8:
          raiseIntOverflow(val.integer, val.sign == CborSign.Neg)
        val.integer = (val.integer shl 8) or v
    if val.sign == CborSign.Neg:
      if val.integer == uint64.high:
        raiseIntOverflow(val.integer, true)
      val.integer += 1

proc parseIntTag[T](
    p: var CborParser, val: var T
) {.raises: [IOError, CborReaderError].} =
  var tag: uint64
  parseTag(p, tag):
    parseIntTagValue(p, tag, val)

proc parseIntImpl(
    p: var CborParser, val: var CborVoid
) {.raises: [IOError, CborReaderError].} =
  let c = p.read()
  if c.major notin {majorUnsigned, majorNegative}:
    raiseUnexpectedValue("number", c.major.toMeaning)
  discard p.readMinorValue(c.minor)

proc parseIntImpl(
    p: var CborParser, val: var CborNumber
) {.raises: [IOError, CborReaderError].} =
  let c = p.read()
  val.sign =
    case c.major
    of majorUnsigned:
      CborSign.None
    of majorNegative:
      CborSign.Neg
    else:
      raiseUnexpectedValue("number", c.major.toMeaning)
  let integer = p.readMinorValue(c.minor)
  when val.integer is string:
    when not hasBigints:
      {.fatal: "`bigints` dependency is required for int string support".}
    if c.major == majorNegative:
      var bint = initBigInt(integer)
      inc(bint, 1)
      val.integer = $bint
    else:
      val.integer = $integer
    if val.integer.len > p.conf.integerDigitsLimit:
      raiseUnexpectedValue("`integerDigitsLimit` reached")
  else:
    val.integer = integer
    if c.major == majorNegative:
      if integer == uint64.high:
        raiseIntOverflow(integer, true)
      val.integer += 1

proc parseInt[T](p: var CborParser, val: var T) {.raises: [IOError, CborReaderError].} =
  when T isnot (CborNumber or CborVoid):
    {.fatal: "`parseInt` only accepts `CborNumber` and `CborVoid`".}
  if p.peek().major == majorTag:
    parseIntTag(p, val)
  else:
    parseIntImpl(p, val)

proc parseFloat(
    p: var CborParser, T: type SomeFloat
): T {.gcsafe, raises: [IOError, CborReaderError].} =
  let c = p.read()
  if c.major != majorFloat:
    raiseUnexpectedValue("float value", c.major.toMeaning)
  let val = p.readMinorValue(c.minor)
  if c.minor == minorLen2:
    decodeHalf(val.uint16).T
  elif c.minor == minorLen4:
    cast[float32](val.uint32).T
  elif c.minor == minorLen8:
    when T is (float or float64):
      cast[float64](val).T
    else:
      raiseUnexpectedValue($T, "float64")
  else:
    raiseUnexpectedValue("float value argument", $c.minor)

proc parseSimpleValue(
    p: var CborParser, val: var CborSimpleValue
) {.gcsafe, raises: [IOError, CborReaderError].} =
  let c = p.read()
  if c.major != majorSimple:
    raiseUnexpectedValue("simple value", c.major.toMeaning)
  if c.minor notin minorLen0 + {minorLen1}:
    raiseUnexpectedValue("simple value argument", $c.minor)
  val = p.readMinorValue(c.minor).CborSimpleValue

proc readMinorValue(
    p: var CborParser, val: var CborRaw, minor: uint8
): uint64 {.raises: [IOError, CborReaderError].} =
  if minor in minorLen0:
    return minor
  elif minor in minorLens:
    var m: byte
    for _ in 0 ..< minor.minorLen():
      m = p.read()
      result = (result shl 8) or m
      val.add m
  else:
    raiseUnexpectedValue("argument len", "value: " & $minor)

proc parseRawHead(
    p: var CborParser, val: var CborRaw
) {.gcsafe, raises: [IOError, CborReaderError].} =
  assert p.peek().major in
    {majorUnsigned, majorNegative, majorTag, majorFloat, majorSimple}
  let c = p.read()
  val.add c
  discard readMinorValue(p, val, c.minor)

template parseRawArrayLikeImpl(p: var CborParser, val: var CborRaw, body: untyped) =
  assert p.peek().major in {majorArray, majorMap}
  let c = p.read()
  val.add c
  if c.minor == minorIndef:
    while p.peek() != breakStopCode:
      body
    val.add p.read() # stop code
  else:
    for _ in 0 ..< readMinorValue(p, val, c.minor):
      body

template parseRawArrayLike(
    p: var CborParser, val: var CborRaw, limit: int, body: untyped
) =
  assert p.peek().major in {majorArray, majorMap}
  enterNestedStructure(p)
  let c = p.peek()
  var rawLen = 0
  parseRawArrayLikeImpl(p, val):
    inc rawLen
    if limit > 0 and rawLen > limit:
      raiseUnexpectedValue(c.major.toMeaning & " length reached")
    body
  exitNestedStructure(p)

template parseRawStringLikeImpl(p: var CborParser, val: var CborRaw, body: untyped) =
  assert p.peek().major in {majorBytes, majorText}
  let c = p.read()
  val.add c
  if c.minor == minorIndef:
    while p.peek() != breakStopCode:
      let c2 = p.read()
      val.add c2
      if c2.major != c.major:
        raiseUnexpectedValue(c.major.toMeaning, c2.major.toMeaning)
      for _ in 0 ..< readMinorValue(p, val, c2.minor):
        body
    val.add p.read() # stop code
  else:
    for _ in 0 ..< readMinorValue(p, val, c.minor):
      body

proc parseRawStringLike(
    p: var CborParser, val: var CborRaw, limit: int
) {.gcsafe, raises: [IOError, CborReaderError].} =
  assert p.peek().major in {majorBytes, majorText}
  let c = p.peek()
  var rawLen = 0
  parseRawStringLikeImpl(p, val):
    inc rawLen
    if limit > 0 and rawLen > limit:
      raiseUnexpectedValue(c.major.toMeaning & " length reached")
    val.add p.read()

proc cborKind*(p: CborParser): CborValueKind {.raises: [IOError, CborReaderError].} =
  let c = p.peek()
  case c.major
  of majorUnsigned, majorNegative:
    CborValueKind.Number
  of majorBytes:
    CborValueKind.Bytes
  of majorText:
    CborValueKind.String
  of majorArray:
    CborValueKind.Array
  of majorMap:
    CborValueKind.Object
  of majorTag:
    case c.minor
    of 2, 3: CborValueKind.Number
    else: CborValueKind.Tag
  of majorSimple: # or majorFloat
    if c.minor in minorLen0 + {minorLen1}:
      case c.minor
      of simpleFalse, simpleTrue: CborValueKind.Bool
      of simpleNull: CborValueKind.Null
      of simpleUndefined: CborValueKind.Undefined
      else: CborValueKind.Simple
    else:
      CborValueKind.Float
  else:
    raiseUnexpectedValue("major type expected", $c.major)

proc toInt*(
    p: var CborParser, val: CborNumber, T: type SomeSignedInt, portable: bool
): T {.raises: [CborReaderError].} =
  if val.sign == CborSign.Neg:
    if val.integer.uint64 > T.high.uint64 + 1:
      raiseIntOverflow(val.integer, true)
    elif val.integer == T.high.uint64 + 1:
      result = T.low
    else:
      result = -T(val.integer)
  else:
    if val.integer > T.high.uint64:
      raiseIntOverflow(val.integer, false)
    result = T(val.integer)

  if portable and result.int64 > maxPortableInt.int64:
    raiseIntOverflow(result.BiggestUInt, false)
  if portable and result.int64 < minPortableInt.int64:
    raiseIntOverflow(result.BiggestUInt, true)

proc toInt*(
    p: var CborParser, val: CborNumber, T: type SomeUnsignedInt, portable: bool
): T {.raises: [CborReaderError].} =
  if val.sign == CborSign.Neg:
    raiseUnexpectedValue("negative int", "unsigned int")
  if val.integer > T.high.uint64:
    raiseIntOverflow(val.integer, false)

  if portable and val.integer > maxPortableInt.uint64:
    raiseIntOverflow(val.integer.BiggestUInt, false)

  T(val.integer)

proc parseInt*(
    r: var CborReader, T: type SomeInteger, portable: bool = false
): T {.raises: [IOError, CborReaderError].} =
  var val: CborNumber[uint64]
  r.parser.parseInt(val)
  r.parser.toInt(val, T, portable)

proc parseByteString*(
    r: var CborReader, limit: int
): seq[byte] {.gcsafe, raises: [IOError, CborReaderError].} =
  r.parser.parseByteString(limit, result)

proc parseByteString*(
    r: var CborReader
): seq[byte] {.gcsafe, raises: [IOError, CborReaderError].} =
  r.parser.parseByteString(r.parser.conf.byteStringLengthLimit, result)

proc parseString*(
    r: var CborReader, limit: int
): string {.gcsafe, raises: [IOError, CborReaderError].} =
  r.parser.parseString(limit, result)

proc parseString*(
    r: var CborReader
): string {.gcsafe, raises: [IOError, CborReaderError].} =
  r.parser.parseString(r.parser.conf.stringLengthLimit, result)

template parseArray*(r: var CborReader, body: untyped) =
  parseArray(r.parser, idx, body)

template parseArray*(r: var CborReader, idx, body: untyped) =
  parseArray(r.parser, idx, body)

template skipNullFields(r: CborReader): untyped =
  mixin flavorSkipNullFields
  type
    Reader = typeof r
    Flavor = Reader.Flavor

  const skipNullFields = flavorSkipNullFields(Flavor)
  skipNullFields

template parseObject*(r: var CborReader, key: untyped, body: untyped) =
  parseObject(r.parser, r.skipNullFields, key, body)

template parseTag*(p: var CborReader, tag: untyped, body: untyped) =
  parseTag(r.parser, tag, body)

proc parseNumberImpl[F, T](
    r: var CborReader[F]
): CborNumber[T] {.raises: [IOError, CborReaderError].} =
  r.parser.parseInt(result)

template parseNumber*(r: var CborReader, T: type): auto =
  ## workaround Nim inablity to instantiate result type
  ## when one the argument is generic type and the other
  ## is a typedesc
  type F = typeof(r)
  parseNumberImpl[F.Flavor, T](r)

proc parseNumber*(
    r: var CborReader, val: var CborNumber
) {.raises: [IOError, CborReaderError].} =
  r.parser.parseInt(val)

proc parseFloat*(
    r: var CborReader, T: type SomeFloat
): T {.raises: [IOError, CborReaderError].} =
  r.parser.parseFloat(T)

proc parseSimpleValue*(
    r: var CborReader
): CborSimpleValue {.raises: [IOError, CborReaderError].} =
  r.parser.parseSimpleValue(result)

proc parseBool*(r: var CborReader): bool {.raises: [IOError, CborReaderError].} =
  let val = r.parseSimpleValue()
  if val.int == simpleTrue or val.int == simpleFalse:
    val.int == simpleTrue
  else:
    raiseUnexpectedValue("bool", $val)

proc parseValue(
    p: var CborParser, val: var CborVoid
) {.raises: [IOError, CborReaderError].} =
  case p.cborKind()
  of CborValueKind.Number:
    parseInt(p, val)
  of CborValueKind.Bytes:
    parseByteString(p, val)
  of CborValueKind.String:
    parseString(p, val)
  of CborValueKind.Array:
    parseArray(p, idx):
      parseValue(p, val)
  of CborValueKind.Object:
    parseObjectImpl(p, false):
      parseValue(p, val)
    do:
      parseValue(p, val)
  of CborValueKind.Bool, CborValueKind.Null, CborValueKind.Undefined,
      CborValueKind.Simple:
    var sv: CborSimpleValue
    parseSimpleValue(p, sv)
  of CborValueKind.Float:
    discard parseFloat(p, float64)
  of CborValueKind.Tag:
    var tag: uint64
    parseTag(p, tag):
      parseValue(p, val)

proc parseValue[T](
    p: var CborParser, val: var CborValueRef[T]
) {.raises: [IOError, CborReaderError].} =
  val = CborValueRef[T](kind: p.cborKind())
  case val.kind
  of CborValueKind.Number:
    parseInt(p, val.numVal)
  of CborValueKind.Bytes:
    parseByteString(p, val.bytesVal)
  of CborValueKind.String:
    parseString(p, val.strVal)
  of CborValueKind.Array:
    parseArray(p, idx):
      let lastPos = val.arrayVal.len
      val.arrayVal.setLen(lastPos + 1)
      parseValue(p, val.arrayVal[lastPos])
  of CborValueKind.Object:
    parseObject(p, false, key):
      var v: CborValueRef[T]
      parseValue(p, v)
      val.objVal[key] = v
  of CborValueKind.Bool:
    var sv: CborSimpleValue
    parseSimpleValue(p, sv)
    val.boolVal = sv.isTrue
  of CborValueKind.Null, CborValueKind.Undefined:
    var sv: CborSimpleValue
    parseSimpleValue(p, sv)
  of CborValueKind.Simple:
    var sv: CborSimpleValue
    parseSimpleValue(p, sv)
    val.simpleVal = sv
  of CborValueKind.Float:
    val.floatVal = parseFloat(p, float64)
  of CborValueKind.Tag:
    var tag: uint64
    parseTag(p, tag):
      val.tagVal = CborTag[CborValueRef[T]](tag: tag)
      parseValue(p, val.tagVal.val)

proc parseValueImpl[F, T](
    r: var CborReader[F]
): CborValueRef[T] {.raises: [IOError, CborReaderError].} =
  parseValue(r.parser, result)

template parseValue*(r: var CborReader, T: type): auto =
  ## workaround Nim inablity to instantiate result type
  ## when one the argument is generic type and the other
  ## is a typedesc
  type F = typeof(r)
  parseValueImpl[F.Flavor, T](r)

proc parseValue*(
    r: var CborReader, val: var CborValueRef
) {.raises: [IOError, CborReaderError].} =
  parseValue(r.parser, val)

proc parseValue*(
    r: var CborReader, val: var CborRaw
) {.raises: [IOError, CborReaderError].} =
  template p(): untyped =
    r.parser

  let c = p.peek()
  case c.major
  of majorUnsigned, majorNegative:
    parseRawHead(p, val)
  of majorBytes:
    parseRawStringLike(p, val, p.conf.byteStringLengthLimit)
  of majorText:
    parseRawStringLike(p, val, p.conf.stringLengthLimit)
  of majorArray:
    parseRawArrayLike(p, val, p.conf.arrayElementsLimit):
      parseValue(r, val)
  of majorMap:
    parseRawArrayLike(p, val, p.conf.objectMembersLimit):
      parseValue(r, val)
      parseValue(r, val)
  of majorTag:
    enterNestedStructure(p)
    parseRawHead(p, val)
    parseValue(r, val)
    exitNestedStructure(p)
  of majorSimple: # or majorFloat
    parseRawHead(p, val)
  else:
    raiseUnexpectedValue("major type expected", $c.major)

template parseObjectCustomKey*(r: var CborReader, keyAction, body: untyped) =
  parseObjectImpl(r.parser, r.skipNullFields, keyAction, body)

proc skipSingleValue*(r: var CborReader) {.raises: [IOError, CborReaderError].} =
  var val: CborVoid
  r.parser.parseValue(val)

proc customIntHandler*(
    r: var CborReader, handler: CustomIntHandler
) {.raises: [IOError, CborReaderError].} =
  ## Apply the `handler` argument function for parsing only integer part
  ## of CborNumber
  var val: CborNumber[string]
  parseNumber(r, val)
  for c in val.integer:
    handler(ord(c) - ord('0'))

proc customNumberHandler*(
    r: var CborReader, handler: CustomNumberHandler
) {.raises: [IOError, CborReaderError].} =
  ## Apply the `handler` argument function for parsing complete CborNumber
  var val: CborNumber[string]
  parseNumber(r, val)
  handler(SignPart, val.sign.toInt)
  for c in val.integer:
    handler(IntegerPart, ord(c) - ord('0'))

proc customStringHandler*(
    r: var CborReader, limit: int, handler: CustomStringHandler
) {.raises: [IOError, CborReaderError].} =
  ## Apply the `handler` argument function for parsing a String type
  ## value.
  let val = r.parseString(limit)
  for c in val:
    handler(c)

template customIntValueIt*(r: var CborReader, body: untyped) =
  ## Convenience wrapper around `customIntHandler()` for parsing integers.
  ##
  ## The `body` argument represents a virtual function body. So the current
  ## digit processing can be exited with `return`.
  var handler: CustomIntHandler = proc(digit: int) =
    let it {.inject.} = digit
    body
  r.customIntHandler(handler)

template customNumberValueIt*(r: var CborReader, body: untyped) =
  ## Convenience wrapper around `customIntHandler()` for parsing numbers.
  ##
  ## The `body` argument represents a virtual function body. So the current
  ## digit processing can be exited with `return`.
  let handler: CustomNumberHandler = proc(part: NumberPart, digit: int) =
    let it {.inject.} = digit
    let part {.inject.} = part
    body
  r.customNumberHandler(handler)

# !!!: don't change limit from untyped to int, it will trigger Nim bug
# the second overloaded customStringValueIt will fail to compile
template customStringValueIt*(r: var CborReader, limit: untyped, body: untyped) =
  ## Convenience wrapper around `customStringHandler()` for parsing a text
  ## terminating with a double quote character '"'.
  ##
  ## The `body` argument represents a virtual function body. So the current
  ## character processing can be exited with `return`.
  let handler: CustomStringHandler = proc(c: char) =
    let it {.inject.} = c
    body
  r.customStringHandler(limit, handler)

template customStringValueIt*(r: var CborReader, body: untyped) =
  ## Convenience wrapper around `customStringHandler()` for parsing a text
  ## terminating with a double quote character '"'.
  ##
  ## The `body` argument represents a virtual function body. So the current
  ## character processing can be exited with `return`.
  let handler: CustomStringHandler = proc(c: char) =
    let it {.inject.} = c
    body
  r.customStringHandler(r.parser.conf.stringLengthLimit, handler)

{.pop.}
