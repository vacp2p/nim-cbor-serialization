import pkg/bigints

import
  ./[reader_desc, common, utils]

export
  reader_desc

template peek(p: CborParser): byte =
  when nimvm:
    if not types.readable(p.stream.VMInputStream):
      raiseUnexpectedValue(p, "unexpected eof")
    types.peek(p.stream.VMInputStream)
  else:
    if not p.stream.readable:
      raiseUnexpectedValue(p, "unexpected eof")
    inputs.peek(p.stream)

template read(p: CborParser): byte =
  when nimvm:
    if not types.readable(p.stream.VMInputStream):
      raiseUnexpectedValue(p, "unexpected eof")
    types.read(p.stream.VMInputStream)
  else:
    if not p.stream.readable:
      raiseUnexpectedValue(p, "unexpected eof")
    inputs.read(p.stream)

proc read(p: CborParser, n: int): uint64 =
  assert n in 1 .. 8
  result = 0
  for _ in 0 ..< n:
    result = (result shl 8) or p.read()

proc readMinorValue(p: CborParser, minor: uint8): uint64 =
  if minor notin minorLens:
    raiseUnexpectedValue(p, "argument len", "value: " & $minor)
  if minor in minorLen0:
    minor.uint64
  else:
    p.read(minor.minorLen())

template parseStringLike(p: var CborParser, majorExpected: uint8, body: untyped) =
  let c = p.read()
  if c.major != majorExpected:
    raiseUnexpectedValue(p, majorExpected.toMeaning, c.major.toMeaning)
  if c.minor == minorIndef:
    while p.peek() != breakStopCode:
      let c2 = p.read()
      if c2.major != majorExpected:
        raiseUnexpectedValue(p, majorExpected.toMeaning, c.major.toMeaning)
      for _ in 0 ..< readMinorValue(p, c2.minor):
        body
    discard p.read()  # stop code
  else:
    for _ in 0 ..< readMinorValue(p, c.minor):
      body

proc parseByteString[T](p: var CborParser, val: var T)
    {.gcsafe, raises: [IOError, CborReaderError].} =
  when T isnot (string or seq[byte] or CborVoid):
    {.fatal: "`parseByteString` only accepts string or `seq[byte]` or `CborVoid`".}
  parseStringLike(p, majorBytes):
    val.add p.read()

proc parseString[T](p: var CborParser, val: var T)
    {.gcsafe, raises: [IOError, CborReaderError].} =
  when T isnot (string or CborVoid):
    {.fatal: "`parseString` only accepts `string` or `CborVoid`".}
  parseStringLike(p, majorText):
    val.add p.read().char

proc parseString(p: var CborParser): string
    {.gcsafe, raises: [IOError, CborReaderError].} =
  p.parseString(result)

template parseArrayLike(p: var CborParser, majorExpected: uint8, body: untyped) =
  let c = p.read()
  if c.major != majorExpected:
    raiseUnexpectedValue(p, majorExpected.toMeaning, c.major.toMeaning)
  if c.minor == minorIndef:
    while p.peek() != breakStopCode:
      body
    discard p.read()  # stop code
  else:
    for _ in 0 ..< readMinorValue(p, c.minor):
      body

template parseArray(p: var CborParser, idx, body: untyped) =
  var idx {.inject.} = 0
  parseArrayLike(p, majorArray):
    body
    inc idx

template parseObjectImpl(p: var CborParser, skipNullFields, keyAction, body: untyped) =
  parseArrayLike(p, majorMap):
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
    let key {.inject.} = p.parseString()
  do:
    body

template parseTag(p: var CborParser, tag: var uint64, body: untyped) =
  let c = p.read()
  if c.major != majorTag:
    raiseUnexpectedValue(p, "tag", c.major.toMeaning)
  tag = p.readMinorValue(c.minor)
  body

proc parseIntTagValue[T](p: var CborParser, tag: uint64, val: var T)
    {.raises: [IOError, CborReaderError].} =
  val.sign = case tag
    of 2: CborSign.None
    of 3: CborSign.Neg
    else: raiseUnexpectedValue(p, "tag number 2 or 3", $tag)
  var s = newSeq[byte]()
  p.parseByteString(s)  # XXX iterator and skipLeadingZeroes
  var leadingZeroes = 0
  for x in s:
    if x != 0:
      break
    inc leadingZeroes
  when val.integer is string:
    var bint = initBigInt(0)
    for i in leadingZeroes ..< s.len:
      bint = bint shl 8
      inc(bint, s[i].int)
    if val.sign == CborSign.Neg:
      inc(bint, 1)
    val.integer = $bint
  else:
    val.integer = 0
    for i in leadingZeroes ..< s.len:
      if val.integer > uint64.high shr 8:
        raiseIntOverflow(val.integer, val.sign == CborSign.Neg)
      val.integer = (val.integer shl 8) or s[i]
    if val.sign == CborSign.Neg:
      if val.integer == uint64.high:
        raiseIntOverflow(val.integer, true)
      val.integer += 1

proc parseIntTag[T](p: var CborParser, val: var T)
    {.raises: [IOError, CborReaderError].} =
  var tag: uint64
  parseTag(p, tag):
    parseIntTagValue(p, tag, val)

proc parseIntImpl[T](p: var CborParser, val: var T)
    {.raises: [IOError, CborReaderError].} =
  let c = p.read()
  val.sign = case c.major
    of majorUnsigned: CborSign.None
    of majorNegative: CborSign.Neg
    else: raiseUnexpectedValue(p, "number", c.major.toMeaning)
  let integer = p.readMinorValue(c.minor)
  when val.integer is string:
    if c.major == majorNegative and integer == uint64.high:
      var bint = initBigInt(integer)
      inc(bint, 1)
      val.integer = $bint
    else:
      val.integer = $integer
  else:
    val.integer = integer
    if c.major == majorNegative:
      if integer == uint64.high:
        raiseIntOverflow(integer, true)
      val.integer += 1

