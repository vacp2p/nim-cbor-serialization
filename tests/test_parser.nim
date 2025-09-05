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
    let val = r.parseNumber()
    check:
      val.toInt(int) == Opt.some(-1234)
      val.sign == CborSign.Neg
      val.integer == 1233

  func highPlus(T: type): uint64 =
    result = T.high.uint64
    result += 1

  proc cborNum(x: uint64, sign: CborSign): seq[byte] =
    CborNumber(integer: x, sign: sign).toCbor()

  template testParseIntI(T: type) =
    var r = toReader cborNum(T.high.uint64, CborSign.None)
    var val = r.parseInt(T)
    check val == T.high

    expect CborReaderError:
      var r = toReader cborNum(highPlus(T), CborSign.None)
      let val = r.parseInt(T)
      discard val

    r = toReader cborNum(T.high.uint64, CborSign.Neg)
    val = r.parseInt(T)
    check val == T.low

    expect CborReaderError:
      var r = toReader cborNum(highPlus(T), CborSign.Neg)
      let val = r.parseInt(T)
      discard val

  template testParseIntU(T: type) =
    var r = toReader cborNum(T.high.uint64, CborSign.None)
    let val = r.parseInt(T)
    check val == T.high

    when T isnot uint64:
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
      discard r.parseValue()
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
    let n = r.parseValue()
    check:
      n["something"].kind == CborValueKind.Null
      n["bool"].kind == CborValueKind.Bool
      n["string"].kind == CborValueKind.Null

    # {"something":null,"bool":true,"string":"moon"}
    var y =
      toReader "0xA369736F6D657468696E67F664626F6F6CF566737472696E67646D6F6F6E".unhex
    let z = y.parseValue()
    check:
      z["something"].kind == CborValueKind.Null
      z["bool"].kind == CborValueKind.Bool
      z["string"].kind == CborValueKind.String

  test "CborValueRef comparison":
    var x = CborValueRef(kind: CborValueKind.Null)
    var n = CborValueRef(nil)
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

suite "Parse to runtime dynamic structure":
  test "parseValue":
    var r = toReader(cborText.unhex)
    let n = r.parseValue()
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
