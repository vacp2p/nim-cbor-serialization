# cbor-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2, ./utils, ../cbor_serialization

suite "Malformed data tests":
  test "Byte array of len int64.high div 2":
    # byte string of len (int64.high / 2) and content "01020304"
    let cbor = "0x5b3fffffffffffffff01020304".unhex
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, CborValueRef)
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, seq[byte])
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, CborBytes)

  test "String of len int64.high div 2":
    # string of len (int64.high / 2) and content "abcd"
    let cbor = "0x7b3fffffffffffffff61626364".unhex
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, CborValueRef)
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, string)
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, CborBytes)

  test "Array of len int64.high div 2":
    # array of len (int64.high / 2) and content "01020304"
    let cbor = "0x9b3fffffffffffffff01020304".unhex
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, CborValueRef)
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, seq[int])
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, CborBytes)

  test "Map of len int64.high div 2":
    # map of len (int64.high / 2) and content "01020304"
    let cbor = "bb3fffffffffffffff01020304".unhex
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, CborValueRef)
    expect CborNotEnoughBytesError:
      discard Cbor.decode(cbor, CborBytes)
