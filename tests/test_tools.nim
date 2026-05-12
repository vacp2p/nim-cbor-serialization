# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  unittest2, ../cbor_serialization, ../cbor_serialization/tools/json_convert, ./utils

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

suite "Test CBOR to JSON":
  test "CBOR spec to JSON":
    check:
      cborToJson(enc(0)) == "0"
      cborToJson(enc(1)) == "1"
      cborToJson(enc(10)) == "10"
      cborToJson(enc(23)) == "23"
      cborToJson(enc(24)) == "24"
      cborToJson(enc(25)) == "25"
      cborToJson(enc(100)) == "100"
      cborToJson(enc(1000)) == "1000"
      cborToJson(enc(1000000)) == "1000000"
      cborToJson(enc(1000000000000)) == "1000000000000"
      cborToJson(enc(18446744073709551615'u64)) == "18446744073709551615"
      cborToJson(enc(CborTag[seq[byte]](tag: 2, val: "0x010000000000000000".unhex))) ==
        "\"AQAAAAAAAAAA\""
      #cborToJson(enc(CborNumber(integer: 18446744073709551615'u64, sign: CborSign.Neg))) == "-18446744073709551616"
      cborToJson(enc(CborTag[seq[byte]](tag: 3, val: "0x010000000000000000".unhex))) ==
        "\"~AQAAAAAAAAAA\""
      cborToJson(enc(-1)) == "-1"
      cborToJson(enc(-10)) == "-10"
      cborToJson(enc(-100)) == "-100"
      cborToJson(enc(-1000)) == "-1000"
      cborToJson(enc(0.0)) == "0.0"
      cborToJson(enc(-0.0)) == "-0.0"
      cborToJson(enc(1.0)) == "1.0"
      cborToJson(enc(1.1)) == "1.1"
      cborToJson(enc(1.5)) == "1.5"
      cborToJson(enc(65504.0)) == "65504.0"
      cborToJson(enc(100000.0)) == "100000.0"
      cborToJson(enc(3.4028234663852886e+38)) == "3.4028234663852886e+38"
      cborToJson(enc(1.0e+300)) == "1e+300"
      cborToJson(enc(5.960464477539063e-8)) == "5.960464477539063e-8"
      cborToJson(enc(0.00006103515625)) == "0.00006103515625"
      cborToJson(enc(-4.0)) == "-4.0"
      cborToJson(enc(-4.1)) == "-4.1"
      #cborToJson(enc(Inf)) == "Inf"
      #cborToJson(enc(NaN)) == "NaN"
      #cborToJson(enc(-Inf)) == "-Inf"
      cborToJson(enc(false)) == "false"
      cborToJson(enc(true)) == "true"
      cborToJson(enc(cborNull)) == "null"
      #cborToJson(enc(cborUndefined)) == "undefined"
      #cborToJson(enc(CborSimpleValue(16))) == ""
      cborToJson(enc(CborTag[string](tag: 0, val: "2013-03-21T20:04:00Z"))) ==
        "\"2013-03-21T20:04:00Z\""
      cborToJson(enc(CborTag[int](tag: 1, val: 1363896240))) == "1363896240"
      cborToJson(enc(CborTag[float](tag: 1, val: 1363896240.5))) == "1363896240.5"
      cborToJson(enc(CborTag[seq[byte]](tag: 23, val: @[1, 2, 3, 4]))) ==
        "\"0x01020304\""
      cborToJson(enc(CborTag[seq[byte]](tag: 24, val: @[100, 73, 69, 84, 70]))) ==
        "\"ZElFVEY\""
      cborToJson(enc(CborTag[string](tag: 32, val: "http://www.example.com"))) ==
        "\"http://www.example.com\""
      cborToJson(enc(newSeq[byte]())) == "\"\""
      cborToJson(enc(@[1.byte, 2, 3, 4])) == "\"AQIDBA\""
      cborToJson(enc("")) == "\"\""
      cborToJson(enc("a")) == "\"a\""
      cborToJson(enc("IETF")) == "\"IETF\""
      cborToJson(enc("\"\\")) == """"\"\\""""
      cborToJson(enc("ü")) == "\"ü\""
      cborToJson(enc("水")) == "\"水\""
      cborToJson(enc("𐅑")) == "\"𐅑\""
      cborToJson(enc(newSeq[int]())) == "[]"
      cborToJson(enc([1, 2, 3])) == "[1,2,3]"
      cborToJson(
        enc(
          [
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
            22, 23, 24, 25,
          ]
        )
      ) == "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]"
      cborToJson(enc(EmptyObj())) == "{}"
      cborToJson(enc(Obj1(a: 1, b: [2, 3]))) == """{"a":1,"b":[2,3]}"""
      cborToJson(enc(("a", Obj2(b: "c")))) == """["a",{"b":"c"}]"""
      cborToJson(enc(Obj3(a: "A", b: "B", c: "C", d: "D", e: "E"))) ==
        """{"a":"A","b":"B","c":"C","d":"D","e":"E"}"""
      cborToJson(enc(Obj5(a: Obj2(b: "c")))) == """{"a":{"b":"c"}}"""
      cborToJson(enc([[1,2], [3,4]])) == "[[1,2],[3,4]]"
