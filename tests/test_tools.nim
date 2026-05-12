# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  unittest2, ../cbor_serialization, ../cbor_serialization/tools/json_converter, ./utils

type
  EmptyObj = object

  Obj1 = object
    a: int
    b: array[2, int]

  Obj2 = object
    b: string

  Obj3 = object
    a, b, c, d, e: string

  Obj4 = object
    Fun: bool
    Amt: int

  Obj5 = object
    a: Obj2

template enc(s): seq[byte] =
  Cbor.encode(s)

template toJson(s): string =
  toJson(CborBytes(s))

suite "Test CBOR to JSON":
  test "CBOR spec to JSON":
    check:
      toJson(enc(0)) == "0"
      toJson(enc(1)) == "1"
      toJson(enc(10)) == "10"
      toJson(enc(23)) == "23"
      toJson(enc(24)) == "24"
      toJson(enc(25)) == "25"
      toJson(enc(100)) == "100"
      toJson(enc(1000)) == "1000"
      toJson(enc(1000000)) == "1000000"
      toJson(enc(1000000000000)) == "1000000000000"
      toJson(enc(18446744073709551615'u64)) == "18446744073709551615"
      toJson(enc(CborTag[seq[byte]](tag: 2, val: "0x010000000000000000".unhex))) ==
        "\"AQAAAAAAAAAA\""
      #toJson(enc(CborNumber(integer: 18446744073709551615'u64, sign: CborSign.Neg))) == "-18446744073709551616"
      toJson(enc(CborTag[seq[byte]](tag: 3, val: "0x010000000000000000".unhex))) ==
        "\"~AQAAAAAAAAAA\""
      toJson(enc(-1)) == "-1"
      toJson(enc(-10)) == "-10"
      toJson(enc(-100)) == "-100"
      toJson(enc(-1000)) == "-1000"
      toJson(enc(0.0)) == "0.0"
      toJson(enc(-0.0)) == "-0.0"
      toJson(enc(1.0)) == "1.0"
      toJson(enc(1.1)) == "1.1"
      toJson(enc(1.5)) == "1.5"
      toJson(enc(65504.0)) == "65504.0"
      toJson(enc(100000.0)) == "100000.0"
      toJson(enc(3.4028234663852886e+38)) == "3.4028234663852886e+38"
      toJson(enc(1.0e+300)) == "1e+300"
      toJson(enc(5.960464477539063e-8)) == "5.960464477539063e-8"
      toJson(enc(0.00006103515625)) == "0.00006103515625"
      toJson(enc(-4.0)) == "-4.0"
      toJson(enc(-4.1)) == "-4.1"
      toJson(enc(Inf)) == "null"
      toJson(enc(NaN)) == "null"
      toJson(enc(-Inf)) == "null"
      toJson(enc(false)) == "false"
      toJson(enc(true)) == "true"
      toJson(enc(cborNull)) == "null"
      toJson(enc(cborUndefined)) == "null"
      toJson(enc(CborSimpleValue(16))) == "null"
      toJson(enc(CborTag[string](tag: 0, val: "2013-03-21T20:04:00Z"))) ==
        "\"2013-03-21T20:04:00Z\""
      toJson(enc(CborTag[int](tag: 1, val: 1363896240))) == "1363896240"
      toJson(enc(CborTag[float](tag: 1, val: 1363896240.5))) == "1363896240.5"
      toJson(enc(CborTag[seq[byte]](tag: 23, val: @[1, 2, 3, 4]))) ==
        "\"0x01020304\""
      toJson(enc(CborTag[seq[byte]](tag: 24, val: @[100, 73, 69, 84, 70]))) ==
        "\"ZElFVEY\""
      toJson(enc(CborTag[string](tag: 32, val: "http://www.example.com"))) ==
        "\"http://www.example.com\""
      toJson(enc(newSeq[byte]())) == "\"\""
      toJson(enc(@[1.byte, 2, 3, 4])) == "\"AQIDBA\""
      toJson(enc("")) == "\"\""
      toJson(enc("a")) == "\"a\""
      toJson(enc("IETF")) == "\"IETF\""
      toJson(enc("\"\\")) == """"\"\\""""
      toJson(enc("ü")) == "\"ü\""
      toJson(enc("水")) == "\"水\""
      toJson(enc("𐅑")) == "\"𐅑\""
      toJson(enc(newSeq[int]())) == "[]"
      toJson(enc([1, 2, 3])) == "[1,2,3]"
      toJson(
        enc(
          [
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
            22, 23, 24, 25,
          ]
        )
      ) == "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]"
      toJson(enc(EmptyObj())) == "{}"
      toJson(enc(Obj1(a: 1, b: [2, 3]))) == """{"a":1,"b":[2,3]}"""
      toJson(enc(("a", Obj2(b: "c")))) == """["a",{"b":"c"}]"""
      toJson(enc(Obj3(a: "A", b: "B", c: "C", d: "D", e: "E"))) ==
        """{"a":"A","b":"B","c":"C","d":"D","e":"E"}"""
      toJson(enc(Obj5(a: Obj2(b: "c")))) == """{"a":{"b":"c"}}"""
      toJson(enc([[1, 2], [3, 4]])) == "[[1,2],[3,4]]"
