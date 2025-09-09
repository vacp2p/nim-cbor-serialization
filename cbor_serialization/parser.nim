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

template peek(p: CborParser): byte =
  if not p.stream.readable:
    p.raiseUnexpectedValue("unexpected eof")
  inputs.peek(p.stream)

template read(p: CborParser): byte =
  if not p.stream.readable:
    p.raiseUnexpectedValue("unexpected eof")
  inputs.read(p.stream)

func minorLen(minor: uint8): int =
  assert minor in cborMinorLens
  if minor < cborMinorLen1:
    0
  else:
    1 shl (minor - cborMinorLen1)

# https://www.rfc-editor.org/rfc/rfc8949#section-3
proc readMinorValue(
    p: CborParser, minor: uint8
): uint64 {.raises: [IOError, CborReaderError].} =
  if minor in cborMinorLen0:
    minor.uint64
  elif minor in cborMinorLens:
    # https://www.rfc-editor.org/rfc/rfc8949#section-3-3.4
    var res = 0'u64
    for _ in 0 ..< minor.minorLen():
      res = (res shl 8) or p.read()
    res
  else:
    p.raiseUnexpectedValue("argument len", "value: " & $minor)

# https://www.rfc-editor.org/rfc/rfc8949#section-3-2
func major(x: byte): CborMajor =
  CborMajor(x shr 5)

func minor(x: byte): uint8 =
  x and 0b0001_1111

func `$`(major: CborMajor): string =
  case major
  of CborMajor.Unsigned: "unsigned integer"
  of CborMajor.Negative: "negative integer"
  of CborMajor.Bytes: "byte string"
  of CborMajor.Text: "text string"
  of CborMajor.Array: "array"
  of CborMajor.Map: "map"
  of CborMajor.Tag: "tag"
  of CborMajor.SimpleOrFloat: "simple/float/break"

template parseStringLikeImpl(
    p: var CborParser, majorExpected: CborMajor, body: untyped
) =
  let c = p.read()
  if c.major != majorExpected:
    p.raiseUnexpectedValue($majorExpected, $c.major)
  if c.minor == cborMinorIndef:
    # https://www.rfc-editor.org/rfc/rfc8949#section-3.2.3
    while p.peek() != cborBreakStopCode:
      let c2 = p.read()
      if c2.major != majorExpected:
        p.raiseUnexpectedValue($majorExpected, $c2.major)
      for _ in 0 ..< readMinorValue(p, c2.minor):
        body
    discard p.read() # stop code
  else:
    # https://www.rfc-editor.org/rfc/rfc8949#section-3-3.2
    for _ in 0 ..< readMinorValue(p, c.minor):
      body

iterator parseStringLikeIt(
    p: var CborParser, majorExpected: CborMajor, limit: int
): byte {.inline, raises: [IOError, CborReaderError].} =
  var strLen = 0
  parseStringLikeImpl(p, majorExpected):
    inc strLen
    if limit > 0 and strLen > limit:
      p.raiseUnexpectedValue($majorExpected & " length limit reached")
    yield p.read()

proc parseStringLike[T](
    p: var CborParser, majorExpected: CborMajor, limit: int, val: var T
) {.raises: [IOError, CborReaderError].} =
  when T isnot (string or seq[byte] or CborVoid):
    {.fatal: "`parseStringLike` only accepts string or `seq[byte]` or `CborVoid`".}
  for v in parseStringLikeIt(p, majorExpected, limit):
    when T is CborVoid:
      discard v
    elif T is string:
      val.add v.char
    else:
      val.add v

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.6
proc parseByteString[T](
    p: var CborParser, limit: int, val: var T
) {.raises: [IOError, CborReaderError].} =
  parseStringLike[T](p, CborMajor.Bytes, limit, val)

proc parseByteString[T](
    p: var CborParser, val: var T
) {.raises: [IOError, CborReaderError].} =
  parseByteString[T](p, p.conf.byteStringLengthLimit, val)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.8
proc parseString[T](
    p: var CborParser, limit: int, val: var T
) {.raises: [IOError, CborReaderError].} =
  parseStringLike[T](p, CborMajor.Text, limit, val)

proc parseString[T](
    p: var CborParser, val: var T
) {.raises: [IOError, CborReaderError].} =
  parseString[T](p, p.conf.stringLengthLimit, val)

template enterNestedStructure(p: CborParser) =
  inc p.currDepth
  if p.conf.nestedDepthLimit > 0 and p.currDepth > p.conf.nestedDepthLimit:
    p.raiseUnexpectedValue("`nestedDepthLimit` reached")

template exitNestedStructure(p: CborParser) =
  dec p.currDepth

