# cbor-serialization
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/tables,
  serialization/errors

export
  tables,
  errors

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
  minorLen1* = 24
  minorLen2* = 25
  minorLen4* = 26
  minorLen8* = 27
  minorIndef* = 31
  minorLens* = minorLen0 + {minorLen1 .. minorLen8}

const
  minorBreak* = 31

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

  CborVoid* = object

  CborReaderFlag* {.pure.} = enum
    allowUnknownFields
    requireAllFields
    portableInt
    #leadingFraction     # on
    #integerPositiveSign # on

  CborReaderFlags* = set[CborReaderFlag]

  CborSign* {.pure.} = enum
    None
    Neg

  #CborNumberKind* {.pure.} = enum
  #  Int
  #  Float
  #  Decimal

  CborNumber*[T: string or uint64] = object
    #kind*: CborNumberKind
    sign*: CborSign
    integer*: T
    #expSign*: CborSign
    #exp*: T

  CborSimpleValue* = distinct uint8

  CborValueKind* {.pure.} = enum
    Bytes
    String
    Number
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

  CborObjectType*[T: string or uint64] = OrderedTable[string, CborValueRef[T]]

  CborValueRef*[T: string or uint64] = ref CborValue[T]
  CborValue*[T: string or uint64] = object
    case kind*: CborValueKind
    of CborValueKind.Bytes:
      bytesVal*: seq[byte]
    of CborValueKind.String:
      strVal*: string
    of CborValueKind.Number:
      numVal*: CborNumber[T]
    of CborValueKind.Float:
      floatVal*: float64
    of CborValueKind.Object:
      objVal*: CborObjectType[T]
    of CborValueKind.Array:
      arrayVal*: seq[CborValueRef[T]]
    of CborValueKind.Tag:
      tagVal*: CborTag[CborValueRef[T]]
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
  minPortableInt* = -9007199254740991 # -2**53 + 1
  maxPortableInt* =  9007199254740991 # +2**53 - 1

  defaultCborReaderFlags*: set[CborReaderFlag] = {}

func minorLen*(minor: uint8): int =
  assert minor in minorLens
  if minor < minorLen1: 0 else: 1 shl (minor-minorLen1)

func toMeaning*(major: uint8): string =
  case major
  of majorUnsigned: "unsigned integer"
  of majorNegative: "negative integer"
  of majorBytes: "byte string"
  of majorText: "text string"
  of majorArray: "array"
  of majorMap: "map"
  of majorTag: "tag"
  of majorFloat: "simple/float/break"
  else: "unknown/invalid"

func isTrue*(v: CborSimpleValue): bool =
  return v.int == simpleTrue

func isFalse*(v: CborSimpleValue): bool =
  return v.int == simpleFalse

func isFalsy*(v: CborSimpleValue): bool =
  return v.int == simpleFalse or
    v.int == simpleNull or
    v.int == simpleUndefined

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

func initialByte*(major, minor: uint8): byte =
  doAssert major <= 7
  doAssert minor <= 31
  return (major shl 5) or minor

func toMinorLen*(val: uint64): uint8 =
  if val < minorLen1:
    val.uint8
  elif val <= uint8.high:
    minorLen1
  elif val <= uint16.high:
    minorLen2
  elif val <= uint32.high:
    minorLen4
  else:
    minorLen8

func toMinorLen*(val: int): uint8 =
  toMinorLen(val.uint64)

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
  of CborValueKind.Number:
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

import faststreams/inputs

type
  VMInputStream* = ref object of InputStream
    pos*: int
    data*: string

proc read*(s: VMInputStream): byte =
  result = byte s.data[s.pos]
  inc s.pos

proc readable*(s: VMInputStream): bool =
  s.pos < s.data.len

proc peek*(s: VMInputStream): byte =
  byte s.data[s.pos]