proc parseInt[T](p: var CborParser, val: var T)
    {.raises: [IOError, CborReaderError].} =
  if p.peek().major == majorTag:
    parseIntTag(p, val)
  else:
    parseIntImpl(p, val)

proc parseFloat(p: var CborParser, T: type SomeFloat): T
    {.gcsafe, raises: [IOError, CborReaderError].} =
  let c = p.read()
  if c.major != majorFloat:
    raiseUnexpectedValue(p, "float value", c.major.toMeaning)
  let val = p.readMinorValue(c.minor)
  if c.minor == minorLen2:
    decodeHalf(val.uint16).T
  elif c.minor == minorLen4:
    cast[float32](val.uint32).T
  elif c.minor == minorLen8:
    when T is (float or float64):
      cast[float64](val).T
    else:
      raiseUnexpectedValue(p, $T, "float64")
  else:
    raiseUnexpectedValue(p, "float value argument", $c.minor)

proc parseSimpleValue[T](p: var CborParser, val: var T)
    {.gcsafe, raises: [IOError, CborReaderError].} =
  when T isnot CborSimpleValue:
    {.fatal: "`parseSimpleValue` only accepts `CborSimpleValue`".}
  let c = p.read()
  if c.major != majorSimple:
    raiseUnexpectedValue(p, "simple value", c.major.toMeaning)
  if c.minor notin minorLen0 + {minorLen1}:
    raiseUnexpectedValue(p, "simple value argument", $c.minor)
  val = p.readMinorValue(c.minor).CborSimpleValue

proc cborKind*(p: CborParser): CborValueKind =
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
    case c.minor:
    of 2, 3: CborValueKind.Number
    else: CborValueKind.Tag
  of majorSimple:  # or majorFloat
    if c.minor in minorLen0 + {minorLen1}:
      case c.minor
      of simpleFalse, simpleTrue: CborValueKind.Bool
      of simpleNull: CborValueKind.Null
      of simpleUndefined: CborValueKind.Undefined
      else: CborValueKind.Simple
    else:
      CborValueKind.Float
  else:
    raiseUnexpectedValue(p, "major type expected", $c.major)

proc minor*(p: CborParser): int =
  p.peek().minor.int

proc toInt*(p: var CborParser, val: CborNumber, T: type SomeSignedInt, portable: bool): T
      {.raises: [CborReaderError].}=
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

proc toInt*(p: var CborParser, val: CborNumber, T: type SomeUnsignedInt, portable: bool): T
      {.raises: [IOError, CborReaderError].}=
  if val.sign == CborSign.Neg:
    raiseUnexpectedValue(p, "negative int", "unsigned int")
  if val.integer > T.high.uint64:
    raiseIntOverflow(val.integer, false)

  if portable and val.integer > maxPortableInt.uint64:
    raiseIntOverflow(val.integer.BiggestUInt, false)

  T(val.integer)

proc parseInt*(r: var CborReader, T: type SomeInteger, portable: bool = false): T
    {.raises: [IOError, CborReaderError].} =
  var val: CborNumber[uint64]
  r.parser.parseInt(val)
  r.parser.toInt(val, T, portable)

proc parseByteString*(r: var CborReader): seq[byte]
    {.gcsafe, raises: [IOError, CborReaderError].} =
  r.parser.parseByteString(result)

proc parseString*(r: var CborReader): string
    {.gcsafe, raises: [IOError, CborReaderError].} =
  r.parser.parseString()

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

proc parseNumber*(r: var CborReader, val: var CborNumber)
    {.raises: [IOError, CborReaderError].} =
  r.parser.parseInt(val)

proc parseFloat*(r: var CborReader, T: type SomeFloat): T
    {.raises: [IOError, CborReaderError].} =
  r.parser.parseFloat(T)

proc parseSimpleValue*(r: var CborReader): CborSimpleValue
    {.raises: [IOError, CborReaderError].} =
  r.parser.parseSimpleValue(result)

proc parseBool*(r: var CborReader): bool
    {.raises: [IOError, CborReaderError].} =
  let val = r.parseSimpleValue()
  if val.int == simpleTrue or val.int == simpleFalse:
    val.int == simpleTrue
  else:
    raiseUnexpectedValue(r.parser, "bool", $val)

proc parseValue[T](p: var CborParser, val: var T) =
  when T isnot CborValueRef:
    {.fatal: "`parseValue` only accepts `CborValueRef`".}
  val = T(kind: p.cborKind())
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
      var v: T
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
      val.tagVal = CborTag[T](tag: tag)
      parseValue(p, val.tagVal.val)

proc parseValueImpl[F,T](r: var CborReader[F]): CborValueRef[T]
    {.raises: [IOError, CborReaderError].} =
  parseValue(r.parser, result)

template parseValue*(r: var CborReader, T: type): auto =
  ## workaround Nim inablity to instantiate result type
  ## when one the argument is generic type and the other
  ## is a typedesc
  type F = typeof(r)
  parseValueImpl[F.Flavor, T](r)

proc parseValue*(r: var CborReader, val: var CborValueRef)
    {.raises: [IOError, CborReaderError].} =
  parseValue[CborValueRef](r.parser, val)

template parseObjectCustomKey*(r: var CborReader, keyAction, body: untyped) =
  parseObjectImpl(r.parser, r.skipNullFields, keyAction, body)

proc skipSingleValue*(r: var CborReader) {.raises: [IOError, CborReaderError].} =
  # XXX CborVoid
  var val: CborValueRef[string]
  r.parser.parseValue(val)
