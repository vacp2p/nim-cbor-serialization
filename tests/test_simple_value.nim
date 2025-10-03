# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2, ../cbor_serialization

template isFn(val: var set[CborSimpleValue], fn: untyped) =
  for x in 0 .. 31:
    if fn(x.CborSimpleValue):
      val.incl x.CborSimpleValue

suite "Test CborSimpleValue":
  dualTest "to string":
    check $cborTrue == "true"
    check $cborFalse == "false"
    check $cborNull == "null"
    check $cborUndefined == "undefined"
    check $CborSimpleValue(30) == "simple(30)"

  dualTest "isTrue":
    var val: set[CborSimpleValue]
    isFn(val, isTrue)
    check val == {cborTrue}

  dualTest "isFalse":
    var val: set[CborSimpleValue]
    isFn(val, isFalse)
    check val == {cborFalse}

  dualTest "isFalsy":
    var val: set[CborSimpleValue]
    isFn(val, isFalsy)
    check val == {cborFalse, cborNull, cborUndefined}

  dualTest "isNull":
    var val: set[CborSimpleValue]
    isFn(val, isNull)
    check val == {cborNull}

  dualTest "isUndefined":
    var val: set[CborSimpleValue]
    isFn(val, isUndefined)
    check val == {cborUndefined}

  dualTest "isNullish":
    var val: set[CborSimpleValue]
    isFn(val, isNullish)
    check val == {cborNull, cborUndefined}