template parseArrayLike(p: var CborParser, majorExpected: CborMajor, body: untyped) =
  enterNestedStructure(p)
  let c = p.read()
  if c.major != majorExpected:
    p.raiseUnexpectedValue($majorExpected, $c.major)
  if c.minor == cborMinorIndef:
    # https://www.rfc-editor.org/rfc/rfc8949#section-3.2.2
    while p.peek() != cborBreakStopCode:
      body
    discard p.read() # stop code
  else:
    # https://www.rfc-editor.org/rfc/rfc8949#section-3-3.2
    for _ in 0 ..< readMinorValue(p, c.minor):
      body
  exitNestedStructure(p)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.10
template parseArray(p: var CborParser, idx, body: untyped) =
  var idx {.inject.} = 0
  parseArrayLike(p, CborMajor.Array):
    if p.conf.arrayElementsLimit > 0 and idx + 1 > p.conf.arrayElementsLimit:
      p.raiseUnexpectedValue("`arrayElementsLimit` reached")
    body
    inc idx

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.12
template parseObjectImpl(p: var CborParser, skipNullFields, keyAction, body: untyped) =
  var numElem = 0
  parseArrayLike(p, CborMajor.Map):
    inc numElem
    if p.conf.objectMembersLimit > 0 and numElem > p.conf.objectMembersLimit:
      p.raiseUnexpectedValue("`objectMembersLimit` reached")
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

# https://www.rfc-editor.org/rfc/rfc8949#section-3.4
template parseTag(p: var CborParser, tag: var uint64, body: untyped) =
  enterNestedStructure(p)
  let c = p.read()
  if c.major != CborMajor.Tag:
    p.raiseUnexpectedValue($CborMajor.Tag, $c.major)
  tag = p.readMinorValue(c.minor)
  body
  exitNestedStructure(p)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.2
# https://www.rfc-editor.org/rfc/rfc8949#section-3.1-2.4
proc parseNumberImpl(
    p: var CborParser, val: var CborNumber
) {.raises: [IOError, CborReaderError].} =
  let c = p.read()
  val.sign =
    case c.major
    of CborMajor.Unsigned:
      CborSign.None
    of CborMajor.Negative:
      CborSign.Neg
    else:
      p.raiseUnexpectedValue("number", $c.major)
  val.integer = p.readMinorValue(c.minor)

proc parseNumberImpl(
    p: var CborParser, val: var CborVoid
) {.raises: [IOError, CborReaderError].} =
  let c = p.read()
  if c.major notin {CborMajor.Unsigned, CborMajor.Negative}:
    p.raiseUnexpectedValue("number", $c.major)
  discard p.readMinorValue(c.minor)

proc parseNumber[T](
    p: var CborParser, val: var T
) {.raises: [IOError, CborReaderError].} =
  when T isnot (CborNumber or CborVoid):
    {.fatal: "`parseNumber` only accepts `CborNumber` and `CborVoid`".}
  parseNumberImpl(p, val)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.3
proc parseFloat(
    p: var CborParser, T: type SomeFloat
): T {.raises: [IOError, CborReaderError].} =
  let c = p.read()
  if c.major != CborMajor.SimpleOrFloat:
    p.raiseUnexpectedValue("float value", $c.major)
  let val = p.readMinorValue(c.minor)
  if c.minor == cborMinorLen2:
    decodeHalf(val.uint16).T
  elif c.minor == cborMinorLen4:
    cast[float32](val.uint32).T
  elif c.minor == cborMinorLen8:
    when T is (float or float64):
      cast[float64](val).T
    else:
      p.raiseUnexpectedValue($T, "float64")
  else:
    p.raiseUnexpectedValue("float value argument", $c.minor)

# https://www.rfc-editor.org/rfc/rfc8949#section-3.3
proc parseSimpleValue(
    p: var CborParser, val: var CborSimpleValue
) {.raises: [IOError, CborReaderError].} =
  let c = p.read()
  if c.major != CborMajor.SimpleOrFloat:
    p.raiseUnexpectedValue("simple value", $c.major)
  if c.minor notin cborMinorLen0 + {cborMinorLen1}:
    p.raiseUnexpectedValue("simple value argument", $c.minor)
  val = p.readMinorValue(c.minor).CborSimpleValue

proc readMinorValue(
    p: var CborParser, val: var CborBytes, minor: uint8
): uint64 {.raises: [IOError, CborReaderError].} =
  if minor in cborMinorLen0:
    minor.uint64
  elif minor in cborMinorLens:
    var res = 0'u64
    var m: byte
    for _ in 0 ..< minor.minorLen():
      m = p.read()
      res = (res shl 8) or m
      val.add m
    res
  else:
    p.raiseUnexpectedValue("argument len", "value: " & $minor)

