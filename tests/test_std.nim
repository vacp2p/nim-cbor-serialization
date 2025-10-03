# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  unittest2,
  ./utils,
  ../cbor_serialization,
  ../cbor_serialization/std/[options, sets, tables]

suite "Test Options":
  dualTest "some":
    let val = some(123)
    let cbor = Cbor.encode(val)
    check cbor.hex == "0x187b"
    checkCbor cbor, 123
    checkCbor cbor, val

  dualTest "none":
    let val = none(int)
    let cbor = Cbor.encode(val)
    check cbor.hex == "0xf6"
    checkCbor cbor, cborNull
    checkCbor cbor, val

suite "Test Sets":
  dualTest "set[int8]":
    let val = {1'i8, 2, 3}
    let cbor = Cbor.encode(val)
    check cbor.hex == "0x9f010203ff"
    checkCbor cbor, val

  dualTest "set[uint8]":
    let val = {1'u8, 2, 3}
    let cbor = Cbor.encode(val)
    check cbor.hex == "0x9f010203ff"
    checkCbor cbor, val

  dualTest "OrderedSet[int]":
    let val = toOrderedSet([1, 2, 3])
    let cbor = Cbor.encode(val)
    check cbor.hex == "0x9f010203ff"
    checkCbor cbor, val

  dualTest "HashSet[int]":
    let val = toHashSet([1, 2, 3])
    let cbor = Cbor.encode(val)
    checkCbor cbor, val

suite "Test Tables":
  dualTest "OrderedTable[int, string]":
    let val = toOrderedTable [(1, "one"), (2, "two")]
    let cbor = Cbor.encode(val)
    check cbor.hex == "0xbf6131636f6e6561326374776fff"
    checkCbor cbor, val

  dualTest "OrderedTable[string, string]":
    let val = toOrderedTable [("1", "one"), ("2", "two")]
    let cbor = Cbor.encode(val)
    check cbor.hex == "0xbf6131636f6e6561326374776fff"
    checkCbor cbor, val

  dualTest "Table[int, string]":
    let val = {1: "one", 2: "two"}.toTable
    let cbor = Cbor.encode(val)
    checkCbor cbor, val

  dualTest "Table[string, string]":
    let val = {"1": "one", "2": "two"}.toTable
    let cbor = Cbor.encode(val)
    checkCbor cbor, val
