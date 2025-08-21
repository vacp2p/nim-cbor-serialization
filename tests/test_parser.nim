# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[strutils, os],
  faststreams,
  stew/[byteutils],
  unittest2,
  ../cbor_serialization/parser,
  ../cbor_serialization/value_ops,
  ./utils

createCborFlavor NullFields, skipNullFields = true

func toReader(input: seq[byte]): CborReader[DefaultFlavor] =
  var stream = unsafeMemoryInput(input)
  CborReader[DefaultFlavor].init(stream)

func toReaderNullFields(input: seq[byte]): CborReader[NullFields] =
  var stream = unsafeMemoryInput(input)
  CborReader[NullFields].init(stream)

suite "Custom iterators":
  test "customIntValueIt":
    var value: int
    var r = toReader "0x1A04A10CA7".unhex # 77663399
    r.customIntValueIt:
      value = value * 10 + it
    check value == 77663399

  test "customNumberValueIt":
    var value: int
    var r = toReader "0x187B".unhex # 123
    r.customNumberValueIt:
      if part == IntegerPart:
        value = value * 10 + it
    check:
      value == 123

  test "customStringValueIt":
    var text: string
    var r = toReader "0x6D68656C6C6F200920776F726C64".unhex # "hello \t world"
    r.customStringValueIt:
      text.add it

    expect CborReaderError:
      r.customStringValueIt(10):
        text.add it

    check text == "hello \t world"

suite "Public parser":
  test "parseArray":
    proc parse(
        r: var CborReader, list: var seq[bool]
    ) {.gcsafe, raises: [IOError, CborReaderError].} =
      r.parseArray:
        list.add r.parseBool()

    var r = toReader "0x83F5F5F4".unhex # [true, true, false]
    var list: seq[bool]
    r.parse(list)
    check list.len == 3
    check list == @[true, true, false]

  test "parseArray with idx":
    proc parse(
        r: var CborReader, list: var seq[bool]
    ) {.gcsafe, raises: [IOError, CborReaderError].} =
      r.parseArray(i):
        list.add (i mod 2) == 0
        list.add r.parseBool()

    var r = toReader "0x83F5F5F4".unhex # [true, true, false]
    var list: seq[bool]
    r.parse(list)
    check list.len == 6
    check list == @[true, true, false, true, true, false]

  test "parseObject":
    type Duck = object
      id: string
      ok: bool

    proc parse(r: var CborReader, list: var seq[Duck]) =
      r.parseObject(key):
        list.add Duck(id: key, ok: r.parseBool())

    var r = toReader "0xA26161F56162F4".unhex # {"a": true, "b": false}
    var list: seq[Duck]
    r.parse(list)

    check list.len == 2
    check list == @[Duck(id: "a", ok: true), Duck(id: "b", ok: false)]

  test "parseNumber uint64":
    var r = toReader "0x3904D1".unhex # -1234
    let val = r.parseNumber(uint64)
    check:
      val.sign == CborSign.Neg
      val.integer == 1234

  test "parseNumber string":
    var r = toReader "0x3904D1".unhex # -1234
    let val = r.parseNumber(string)
    check:
      val.sign == CborSign.Neg
      val.integer == "1234"

  func highPlus(T: type): string =
    result = $(T.high)
    result[^1] = char(result[^1].int + 1)

  func lowMin(T: type): string =
    result = $(T.low)
    result[^1] = char(result[^1].int + 1)

  proc cborNum(s: string, sign: CborSign): seq[byte] =
    CborNumber[string](integer: s, sign: sign).toCbor()

  template testParseIntI(T: type) =
    var r = toReader cborNum($(T.high), CborSign.None)
    var val = r.parseInt(T)
    check val == T.high

    expect CborReaderError:
      var r = toReader cborNum(highPlus(T), CborSign.None)
      let val = r.parseInt(T)
      discard val

    r = toReader cborNum($(T.low), CborSign.Neg)
    val = r.parseInt(T)
    check val == T.low

    expect CborReaderError:
      var r = toReader cborNum(lowMin(T), CborSign.Neg)
      let val = r.parseInt(T)
      discard val

  template testParseIntU(T: type) =
    var r = toReader cborNum($(T.high), CborSign.None)
    let val = r.parseInt(T)
    check val == T.high

    expect CborReaderError:
      var r = toReader cborNum(highPlus(T), CborSign.None)
      let val = r.parseInt(T)
      discard val

  test "parseInt uint8":
    testParseIntU(uint8)

  test "parseInt int8":
    testParseIntI(int8)

  test "parseInt uint16":
    testParseIntU(uint16)

  test "parseInt int16":
    testParseIntI(int16)

  test "parseInt uint32":
    testParseIntU(uint32)

  test "parseInt int32":
    testParseIntI(int32)

  test "parseInt uint64":
    testParseIntU(uint64)

  test "parseInt int64":
    testParseIntI(int64)

  test "parseInt portable overflow":
    expect CborReaderError:
      var r = toReader (minPortableInt - 1).toCbor()
      let val = r.parseInt(int64, true)
      discard val

    expect CborReaderError:
      var r = toReader (maxPortableInt + 1).toCbor()
      let val = r.parseInt(int64, true)
      discard val

    when sizeof(int) == 8:
      expect CborReaderError:
        var r = toReader (minPortableInt - 1).toCbor()
        let val = r.parseInt(int, true)
        discard val

      expect CborReaderError:
        var r = toReader (maxPortableInt + 1).toCbor()
        let val = r.parseInt(int, true)
        discard val

  test "parseFloat":
    var
      r = toReader "0xFB404C0126E978D4FE".unhex # 56.009 
      val = r.parseFloat(float64)
    check val == 56.009

    r = toReader "0xFACC55A84A".unhex # -56.009e6
    val = r.parseFloat(float64)
    check val == -56009000.0

  proc execParseObject(r: var CborReader): int =
    r.parseObject(key):
      discard key
      discard r.parseValue(uint64)
      inc result

  test "parseObject of null fields":
    # {"something":null, "bool":true, "string":null}
    var r =
      toReaderNullFields "0xA369736F6D657468696E67F664626F6F6CF566737472696E67F6".unhex
    check execParseObject(r) == 1

    # {"something":null,"bool":true,"string":"moon"}
    var y =
      toReader "0xA369736F6D657468696E67F664626F6F6CF566737472696E67646D6F6F6E".unhex
    check execParseObject(y) == 3

    # {"something":null,"bool":true,"string":"moon"}
    var z = toReaderNullFields "0xA369736F6D657468696E67F664626F6F6CF566737472696E67646D6F6F6E".unhex
    check execParseObject(z) == 2

  test "parseVaue of null fields":
    # {"something":null, "bool":true, "string":null}
    var r =
      toReaderNullFields "0xA369736F6D657468696E67F664626F6F6CF566737472696E67F6".unhex
    let n = r.parseValue(uint64)
    check:
      n["something"].kind == CborValueKind.Null
      n["bool"].kind == CborValueKind.Bool
      n["string"].kind == CborValueKind.Null

    # {"something":null,"bool":true,"string":"moon"}
    var y =
      toReader "0xA369736F6D657468696E67F664626F6F6CF566737472696E67646D6F6F6E".unhex
    let z = y.parseValue(uint64)
    check:
      z["something"].kind == CborValueKind.Null
      z["bool"].kind == CborValueKind.Bool
      z["string"].kind == CborValueKind.String

  test "CborValueRef comparison":
    var x = CborValueRef[uint64](kind: CborValueKind.Null)
    var n = CborValueRef[uint64](nil)
    check x != n
    check n != x
    check x == x
    check n == n

