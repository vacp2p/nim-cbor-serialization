# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2, ../cbor_serialization, ../cbor_serialization/json_utils, ./utils

const testCases = [
  ("0x00", "0"),
  ("0x01", "1"),
  ("0x0a", "10"),
  ("0x17", "23"),
  ("0x1818", "24"),
  ("0x1819", "25"),
  ("0x1864", "100"),
  ("0x1903e8", "1000"),
  ("0x1a000f4240", "1000000"),
  ("0x1b000000e8d4a51000", "1000000000000"),
  ("0x1bffffffffffffffff", "18446744073709551615"),
  ("0x20", "-1"),
  ("0x29", "-10"),
  ("0x3863", "-100"),
  ("0x3903e7", "-1000"),
  ("0xfb3ff199999999999a", "1.1"),
  ("0xfa47c35000", "100000.0"),
  ("0xfbc010666666666666", "-4.1"),
  ("0xf4", "false"),
  ("0xf5", "true"),
  ("0xf6", "null"),
  ("0x60", "\"\""),
  ("0x6161", "\"a\""),
  ("0x6449455446", "\"IETF\""),
  ("0x62225c", """"\"\\""""),
  ("0x62c3bc", "\"ü\""),
  ("0x63e6b0b4", "\"水\""),
  ("0x64f0908591", "\"𐅑\""),
  ("0x80", "[]"),
  ("0x83010203", "[1,2,3]"),
  ("0x8301820203820405", "[1,[2,3],[4,5]]"),
  (
    "0x98190102030405060708090a0b0c0d0e0f101112131415161718181819",
    "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]",
  ),
  ("0xa0", "{}"),
  ("0xa26161016162820203", """{"a":1,"b":[2,3]}"""),
  ("0x826161a161626163", """["a",{"b":"c"}]"""),
  (
    "0xa56161614161626142616361436164614461656145",
    """{"a":"A","b":"B","c":"C","d":"D","e":"E"}""",
  ),
]

const testCasesNoRountrip = [
  # exponent too large
  ("0xfa7f7fffff", "3.4028234663852886e+38"),
  ("0xfb7e37e43c8800759c", "1e+300"), # 1.0e+300
  # float16; it will encode as float32 in cbor
  ("0xf90000", "0.0"),
  ("0xf98000", "-0.0"),
  ("0xf93c00", "1.0"),
  ("0xf93e00", "1.5"),
  ("0xf97bff", "65504.0"),
  ("0xf90001", "5.960464477539063e-8"),
  ("0xf90400", "0.00006103515625"),
  ("0xf9c400", "-4.0"),
  # substituted
  ("0xf97c00", "null"),
  ("0xf97e00", "null"),
  ("0xf9fc00", "null"),
  ("0xf7", "null"),
  ("0xf0", "null"),
  ("0xf8ff", "null"),
  ("0xfa7f800000", "null"),
  ("0xfa7fc00000", "null"),
  ("0xfaff800000", "null"),
  ("0xfb7ff0000000000000", "null"),
  ("0xfb7ff8000000000000", "null"),
  ("0xfbfff0000000000000", "null"),
  # tags
  ("0xc074323031332d30332d32315432303a30343a30305a", "\"2013-03-21T20:04:00Z\""),
  ("0xc11a514b67b0", "1363896240"),
  ("0xc1fb41d452d9ec200000", "1363896240.5"),
  ("0xd74401020304", "\"0x01020304\""),
  ("0xd818456449455446", "\"ZElFVEY\""),
  ("0xd82076687474703a2f2f7777772e6578616d706c652e636f6d", "\"http://www.example.com\""),
  # byte strings
  ("0xc249010000000000000000", "\"AQAAAAAAAAAA\""),
  ("0xc349010000000000000000", "\"~AQAAAAAAAAAA\""),
  ("0x40", "\"\""),
  ("0x4401020304", "\"AQIDBA\""),
]

suite "Test CBOR to JSON":
  test "CBOR spec to JSON":
    for (cbor, json) in items(testCases):
      check toJson(CborBytes(cbor.unhex)) == json
    for (cbor, json) in items(testCasesNoRountrip):
      check toJson(CborBytes(cbor.unhex)) == json

  test "JSON spec to CBOR":
    for (cbor, json) in items(testCases):
      check toCbor(JsonString(json), definiteLen = true).hex == cbor
