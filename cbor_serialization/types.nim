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

const
  majorUnsigned* = 0
  majorNegative* = 1
  majorBytes* = 2
  majorText* = 3
  majorArray* = 4
  majorMap* = 5
  majorTag* = 6
  majorFloat* = 7
  majorSimple* = 7
  majorBreak* = 7

const
  minorLen0* = {0'u8 .. 23'u8}
  minorLen1* = 24'u8
  minorLen2* = 25'u8
  minorLen4* = 26'u8
  minorLen8* = 27'u8
  minorIndef* = 31'u8
  minorLens* = minorLen0 + {minorLen1 .. minorLen8}

const minorBreak* = 31

const
  simpleFalse* = 20
  simpleTrue* = 21
  simpleNull* = 22
  simpleUndefined* = 23
  simpleReserved* = {24'u8 .. 31'u8}
  simpleUnassigned* = {0'u8 .. 19'u8, 32'u8 .. 255'u8}

const breakStopCode* = (majorBreak shl 5) or minorBreak

type
  CborError* = object of SerializationError

  CborVoid* = object ## Marker used for skipping a CBOR value during parsing

  CborRaw* = distinct seq[byte]
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

  CborReaderFlag* {.pure.} = enum
    allowUnknownFields
    requireAllFields

  CborReaderFlags* = set[CborReaderFlag]

  CborReaderConf* = object
    nestedDepthLimit*: int
    arrayElementsLimit*: int
    objectMembersLimit*: int
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

const
  cborFalse* = simpleFalse.CborSimpleValue
  cborTrue* = simpleTrue.CborSimpleValue
  cborNull* = simpleNull.CborSimpleValue
  cborUndefined* = simpleUndefined.CborSimpleValue

const
  defaultCborReaderFlags*: set[CborReaderFlag] = {}

  defaultCborReaderConf* = CborReaderConf(
    nestedDepthLimit: 512,
    arrayElementsLimit: 0,
    objectMembersLimit: 0,
    stringLengthLimit: 0,
    byteStringLengthLimit: 0,
    bigNumBytesLimit: 64,
  )

proc add*(a: var CborRaw, b: byte) {.borrow.}
proc `==`*(a, b: CborRaw): bool {.borrow.}
proc `==`*(a: CborRaw, b: seq[byte]): bool {.borrow.}
proc `==`*(a: seq[byte], b: CborRaw): bool {.borrow.}

template toBytes*(val: CborRaw): untyped =
  seq[byte](val)

func isTrue*(v: CborSimpleValue): bool =
  return v.int == simpleTrue

func isFalse*(v: CborSimpleValue): bool =
  return v.int == simpleFalse

func isFalsy*(v: CborSimpleValue): bool =
  return v.int == simpleFalse or v.int == simpleNull or v.int == simpleUndefined

func isNull*(v: CborSimpleValue): bool =
  return v.int == simpleNull

func isUndefined*(v: CborSimpleValue): bool =
  return v.int == simpleUndefined

func isNullish*(v: CborSimpleValue): bool =
  return v.int == simpleNull or v.int == simpleUndefined

func `$`*(v: CborSimpleValue): string =
  if v.isTrue:
    "true"
  elif v.isFalse:
    "false"
  elif v.isNull:
    "null"
  elif v.isUndefined:
    "undefined"
  else:
    "simple value " & $v

func `==`*(a, b: CborSimpleValue): bool =
  return a.int == b.int

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
