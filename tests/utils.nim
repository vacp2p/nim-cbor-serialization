# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2, stew/[byteutils], ../cbor_serialization

export toCbor, toHex

proc unhex*(s: string): seq[byte] =
  s.hexToSeqByte

proc hex*(s: seq[byte]): string =
  s.to0xHex

proc checkCbor*[T](cbor: seq[byte], val: T) =
  check Cbor.decode(cbor, T) == val

proc numNode*(x: int): CborValueRef =
  CborValueRef(
    kind: CborValueKind.Number,
    numVal: CborNumber(integer: x.uint64, sign: CborSign.None),
  )

proc arrNode*(x: seq[CborValueRef]): CborValueRef =
  CborValueRef(kind: CborValueKind.Array, arrayVal: x)

template objNode*(x): CborValueRef =
  CborValueRef(kind: CborValueKind.Object, objVal: x)

proc strNode*(x: string): CborValueRef =
  CborValueRef(kind: CborValueKind.String, strVal: x)

proc boolNode*(x: bool): CborValueRef =
  CborValueRef(kind: CborValueKind.Bool, boolVal: x)

proc nullNode*(): CborValueRef =
  CborValueRef(kind: CborValueKind.Null)

proc floatNode*(x: float): CborValueRef =
  CborValueRef(kind: CborValueKind.Float, floatVal: x)
