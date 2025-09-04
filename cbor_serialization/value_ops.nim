# cbor-serialization
# Copyright (c) 2025-2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/[tables], ./types

proc len*(n: CborValueRef): int =
  ## If `n` is a `CborValueKind.Array`, it returns the number of elements.
  ## If `n` is a `CborValueKind.Object`, it returns the number of pairs.
  ## Else it returns 0.
  case n.kind
  of CborValueKind.Array:
    result = n.arrayVal.len
  of CborValueKind.Object:
    result = n.objVal.len
  else:
    discard

proc `[]`*(node: CborValueRef, name: string): CborValueRef {.inline.} =
  ## Gets a field from a `CborValueKind.Object`, which must not be nil.
  assert(not isNil(node))
  assert(node.kind == CborValueKind.Object)
  node.objVal.getOrDefault(name, nil)

proc `[]`*(node: CborValueRef, index: int): CborValueRef {.inline.} =
  ## Gets the node at `index` in an Array. Result is undefined if `index`
  ## is out of bounds, but as long as array bound checks are enabled it will
  ## result in an exception.
  assert(not isNil(node))
  assert(node.kind == CborValueKind.Array)
  node.arrayVal[index]

proc contains*(node: CborValueRef, key: string): bool =
  ## Checks if `key` exists in `node`.
  assert(node.kind == CborValueKind.Object)
  node.objVal.hasKey(key)

proc contains*(node: CborValueRef, val: CborValueRef): bool =
  ## Checks if `val` exists in array `node`.
  assert(node.kind == CborValueKind.Array)
  find(node.arrayVal, val) >= 0

proc `[]=`*(obj: CborValueRef, key: string, val: CborValueRef) {.inline.} =
  ## Sets a field from a `CborValueKind.Object`.
  assert(obj.kind == CborValueKind.Object)
  obj.objVal[key] = val

proc `[]=`*(obj: CborValueRef, index: int, val: CborValueRef) {.inline.} =
  ## Sets a field from a `CborValueKind.Array`.
  assert(obj.kind == CborValueKind.Array)
  obj.arrayVal[index] = val

proc `{}`*(node: CborValueRef, keys: varargs[string]): CborValueRef =
  ## Traverses the node and gets the given value. If any of the
  ## keys do not exist, returns ``nil``. Also returns ``nil`` if one of the
  ## intermediate data structures is not an object.
  result = node
  for key in keys:
    if isNil(result) or result.kind != CborValueKind.Object:
      return nil
    result = result.objVal.getOrDefault(key)

proc getOrDefault*(node: CborValueRef, key: string): CborValueRef =
  ## Gets a field from a `node`. If `node` is nil or not an object or
  ## value at `key` does not exist, returns nil
  if not isNil(node) and node.kind == CborValueKind.Object:
    result = node.objVal.getOrDefault(key)

proc delete*(obj: CborValueRef, key: string) =
  ## Deletes ``obj[key]``.
  assert(obj.kind == CborValueKind.Object)
  if not obj.objVal.hasKey(key):
    raise newException(IndexDefect, "key not in object")
  obj.objVal.del(key)

func compare*(lhs, rhs: CborValueRef): bool

func compareObject(lhs, rhs: CborValueRef): bool =
  ## assume lhs.len >= rhs.len
  ## null field and no field are treated equals
  for k, v in lhs.objVal:
    let rhsVal = rhs.objVal.getOrDefault(k, nil)
    if rhsVal.isNil:
      if v.kind != CborValueKind.Null:
        return false
      else:
        continue
    if not compare(rhsVal, v):
      return false
  true

func compare*(lhs, rhs: CborValueRef): bool =
  ## The difference between `==` and `compare`
  ## lies in the object comparison. Null field `compare`
  ## to non existent field will return true.
  ## On the other hand, `==` will return false.

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
    if lhs.objVal.len >= rhs.objVal.len:
      compareObject(lhs, rhs)
    else:
      compareObject(rhs, lhs)
  of CborValueKind.Array:
    if lhs.arrayVal.len != rhs.arrayVal.len:
      return false
    for i, x in lhs.arrayVal:
      if not compare(x, rhs.arrayVal[i]):
        return false
    true
  of CborValueKind.Tag:
    lhs.tagVal.tag == rhs.tagVal.tag and compare(lhs.tagVal.val, rhs.tagVal.val)
  of CborValueKind.Simple:
    lhs.simpleVal == rhs.simpleVal
  of CborValueKind.Bool:
    lhs.boolVal == rhs.boolVal
  of CborValueKind.Null, CborValueKind.Undefined:
    true

{.pop.}
