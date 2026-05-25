# cbor-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/[macros], stew/shims/macros as stewmacros, ./parser

export CborCddlError

# https://datatracker.ietf.org/doc/html/rfc8610#appendix-D
proc toNimTyp(t: FieldType): NimNode =
  case t.kind
  of fkSimpleType:
    case t.name
    of "any":
      ident"CborValueRef"
    of "uint", "int", "float32", "float64", "float", "bool":
      ident(t.name)
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
      raiseAssert("unsupported type " & $t.name)
    else:
      ident(t.name)
  else:
    raiseAssert("unsupported type " & $t.kind)

proc fromCddlImpl*(s: string): NimNode {.raises: [CborCddlError].} =
  result = newNimNode(nnkTypeSection)
  let schema = parseCddl(s)
  for rule in schema:
    doAssert rule.kind == rkType
    case rule.typeExpr.kind
    of fkMap:
      let fields = newNimNode(nnkRecList)
      for f in rule.typeExpr.fields:
        fields.add newNimNode(nnkIdentDefs).add(
          newNimNode(nnkPostfix).add(ident("*"), ident(f.keyText)),
          toNimTyp(f.typ),
          newEmptyNode(),
        )
      result.add newNimNode(nnkTypeDef).add(
        newNimNode(nnkPostfix).add(ident("*"), ident(rule.name)),
        newEmptyNode(),
        newNimNode(nnkObjectTy).add(newEmptyNode(), newEmptyNode(), fields),
      )
    else:
      raiseAssert("unsupported type " & $rule.typeExpr.kind)
  when defined(CborLogGeneratedTypes):
    result.storeMacroResult(true)

macro fromCddl*(s: static[string]): untyped =
  fromCddlImpl(s)
