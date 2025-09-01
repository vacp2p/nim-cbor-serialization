# cbor-serialization
# Copyright (c) 2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[strutils],
  unittest2,
  bigints,
  ./utils,
  ../cbor_serialization,
  ../cbor_serialization/pkg/bigints

const cborFlags = defaultCborReaderFlags

suite "Test BigInt":
  test "Spec unsigned bignum tag encode":
    let val = "18446744073709551616".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0xc249010000000000000000".unhex

  test "Spec negative bignum tag encode":
    let val = "-18446744073709551617".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0xc349010000000000000000".unhex

  test "Spec unsigned bignum tag decode":
    let val = "0xc249010000000000000000".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "18446744073709551616".initBigInt

  test "Spec negative bignum tag decode":
    let val = "0xc349010000000000000000".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "-18446744073709551617".initBigInt

  test "Spec unsigned int encode":
    let val = "18446744073709551615".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0x1bffffffffffffffff".unhex

  test "Spec negative int encode":
    let val = "-18446744073709551616".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0x3bffffffffffffffff".unhex

  test "Spec unsigned int decode":
    let val = "0x1bffffffffffffffff".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "18446744073709551615".initBigInt

  test "Spec negative int decode":
    let val = "0x3bffffffffffffffff".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "-18446744073709551616".initBigInt

  test "Spec small int encode":
    let val = "1".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0x01".unhex

  test "Spec small int decode":
    let val = "0x01".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "1".initBigInt

  test "Int integerDigitsLimit":
    let val = 123.initBigInt
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, BigInt) == val
      Cbor.decode(
        cbor, BigInt, flags = cborFlags, conf = CborReaderConf(integerDigitsLimit: 3)
      ) == val
    expect UnexpectedValueError:
      discard Cbor.decode(
        cbor, BigInt, flags = cborFlags, conf = CborReaderConf(integerDigitsLimit: 2)
      )

  test "Tag Bignum integerDigitsLimit":
    let bigNum = repeat('9', 128)
    let val = bigNum.initBigInt
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, BigInt) == val
      Cbor.decode(
        cbor, BigInt, flags = cborFlags, conf = CborReaderConf(integerDigitsLimit: 128)
      ) == val
    expect UnexpectedValueError:
      discard Cbor.decode(
        cbor, BigInt, flags = cborFlags, conf = CborReaderConf(integerDigitsLimit: 127)
      )
