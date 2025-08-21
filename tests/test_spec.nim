# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2, ./utils, ../cbor_serialization

template enc(s): string =
  Cbor.encode(s).hex

template decode(s: string, typ: untyped): untyped =
  {.line: instantiationInfo(fullPaths = true).}:
    Cbor.decode(s.unhex, typ)

type
  EmptyObj = object

  Obj1 = object
    a: int
    b: array[2, int]

  Obj2 = object
    a, b, c, d, e: string

  Obj3 = object
    Fun: bool
    Amt: int

suite "Test spec":
  test "encode":
    check enc(0) == "0x00"
    check enc(1) == "0x01"
    check enc(10) == "0x0a"
    check enc(23) == "0x17"
    check enc(24) == "0x1818"
    check enc(25) == "0x1819"
    check enc(100) == "0x1864"
    check enc(1000) == "0x1903e8"
    check enc(1000000) == "0x1a000f4240"
    check enc(1000000000000) == "0x1b000000e8d4a51000"
    check enc(18446744073709551615'u64) == "0x1bffffffffffffffff"
    check enc(CborNumber[string](integer: "18446744073709551616", sign: CborSign.None)) ==
      "0xc249010000000000000000"
    check enc(CborNumber[string](integer: "18446744073709551616", sign: CborSign.Neg)) ==
      "0xc348ffffffffffffffff" # output is a tag
    check enc(CborNumber[string](integer: "18446744073709551617", sign: CborSign.Neg)) ==
      "0xc349010000000000000000"
    check enc(-1) == "0x20"
    check enc(-10) == "0x29"
    check enc(-100) == "0x3863"
    check enc(-1000) == "0x3903e7"
    check enc(0.0) == "0xfa00000000"
    check enc(-0.0) == "0xfa80000000"
    check enc(1.0) == "0xfa3f800000"
    check enc(1.1) == "0xfb3ff199999999999a"
    check enc(1.5) == "0xfa3fc00000"
    check enc(65504.0) == "0xfa477fe000"
    check enc(100000.0) == "0xfa47c35000"
    check enc(3.4028234663852886e+38) == "0xfa7f7fffff"
    check enc(1.0e+300) == "0xfb7e37e43c8800759c"
    check enc(5.960464477539063e-8) == "0xfa33800000"
    check enc(0.00006103515625) == "0xfa38800000"
    check enc(-4.0) == "0xfac0800000"
    check enc(-4.1) == "0xfbc010666666666666"
    check enc(Inf) == "0xf97c00"
    check enc(NaN) == "0xf97e00"
    check enc(-Inf) == "0xf9fc00"
    check enc(false) == "0xf4"
    check enc(true) == "0xf5"
    check enc(cborNull) == "0xf6"
    check enc(cborUndefined) == "0xf7"
    check enc(CborSimpleValue(16)) == "0xf0"
    check enc(CborSimpleValue(255)) == "0xf8ff"
    check enc(CborTag[string](tag: 0, val: "2013-03-21T20:04:00Z")) ==
      "0xc074323031332d30332d32315432303a30343a30305a"
    check enc(CborTag[int](tag: 1, val: 1363896240)) == "0xc11a514b67b0"
    check enc(CborTag[float](tag: 1, val: 1363896240.5)) == "0xc1fb41d452d9ec200000"
    check enc(CborTag[seq[byte]](tag: 23, val: @[1, 2, 3, 4])) == "0xd74401020304"
    check enc(CborTag[seq[byte]](tag: 24, val: @[100, 73, 69, 84, 70])) ==
      "0xd818456449455446"
    check enc(CborTag[string](tag: 32, val: "http://www.example.com")) ==
      "0xd82076687474703a2f2f7777772e6578616d706c652e636f6d"
    check enc(newSeq[byte]()) == "0x40"
    check enc(@[1.byte, 2, 3, 4]) == "0x4401020304"
    check enc("") == "0x60"
    check enc("a") == "0x6161"
    check enc("IETF") == "0x6449455446"
    check enc("\"\\") == "0x62225c"
    check enc("ü") == "0x62c3bc"
    check enc("水") == "0x63e6b0b4"
    check enc("𐅑") == "0x64f0908591"
    check enc(newSeq[int]()) == "0x80"
    check enc([1, 2, 3]) == "0x83010203"
    check enc(
      @[
        numNode(1),
        arrNode(@[numNode(2), numNode(3)]),
        arrNode(@[numNode(4), numNode(5)]),
      ]
    ) == "0x8301820203820405"
    check enc(
      [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
        23, 24, 25,
      ]
    ) == "0x98190102030405060708090a0b0c0d0e0f101112131415161718181819"
    check enc(EmptyObj()) == "0xa0"
    check enc(Obj1(a: 1, b: [2, 3])) == "0xa26161016162820203"
    check enc(@[strNode("a"), objNode({"b": strNode("c")}.toOrderedTable)]) ==
      "0x826161a161626163"
    check enc(Obj2(a: "A", b: "B", c: "C", d: "D", e: "E")) ==
      "0xa56161614161626142616361436164614461656145"

  test "decode":
    check decode("0x00", int) == 0
    check decode("0x01", int) == 1
    check decode("0x0a", int) == 10
    check decode("0x17", int) == 23
    check decode("0x1818", int) == 24
    check decode("0x1819", int) == 25
    check decode("0x1864", int) == 100
    check decode("0x1903e8", int) == 1000
    check decode("0x1a000f4240", int) == 1000000
    check decode("0x1b000000e8d4a51000", int64) == 1000000000000
    check decode("0x1bffffffffffffffff", CborNumber[string]) ==
      CborNumber[string](integer: "18446744073709551615", sign: CborSign.None)
    check decode("0xc249010000000000000000", CborNumber[string]) ==
      CborNumber[string](integer: "18446744073709551616", sign: CborSign.None)
    check decode("0x3bffffffffffffffff", CborNumber[string]) ==
      CborNumber[string](integer: "18446744073709551616", sign: CborSign.Neg)
    check decode("0xc349010000000000000000", CborNumber[string]) ==
      CborNumber[string](integer: "18446744073709551617", sign: CborSign.Neg)
    check decode("0x20", int) == -1
    check decode("0x29", int) == -10
    check decode("0x3863", int) == -100
    check decode("0x3903e7", int) == -1000
    check decode("0xf90000", float) == 0.0
    check decode("0xf98000", float) == -0.0
    check decode("0xf93c00", float) == 1.0
    check decode("0xfb3ff199999999999a", float) == 1.1
    check decode("0xf93e00", float) == 1.5
    check decode("0xf97bff", float) == 65504.0
    check decode("0xfa47c35000", float) == 100000.0
    check decode("0xfa7f7fffff", float) == 3.4028234663852886e+38
    check decode("0xfb7e37e43c8800759c", float) == 1.0e+300
    check decode("0xf90001", float) == 5.960464477539063e-8
    check decode("0xf90400", float) == 0.00006103515625
    check decode("0xf9c400", float) == -4.0
    check decode("0xfbc010666666666666", float) == -4.1
    check decode("0xf97c00", float) == Inf
    check $decode("0xf97e00", float) == "nan"
    check decode("0xf9fc00", float) == -Inf
    check decode("0xfa7f800000", float) == Inf
    check $decode("0xfa7fc00000", float) == "nan"
    check decode("0xfaff800000", float) == -Inf
    check decode("0xfb7ff0000000000000", float) == Inf
    check $decode("0xfb7ff8000000000000", float) == "nan"
    check decode("0xfbfff0000000000000", float) == -Inf
    check decode("0xf4", bool) == false
    check decode("0xf5", bool) == true
    check decode("0xf6", CborSimpleValue) == cborNull
    check decode("0xf7", CborSimpleValue) == cborUndefined
    check decode("0xf0", CborSimpleValue) == CborSimpleValue(16)
    check decode("0xf8ff", CborSimpleValue) == CborSimpleValue(255)
    check decode("0xc074323031332d30332d32315432303a30343a30305a", CborTag[string]) ==
      CborTag[string](tag: 0, val: "2013-03-21T20:04:00Z")
    check decode("0xc11a514b67b0", CborTag[int]) == CborTag[int](
      tag: 1, val: 1363896240
    )
    check decode("0xc1fb41d452d9ec200000", CborTag[float]) ==
      CborTag[float](tag: 1, val: 1363896240.5)
    check decode("0xd74401020304", CborTag[seq[byte]]) ==
      CborTag[seq[byte]](tag: 23, val: @[1, 2, 3, 4])
    check decode("0xd818456449455446", CborTag[seq[byte]]) ==
      CborTag[seq[byte]](tag: 24, val: @[100, 73, 69, 84, 70])
    check decode(
      "0xd82076687474703a2f2f7777772e6578616d706c652e636f6d", CborTag[string]
    ) == CborTag[string](tag: 32, val: "http://www.example.com")
    check decode("0x40", seq[byte]) == newSeq[byte]()
    check decode("0x4401020304", seq[byte]) == @[1.byte, 2, 3, 4]
    check decode("0x60", string) == ""
    check decode("0x6161", string) == "a"
    check decode("0x6449455446", string) == "IETF"
    check decode("0x62225c", string) == "\"\\"
    check decode("0x62c3bc", string) == "ü"
    check decode("0x63e6b0b4", string) == "水"
    check decode("0x64f0908591", string) == "𐅑"
    check decode("0x80", seq[int]) == newSeq[int]()
    check decode("0x83010203", seq[int]) == @[1, 2, 3]
    check decode("0x83010203", array[3, int]) == [1, 2, 3]
    check decode("0x8301820203820405", seq[CborValueRef[uint64]]) ==
      @[
        numNode(1),
        arrNode(@[numNode(2), numNode(3)]),
        arrNode(@[numNode(4), numNode(5)]),
      ]
    check decode(
      "0x98190102030405060708090a0b0c0d0e0f101112131415161718181819", seq[int]
    ) ==
      @[
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
        23, 24, 25,
      ]
    check decode("0xa0", EmptyObj) == EmptyObj()
    # XXX support {1: 2, 3: 4} 0xa201020304
    check decode("0xa26161016162820203", Obj1) == Obj1(a: 1, b: [2, 3])
    check decode("0x826161a161626163", seq[CborValueRef[uint64]]) ==
      @[strNode("a"), objNode({"b": strNode("c")}.toOrderedTable)]
    check decode("0xa56161614161626142616361436164614461656145", Obj2) ==
      Obj2(a: "A", b: "B", c: "C", d: "D", e: "E")
    check decode("0x5f42010243030405ff", seq[byte]) == @[1.byte, 2, 3, 4, 5]
    check decode("0x7f657374726561646d696e67ff", string) == "streaming"
    check decode("0x9fff", seq[int]) == newSeq[int]()
    check decode("0x9f018202039f0405ffff", seq[CborValueRef[uint64]]) ==
      @[
        numNode(1),
        arrNode(@[numNode(2), numNode(3)]),
        arrNode(@[numNode(4), numNode(5)]),
      ]
    check decode("0x9f01820203820405ff", seq[CborValueRef[uint64]]) ==
      @[
        numNode(1),
        arrNode(@[numNode(2), numNode(3)]),
        arrNode(@[numNode(4), numNode(5)]),
      ]
    check decode("0x83018202039f0405ff", seq[CborValueRef[uint64]]) ==
      @[
        numNode(1),
        arrNode(@[numNode(2), numNode(3)]),
        arrNode(@[numNode(4), numNode(5)]),
      ]
    check decode("0x83019f0203ff820405", seq[CborValueRef[uint64]]) ==
      @[
        numNode(1),
        arrNode(@[numNode(2), numNode(3)]),
        arrNode(@[numNode(4), numNode(5)]),
      ]
    check decode(
      "0x9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff", seq[int]
    ) ==
      @[
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
        23, 24, 25,
      ]
    check decode("0xbf61610161629f0203ffff", Obj1) == Obj1(a: 1, b: [2, 3])
    check decode("0x826161bf61626163ff", seq[CborValueRef[uint64]]) ==
      @[strNode("a"), objNode({"b": strNode("c")}.toOrderedTable)]
    check decode("0xbf6346756ef563416d7421ff", Obj3) == Obj3(Fun: true, Amt: -2)
