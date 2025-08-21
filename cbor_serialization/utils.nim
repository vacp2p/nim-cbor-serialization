# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/[math, options, algorithm]

template importBigints() =
  import bigints

when compiles(importBigints):
  import pkg/bigints
  export bigints

const hasBigints* = compiles(importBigints)

proc ldexp(x: float64, exp: int): float64 =
  return x * pow(2.0, float64(exp))

# https://www.rfc-editor.org/rfc/rfc8949.html#name-half-precision
proc decodeHalf*(half: uint16): float =
  let exp = (half shr 10) and 0x1f
  let mant = half and 0x3ff
  let val =
    if exp == 0:
      ldexp(mant.float64, -24)
    elif exp != 31:
      ldexp(mant.float64 + 1024, exp.int - 25)
    else:
      if mant == 0: Inf else: NaN
  return
    if (half and 0x8000) != 0:
      -val
    else:
      val

func parseBigInt*(s: string, val: var uint64): bool =
  ## Parse valid digits into val. Return false on overflow.
  const validChars = {'0' .. '9'}
  var i = 0
  val = 0
  while i < s.len:
    if s[i].char in validChars:
      let c = uint64(ord(s[i].char) - ord('0'))
      if val > (uint64.high - c) div 10:
        return false
      val = val * 10 + c
    inc i
  return true

when hasBigints:
  func toBigInt*(s: string): BigInt =
    try:
      return initBigInt(s)
    except ValueError:
      return initBigInt(0)

  func toBytesImpl(bint: BigInt): seq[byte] {.raises: [Exception].} =
    var bint = bint
    result = newSeq[byte]()
    let stop = initBigInt(0)
    let ff = initBigInt(0xff)
    while bint > stop:
      result.add toInt[uint8](bint and ff).get()
      bint = bint shr 8
    if result.len == 0:
      result.add 0'u8
    result.reverse()

  func toBytes*(bint: BigInt): seq[byte] {.raises: [].} =
    # XXX fix bigint `shr` & `and` to not raise Exception
    try:
      return toBytesImpl(bint)
    except Defect as e:
      raise e
    except Exception:
      doAssert false
