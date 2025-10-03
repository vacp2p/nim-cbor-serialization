# cbor-serialization
# Copyright (c) 2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2, ../cbor_serialization, ../cbor_serialization/value_ops

func cborBool(x: bool): CborValueRef =
  CborValueRef(kind: CborValueKind.Bool, boolVal: x)

func cborNull(): CborValueRef =
  CborValueRef(kind: CborValueKind.Null)

template allValueRefs() {.dirty.} =
  let objA = CborValueRef(
    kind: CborValueKind.Object, objVal: [("a", cborBool(true))].toOrderedTable
  )

  let objA2 = CborValueRef(
    kind: CborValueKind.Object, objVal: [("a", cborBool(true))].toOrderedTable
  )

  let objABNull = CborValueRef(
    kind: CborValueKind.Object,
    objVal: [("a", cborBool(true)), ("b", cborNull())].toOrderedTable,
  )

  let objAB = CborValueRef(
    kind: CborValueKind.Object,
    objVal: [("a", cborBool(true)), ("b", cborBool(true))].toOrderedTable,
  )

  let objInArrayA = CborValueRef(kind: CborValueKind.Array, arrayVal: @[objA])

  let objInArrayA2 = CborValueRef(kind: CborValueKind.Array, arrayVal: @[objA2])

  let objInArrayAB = CborValueRef(kind: CborValueKind.Array, arrayVal: @[objAB])

  let objInArrayABNull = CborValueRef(kind: CborValueKind.Array, arrayVal: @[objABNull])

  let objInObjA =
    CborValueRef(kind: CborValueKind.Object, objVal: [("x", objA)].toOrderedTable)

  let objInObjA2 =
    CborValueRef(kind: CborValueKind.Object, objVal: [("x", objA2)].toOrderedTable)

  let objInObjAB =
    CborValueRef(kind: CborValueKind.Object, objVal: [("x", objAB)].toOrderedTable)

  let objInObjABNull =
    CborValueRef(kind: CborValueKind.Object, objVal: [("x", objABNull)].toOrderedTable)

suite "Test CborValueRef":
  dualTest "Test table keys equality":
    allValueRefs()
    check objA != objAB
    check objA == objA2
    check objA != objABNull
    check objAB != objABNull

    check objInArrayA != objInArrayAB
    check objInArrayA != objInArrayABNull
    check objInArrayA == objInArrayA2
    check objInArrayAB != objInArrayABNull

    check objInObjA != objInObjAB
    check objInObjA != objInObjABNull
    check objInObjA == objInObjA2
    check objInObjAB != objInObjABNull

  dualTest "Test compare":
    allValueRefs()
    check compare(objA, objAB) == false
    check compare(objA, objA2) == true
    check compare(objA, objABNull) == true
    check compare(objAB, objABNull) == false

    check compare(objInArrayA, objInArrayAB) == false
    check compare(objInArrayA, objInArrayABNull) == true
    check compare(objInArrayA, objInArrayA2) == true
    check compare(objInArrayAB, objInArrayABNull) == false

    check compare(objInObjA, objInObjAB) == false
    check compare(objInObjA, objInObjABNull) == true
    check compare(objInObjA, objInObjA2) == true
    check compare(objInObjAB, objInObjABNull) == false