proc parseRawHead(
    p: var CborParser, val: var CborBytes
) {.raises: [IOError, CborReaderError].} =
  assert p.peek().major in
    {CborMajor.Unsigned, CborMajor.Negative, CborMajor.Tag, CborMajor.SimpleOrFloat}
  let c = p.read()
  val.add c
  discard readMinorValue(p, val, c.minor)

template parseRawArrayLikeImpl(p: var CborParser, val: var CborBytes, body: untyped) =
  assert p.peek().major in {CborMajor.Array, CborMajor.Map}
  let c = p.read()
  val.add c
  if c.minor == cborMinorIndef:
    while p.peek() != cborBreakStopCode:
      body
    val.add p.read() # stop code
  else:
    for _ in 0 ..< readMinorValue(p, val, c.minor):
      body

template parseRawArrayLike(
    p: var CborParser, val: var CborBytes, limit: int, body: untyped
) =
  assert p.peek().major in {CborMajor.Array, CborMajor.Map}
  enterNestedStructure(p)
  let c = p.peek()
  var rawLen = 0
  parseRawArrayLikeImpl(p, val):
    inc rawLen
    if limit > 0 and rawLen > limit:
      p.raiseUnexpectedValue($c.major & " length reached")
    body
  exitNestedStructure(p)

template parseRawStringLikeImpl(p: var CborParser, val: var CborBytes, body: untyped) =
  assert p.peek().major in {CborMajor.Bytes, CborMajor.Text}
  let c = p.read()
  val.add c
  if c.minor == cborMinorIndef:
    while p.peek() != cborBreakStopCode:
      let c2 = p.read()
      val.add c2
      if c2.major != c.major:
        p.raiseUnexpectedValue($c.major, $c2.major)
      for _ in 0 ..< readMinorValue(p, val, c2.minor):
        body
    val.add p.read() # stop code
  else:
    for _ in 0 ..< readMinorValue(p, val, c.minor):
      body

proc parseRawStringLike(
    p: var CborParser, val: var CborBytes, limit: int
) {.raises: [IOError, CborReaderError].} =
  assert p.peek().major in {CborMajor.Bytes, CborMajor.Text}
  let c = p.peek()
  var rawLen = 0
  parseRawStringLikeImpl(p, val):
    inc rawLen
    if limit > 0 and rawLen > limit:
      p.raiseUnexpectedValue($c.major & " length reached")
    val.add p.read()

# https://www.rfc-editor.org/rfc/rfc8949#section-3.1
proc cborKind*(p: CborParser): CborValueKind {.raises: [IOError, CborReaderError].} =
  let c = p.peek()
  case c.major
  of CborMajor.Unsigned:
    CborValueKind.Unsigned
  of CborMajor.Negative:
    CborValueKind.Negative
  of CborMajor.Bytes:
    CborValueKind.Bytes
  of CborMajor.Text:
    CborValueKind.String
  of CborMajor.Array:
    CborValueKind.Array
  of CborMajor.Map:
    CborValueKind.Object
  of CborMajor.Tag:
    CborValueKind.Tag
  of CborMajor.SimpleOrFloat:
    if c.minor in cborMinorLen0 + {cborMinorLen1}:
      case c.minor.CborSimpleValue
      of cborFalse, cborTrue: CborValueKind.Bool
      of cborNull: CborValueKind.Null
      of cborUndefined: CborValueKind.Undefined
      else: CborValueKind.Simple
    else:
      CborValueKind.Float

proc parseInt*(
    r: var CborReader, T: type SomeInteger
): T {.raises: [IOError, CborReaderError].} =
  var val: CborNumber
  r.parser.parseNumber(val)
  when T is SomeUnsignedInt:
    if val.sign == CborSign.Neg:
      r.parser.raiseUnexpectedValue("negative int", "unsigned int")
  toInt(val, T).valueOr:
    r.parser.raiseIntOverflow(val.integer, val.sign == CborSign.Neg)

iterator parseStringLikeIt(
    r: var CborReader, limit: int, safeBreak: static[bool], T: type
): byte {.inline, raises: [IOError, CborReaderError].} =
  let majorType =
    when T is string:
      CborMajor.Text
    elif T is seq[byte]:
      CborMajor.Bytes
    else:
      {.fatal: "`parseStringLikeIt` seq[byte] or string expected".}
  when safeBreak:
    var s: T
    r.parser.parseStringLike(majorType, limit, s)
    for x in s:
      yield x.byte
  else:
    for x in r.parser.parseStringLikeIt(majorType, limit):
      yield x

