# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/[math]

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