#{
#  "string" : "hello world",
#  "number" : -123.456,
#  "int":    789,
#  "bool"  : true    ,
#  "null"  : null  ,
#  "array"  : [  true, 567.89  ,   "string in array"  , null, [ 123 ] ],
#  "object" : {
#    "abc"   : 444.008 ,
#    "def": false
#  }
#}
const cborText =
  "0xA766737472696E676B68656C6C6F20776F726C64666E756D626572FBC05EDD2F1A9FBE7763696E7419031564626F6F6CF5646E756C6CF665617272617985F5FB4081BF1EB851EB856F737472696E6720696E206172726179F681187B666F626A656374A263616263FB407BC020C49BA5E363646566F4"

#{
#  "bignum": 9999999999999999999999999999999999999999999,
#  "float": 124.123,
#  "int": -12345
#}
const cborBigNum =
  "0xA3666269676E756DC25272CB5BD86321E38CB6CE6682E7FFFFFFFFFF65666C6F6174FB405F07DF3B645A1D63696E74393038"

suite "Parse to runtime dynamic structure":
  test "parseValue":
    var r = toReader(cborText.unhex)
    let n = r.parseValue(uint64)
    check:
      n["string"].strVal == "hello world"
      n["bool"].boolVal == true
      n["int"].numVal.integer == 789
      n["array"].len == 5
      n["array"][0].boolVal == true
      n["array"][2].strVal == "string in array"
      n["array"][3].kind == CborValueKind.Null
      n["array"][4].kind == CborValueKind.Array
      n["array"][4].len == 1
      n["object"]["def"].boolVal == false

  test "parseValue bignum":
    var r = toReader(cborBigNum.unhex)
    let n = r.parseValue(string)
    check:
      n["bignum"].kind == CborValueKind.Number
      n["bignum"].numVal.integer == "9999999999999999999999999999999999999999999"

  test "parseValue bignum overflow":
    var r = toReader(cborBigNum.unhex)
    expect CborReaderError:
      discard r.parseValue(uint64)

  test "nim v2 regression #23233":
    # Nim compiler bug #23233 will prevent
    # compilation if both CborValueRef[uint64] and CborValueRef[string]
    # are instantiated at together.
    var r1 = toReader(cborText.unhex)
    let n1 = r1.parseValue(uint64)
    check n1["int"].numVal.integer == 789

    var r2 = toReader(cborText.unhex)
    let n2 = r2.parseValue(string)
    check n2["int"].numVal.integer == "789"