proc parseByteString*(
    r: var CborReader, limit: int
): seq[byte] {.raises: [IOError, CborReaderError].} =
  r.parser.parseByteString(limit, result)

proc parseByteString*(
    r: var CborReader
): seq[byte] {.raises: [IOError, CborReaderError].} =
  r.parser.parseByteString(r.parser.conf.byteStringLengthLimit, result)

iterator parseByteStringIt*(
    r: var CborReader, limit: int, safeBreak: static[bool] = true
): byte {.inline, raises: [IOError, CborReaderError].} =
  for x in r.parseStringLikeIt(limit, safeBreak, seq[byte]):
    yield x

iterator parseByteStringIt*(
    r: var CborReader, safeBreak: static[bool] = true
): byte {.inline, raises: [IOError, CborReaderError].} =
  for x in r.parseByteStringIt(r.parser.conf.byteStringLengthLimit, safeBreak):
    yield x

proc parseString*(
    r: var CborReader, limit: int
): string {.raises: [IOError, CborReaderError].} =
  r.parser.parseString(limit, result)

proc parseString*(r: var CborReader): string {.raises: [IOError, CborReaderError].} =
  r.parser.parseString(r.parser.conf.stringLengthLimit, result)

iterator parseStringIt*(
    r: var CborReader, limit: int, safeBreak: static[bool] = true
): char {.inline, raises: [IOError, CborReaderError].} =
  for x in r.parseStringLikeIt(limit, safeBreak, string):
    yield x.char

iterator parseStringIt*(
    r: var CborReader, safeBreak: static[bool] = true
): char {.inline, raises: [IOError, CborReaderError].} =
  for x in r.parseStringIt(r.parser.conf.stringLengthLimit, safeBreak):
    yield x

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

proc parseNumber*(
    r: var CborReader, val: var CborNumber
) {.raises: [IOError, CborReaderError].} =
  r.parser.parseNumber(val)

proc parseNumber*(
    r: var CborReader
): CborNumber {.raises: [IOError, CborReaderError].} =
  r.parser.parseNumber(result)

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
  if val in {cborTrue, cborFalse}:
    val == cborTrue
  else:
    r.parser.raiseUnexpectedValue("bool", $val)

proc parseValue(
    p: var CborParser, val: var CborVoid
) {.raises: [IOError, CborReaderError].} =
  case p.cborKind()
  of CborValueKind.Unsigned, CborValueKind.Negative:
    parseNumber(p, val)
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

proc parseValue(
    p: var CborParser, val: var CborValueRef
) {.raises: [IOError, CborReaderError].} =
  val = CborValueRef(kind: p.cborKind())
  case val.kind
  of CborValueKind.Unsigned, CborValueKind.Negative:
    parseNumber(p, val.numVal)
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
      var v: CborValueRef
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
      val.tagVal = CborTag[CborValueRef](tag: tag)
      parseValue(p, val.tagVal.val)

proc parseValue*(
    r: var CborReader, val: var CborValueRef
) {.raises: [IOError, CborReaderError].} =
  parseValue(r.parser, val)

proc parseValue*(
    r: var CborReader
): CborValueRef {.raises: [IOError, CborReaderError].} =
  parseValue(r.parser, result)

proc parseValue*(
    r: var CborReader, val: var CborBytes
) {.raises: [IOError, CborReaderError].} =
  template p(): untyped =
    r.parser

  let c = p.peek()
  case c.major
  of CborMajor.Unsigned, CborMajor.Negative:
    parseRawHead(p, val)
  of CborMajor.Bytes:
    parseRawStringLike(p, val, p.conf.byteStringLengthLimit)
  of CborMajor.Text:
    parseRawStringLike(p, val, p.conf.stringLengthLimit)
  of CborMajor.Array:
    parseRawArrayLike(p, val, p.conf.arrayElementsLimit):
      parseValue(r, val)
  of CborMajor.Map:
    parseRawArrayLike(p, val, p.conf.objectMembersLimit):
      parseValue(r, val)
      parseValue(r, val)
  of CborMajor.Tag:
    enterNestedStructure(p)
    parseRawHead(p, val)
    parseValue(r, val)
    exitNestedStructure(p)
  of CborMajor.SimpleOrFloat:
    parseRawHead(p, val)

template parseObjectCustomKey*(r: var CborReader, keyAction, body: untyped) =
  parseObjectImpl(r.parser, r.skipNullFields, keyAction, body)

proc skipSingleValue*(r: var CborReader) {.raises: [IOError, CborReaderError].} =
  var val: CborVoid
  r.parser.parseValue(val)

{.pop.}
