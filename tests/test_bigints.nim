# cbor-serialization
# Copyright (c) 2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  unittest2, bigints, ./utils, ../cbor_serialization, ../cbor_serialization/pkg/bigints

suite "Test BigInt":
  dualTest "Spec unsigned bignum tag encode":
    let val = "18446744073709551616".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0xc249010000000000000000".unhex

  dualTest "Spec negative bignum tag encode":
    let val = "-18446744073709551617".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0xc349010000000000000000".unhex

  dualTest "Spec unsigned bignum tag decode":
    let val = "0xc249010000000000000000".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "18446744073709551616".initBigInt

  dualTest "Spec negative bignum tag decode":
    let val = "0xc349010000000000000000".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "-18446744073709551617".initBigInt

  dualTest "Spec unsigned int encode":
    let val = "18446744073709551615".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0x1bffffffffffffffff".unhex

  dualTest "Spec negative int encode":
    let val = "-18446744073709551616".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0x3bffffffffffffffff".unhex

  dualTest "Spec unsigned int decode":
    let val = "0x1bffffffffffffffff".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "18446744073709551615".initBigInt

  dualTest "Spec negative int decode":
    let val = "0x3bffffffffffffffff".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "-18446744073709551616".initBigInt

  dualTest "Spec small int encode":
    let val = "1".initBigInt
    let cbor = Cbor.encode(val)
    check cbor == "0x01".unhex

  dualTest "Spec small int decode":
    let val = "0x01".unhex
    let cbor = Cbor.decode(val, BigInt)
    check cbor == "1".initBigInt

  dualTest "Tag Bignum bigNumBytesLimit":
    let val = (initBigInt(1) shl 128) - initBigInt(1)
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, BigInt) == val
      Cbor.decode(cbor, BigInt, conf = CborReaderConf(bigNumBytesLimit: 16)) == val
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, BigInt, conf = CborReaderConf(bigNumBytesLimit: 15))

  dualTest "Tag negative Bignum bigNumBytesLimit":
    var val = (initBigInt(1) shl 128) - initBigInt(1)
    val *= -1.initBigInt
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, BigInt) == val
      Cbor.decode(cbor, BigInt, conf = CborReaderConf(bigNumBytesLimit: 16)) == val
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, BigInt, conf = CborReaderConf(bigNumBytesLimit: 15))

  dualTest "Tag negative Bignum bigNumBytesLimit":
    # this triggers the limit check for negativeTag
    var val = (initBigInt(1) shl 128) #- initBigInt(1)
    val *= -1.initBigInt
    let cbor = Cbor.encode(val)
    check Cbor.decode(cbor, BigInt) == val
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, BigInt, conf = CborReaderConf(bigNumBytesLimit: 16))
