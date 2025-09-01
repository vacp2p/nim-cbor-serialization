# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/[math, options, algorithm]
import pkg/bigints, ../../cbor_serialization/[reader, writer]

export bigints

func toBytesImpl(bint: BigInt, bytes: var seq[byte]) {.raises: [Exception].} =
  var bint = bint
  let stop = initBigInt(0)
  let ff = initBigInt(0xff)
  while bint > stop:
    bytes.add toInt[uint8](bint and ff).get()
    bint = bint shr 8
  if bytes.len == 0:
    bytes.add 0'u8
  bytes.reverse()

func toBytes(bint: BigInt, bytes: var seq[byte]) {.raises: [].} =
  # XXX fix bigint `shr` & `and` to not raise Exception
  try:
    toBytesImpl(bint, bytes)
  except Defect as e:
    raise e
  except Exception:
    doAssert false

const maxIntLen = len($(uint64.high)) + 1 # + sign
const unsignedTag = 2
const negativeTag = 3

proc writeValue*(writer: var CborWriter, value: BigInt) {.raises: [IOError].} =
  if value >= 0.initBigInt:
    let sint = toInt[uint64](value)
    if sint.isSome:
      writer.writeValue(CborNumber(sign: CborSign.None, integer: sint.get()))
    else:
      var bintTag = CborTag[seq[byte]](tag: unsignedTag)
      toBytes(value, bintTag.val)
      writer.writeValue(bintTag)
  else:
    var bint = value.abs()
    dec(bint, 1)
    let sint = toInt[uint64](bint)
    if sint.isSome:
      writer.writeValue(CborNumber(sign: CborSign.Neg, integer: sint.get()))
    else:
      var bintTag = CborTag[seq[byte]](tag: negativeTag)
      toBytes(bint, bintTag.val)
      writer.writeValue(bintTag)

proc readValue*(
    reader: var CborReader, value: var BigInt
) {.raises: [IOError, SerializationError].} =
  template p(): untyped =
    reader.parser

  let kind = p.cborKind()
  if kind == CborValueKind.Number:
    var val: CborNumber
    reader.readValue(val)
    value = initBigInt(val.integer)
    if val.sign == CborSign.Neg:
      inc(value, 1)
      value *= -1.initBigInt
    if p.conf.integerDigitsLimit in 1 .. maxIntLen and
        len($value) > p.conf.integerDigitsLimit:
      raiseUnexpectedValue("`integerDigitsLimit` reached")
  elif kind == CborValueKind.Tag:
    var tbint: CborTag[seq[byte]]
    reader.readValue(tbint)
    if tbint.tag notin {unsignedTag, negativeTag}:
      raiseUnexpectedValue("tag number 2 or 3", $tbint.tag)
    value = initBigInt(0)
    var digits = 1
    let bigint10 = initBigInt(10)
    var threshold = bigint10
    var leadingZero = true
    for v in tbint.val:
      leadingZero = leadingZero and v == 0
      if not leadingZero:
        value = value shl 8
        inc(value, v.int)
        if p.conf.integerDigitsLimit > 0:
          while threshold <= value:
            threshold *= bigint10
            inc digits
            if digits > p.conf.integerDigitsLimit:
              raiseUnexpectedValue("`integerDigitsLimit` reached")
    if tbint.tag == negativeTag:
      inc(value, 1)
      if threshold <= value and digits + 1 > p.conf.integerDigitsLimit:
        raiseUnexpectedValue("`integerDigitsLimit` reached")
      value *= -1.initBigInt
  else:
    raiseUnexpectedValue("number", $kind)
