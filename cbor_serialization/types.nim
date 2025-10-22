# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/tables, results, serialization/errors

export tables, results, errors

type
  # https://www.rfc-editor.org/rfc/rfc8949#section-3.1
  CborMajor* {.pure.} = enum
    Unsigned = 0
    Negative = 1
    Bytes = 2
    Text = 3
    Array = 4
    Map = 5
    Tag = 6
    SimpleOrFloat = 7

  CborError* = object of SerializationError

  CborVoid* = object ## Marker used for skipping a CBOR value during parsing

  CborBytes* = distinct seq[byte]
    ## A seq[byte] containing valid CBOR.
    ## Used to preserve and pass on parts of CBOR to another parser
    ## or layer without interpreting it further

  CborSign* {.pure.} = enum
    None
    Neg

  CborNumber* = object
    sign*: CborSign
    integer*: uint64

  CborSimpleValue* = distinct uint8

  CborReaderConf* = object
    nestedDepthLimit*: int
    arrayElementsLimit*: int
    objectFieldsLimit*: int
    stringLengthLimit*: int
    byteStringLengthLimit*: int
    bigNumBytesLimit*: int

  CborValueKind* {.pure.} = enum
    Bytes
    String
    Unsigned
    Negative
    Float
    Object
    Array
    Tag
    Simple
    Bool
    Null
    Undefined

  CborTag*[T] = object
    tag*: uint64
    val*: T

  CborObjectType* = OrderedTable[string, CborValueRef]

  CborValueRef* = ref CborValue
  CborValue* = object
    case kind*: CborValueKind
    of CborValueKind.Bytes:
      bytesVal*: seq[byte]
    of CborValueKind.String:
      strVal*: string
    of CborValueKind.Unsigned, CborValueKind.Negative:
      numVal*: CborNumber
    of CborValueKind.Float:
      floatVal*: float64
    of CborValueKind.Object:
      objVal*: CborObjectType
    of CborValueKind.Array:
      arrayVal*: seq[CborValueRef]
    of CborValueKind.Tag:
      tagVal*: CborTag[CborValueRef]
    of CborValueKind.Simple:
      simpleVal*: CborSimpleValue
    of CborValueKind.Bool:
      boolVal*: bool
    of CborValueKind.Null, CborValueKind.Undefined:
      discard

# https://www.rfc-editor.org/rfc/rfc8949#section-3
const
  cborFalse* = 20.CborSimpleValue
  cborTrue* = 21.CborSimpleValue
  cborNull* = 22.CborSimpleValue
  cborUndefined* = 23.CborSimpleValue

# https://www.rfc-editor.org/rfc/rfc8949#section-3
const
  cborMinorLen0* = {0'u8 .. 23'u8}
  cborMinorLen1* = 24'u8
  cborMinorLen2* = 25'u8
  cborMinorLen4* = 26'u8
  cborMinorLen8* = 27'u8
  cborMinorIndef* = 31'u8
  cborMinorLens* = cborMinorLen0 + {cborMinorLen1 .. cborMinorLen8}

# https://www.rfc-editor.org/rfc/rfc8949#section-3.2.1
const cborBreakStopCode* = (7 shl 5) or 31

const defaultCborReaderConf* = CborReaderConf(
  nestedDepthLimit: 512,
  arrayElementsLimit: 0,
  objectFieldsLimit: 0,
  stringLengthLimit: 0,
  byteStringLengthLimit: 0,
  bigNumBytesLimit: 64,
)

proc add*(a: var CborBytes, b: byte) {.borrow.}
proc `==`*(a, b: CborBytes): bool {.borrow.}
proc `==`*(a: CborBytes, b: seq[byte]): bool {.borrow.}
proc `==`*(a: seq[byte], b: CborBytes): bool {.borrow.}

template toBytes*(val: CborBytes): untyped =
  seq[byte](val)

func `==`*(a, b: CborSimpleValue): bool {.borrow.}
func contains*(x: set[uint8], y: CborSimpleValue): bool {.borrow.}

func isTrue*(v: CborSimpleValue): bool =
  v == cborTrue

func isFalse*(v: CborSimpleValue): bool =
  v == cborFalse

func isFalsy*(v: CborSimpleValue): bool =
  v in {cborFalse, cborNull, cborUndefined}

func isNull*(v: CborSimpleValue): bool =
  v == cborNull

func isUndefined*(v: CborSimpleValue): bool =
  v == cborUndefined

func isNullish*(v: CborSimpleValue): bool =
  v in {cborNull, cborUndefined}

func `$`*(v: CborSimpleValue): string =
  if v == cborFalse:
    "false"
  elif v == cborTrue:
    "true"
  elif v == cborNull:
    "null"
  elif v == cborUndefined:
    "undefined"
  else:
    "simple(" & $v.int & ")"

func toInt*(sign: CborSign): int =
  case sign
  of CborSign.None: 1
  of CborSign.Neg: -1

proc toInt*(val: CborNumber, T: type SomeSignedInt): Opt[T] =
  ## Converts a CborNumber to a signed integer, if it fits in `T`.
  if val.sign == CborSign.Neg:
    if val.integer == uint64.high:
      Opt.none(T)
    elif val.integer > T.high.uint64:
      Opt.none(T)
    elif val.integer == T.high.uint64:
      Opt.some(T.low)
    else:
      Opt.some(-T(val.integer + 1))
  else:
    if val.integer > T.high.uint64:
      Opt.none(T)
    else:
      Opt.some(T(val.integer))

proc toInt*(val: CborNumber, T: type SomeUnsignedInt): Opt[T] =
  ## Converts a CborNumber to a unsigned integer, if it fits in `T`.
  if val.sign == CborSign.Neg:
    Opt.none(T)
  elif val.integer > T.high.uint64:
    Opt.none(T)
  else:
    Opt.some(T(val.integer))

func `==`*(lhs, rhs: CborValueRef): bool =
  if lhs.isNil and rhs.isNil:
    return true

  if not lhs.isNil and rhs.isNil:
    return false

  if lhs.isNil and not rhs.isNil:
    return false

  if lhs.kind != rhs.kind:
    return false

  case lhs.kind
  of CborValueKind.Bytes:
    lhs.bytesVal == rhs.bytesVal
  of CborValueKind.String:
    lhs.strVal == rhs.strVal
  of CborValueKind.Unsigned, CborValueKind.Negative:
    lhs.numVal == rhs.numVal
  of CborValueKind.Float:
    lhs.floatVal == rhs.floatVal
  of CborValueKind.Object:
    if lhs.objVal.len != rhs.objVal.len:
      return false
    for k, v in lhs.objVal:
      let rhsVal = rhs.objVal.getOrDefault(k, nil)
      if rhsVal.isNil:
        return false
      if rhsVal != v:
        return false
    true
  of CborValueKind.Array:
    if lhs.arrayVal.len != rhs.arrayVal.len:
      return false
    for i, x in lhs.arrayVal:
      if x != rhs.arrayVal[i]:
        return false
    true
  of CborValueKind.Tag:
    lhs.tagVal == rhs.tagVal
  of CborValueKind.Simple:
    lhs.simpleVal == rhs.simpleVal
  of CborValueKind.Bool:
    lhs.boolVal == rhs.boolVal
  of CborValueKind.Null, CborValueKind.Undefined:
    true

{.pop.}
