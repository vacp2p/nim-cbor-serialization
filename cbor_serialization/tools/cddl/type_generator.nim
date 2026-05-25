# cbor-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/[macros, tables, strutils], stew/shims/macros as stewmacros, ./parser

export CborCddlError

proc newCborCddlError(msg: string): ref CborCddlError =
  (ref CborCddlError)(msg: msg)

# https://datatracker.ietf.org/doc/html/rfc8610#appendix-D
proc toNimTyp(ft: FieldType): NimNode =
  case ft.kind
  of fkSimpleType:
    case ft.name
    of "any":
      ident"CborValueRef"
    of "uint", "int", "float32", "float64", "float", "bool":
      ident(ft.name)
    of "nint":
      ident"int"
    of "float16", "float16-32":
      ident"float32"
    of "float32-64":
      ident"float"
    of "bstr", "bytes":
      newNimNode(nnkBracketExpr).add(ident("seq"), ident("byte"))
    of "tstr", "text":
      ident"string"
    of "tdate", "time", "biguint", "bignint", "bigint", "integer", "unsigned",
        "decfrac", "bigfloat", "eb64url", "eb64legacy", "eb16", "encoded-cbor", "uri",
        "b64url", "b64legacy", "regexp", "mime-message", "cbor-any", "number", "false",
        "true", "nil", "null", "undefined":
      raise newCborCddlError("unsupported type " & $ft.name)
    else:
      ident(ft.name)
  of fkArray:
    if ft.fields.len != 1:
      raise newCborCddlError("unsupported array of len: " & $ft.fields.len)
    let inner = toNimTyp(ft.fields[0].typ)
    newNimNode(nnkBracketExpr).add(ident("seq"), inner)
  else:
    raise newCborCddlError("unsupported type " & $ft.kind)

proc toLitNode(ft: FieldType): NimNode =
  template s(): untyped =
    ft.valueText

  doAssert ft.kind == fkValue
  doAssert s.len > 0
  if s[0] == '"':
    doAssert s.len >= 2
    doAssert s[^1] == '"'
    newLitFixed(s[1 ..< s.high])
  else:
    let val =
      try:
        parseInt(s)
      except ValueError:
        raise newCborCddlError("unsupported value " & s)
    newLitFixed(val)

proc toEnumFieldName(s: string, i: int): NimNode =
  if s.len >= 2 and s[0].isAlphaAscii and s[1].isAlphaAscii:
    ident(toLowerAscii(s[0 .. 1] & $i))
  else:
    ident("e" & $i)

proc literalsMap(cddl: CddlSchema): TableRef[string, FieldType] =
  ## map of rule_name -> literal_val
  result = newTable[string, FieldType]()
  for rule in cddl:
    if rule.kind == rkType and rule.typeExpr.kind == fkValue:
      result[rule.name] = rule.typeExpr

proc fromCddlImpl*(s: string): NimNode {.raises: [CborCddlError].} =
  result = newNimNode(nnkTypeSection)
  let cddl = parseCddl(s)
  let lits = literalsMap(cddl)
  for rule in cddl:
    doAssert rule.kind == rkType
    let value =
      case rule.typeExpr.kind
      of fkMap:
        let fields = newNimNode(nnkRecList)
        for f in rule.typeExpr.fields:
          fields.add newNimNode(nnkIdentDefs).add(
            newNimNode(nnkPostfix).add(ident("*"), ident(f.keyText)),
            toNimTyp(f.typ),
            newEmptyNode(),
          )
        newNimNode(nnkObjectTy).add(newEmptyNode(), newEmptyNode(), fields)
      of fkUnion:
        var fields = default(seq[NimNode])
        for i, variant in rule.typeExpr.variants.pairs():
          case variant.kind
          of fkSimpleType:
            let v = lits.getOrDefault(variant.name, default(FieldType))
            if v.kind == fkUnset:
              raise newCborCddlError("union variant not found: " & $variant.name)
            fields.add newNimNode(nnkEnumFieldDef).add(
              ident(variant.name), toLitNode(v)
            )
          of fkValue:
            fields.add newNimNode(nnkEnumFieldDef).add(
              toEnumFieldName(rule.name, i), toLitNode(variant)
            )
          else:
            raise newCborCddlError("unsupported type " & $variant.kind)
        newNimNode(nnkEnumTy).add(newEmptyNode()).add(fields)
      of fkSimpleType, fkArray:
        toNimTyp(rule.typeExpr)
      of fkValue:
        default(NimNode) # lits map contains this field
      else:
        raise newCborCddlError("unsupported type " & $rule.typeExpr.kind)
    case rule.typeExpr.kind
    of fkValue:
      discard
    of fkUnion:
      result.add newNimNode(nnkTypeDef).add(
        newNimNode(nnkPragmaExpr).add(
          newNimNode(nnkPostfix).add(ident("*"), ident(rule.name)),
          newNimNode(nnkPragma).add(ident("pure")),
        ),
        newEmptyNode(),
        value,
      )
    else:
      result.add newNimNode(nnkTypeDef).add(
        newNimNode(nnkPostfix).add(ident("*"), ident(rule.name)), newEmptyNode(), value
      )
  when defined(CborLogGeneratedTypes):
    result.storeMacroResult(true)

macro fromCddl*(s: static[string]): untyped =
  fromCddlImpl(s)
