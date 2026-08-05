# cbor-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/[macros, tables, strutils], stew/shims/macros as stewmacros, ./parser2

export CborCddlError

const repeatedMap =
  {CddlOccurKind.ocOneOrMore, CddlOccurKind.ocZeroOrMore, CddlOccurKind.ocRange}

proc newCborCddlError(msg: string): ref CborCddlError =
  (ref CborCddlError)(msg: msg)

# https://datatracker.ietf.org/doc/html/rfc8610#appendix-D
proc toSimpleNimTyp(s: string): NimNode {.raises: [CborCddlError].} =
  case s
  of "any":
    ident"CborBytes"
  of "float32", "float64", "float", "bool":
    ident(s)
  of "uint":
    ident"uint64"
  of "int", "nint":
    ident"int64"
  of "float16", "float16-32":
    ident"float32"
  of "float32-64":
    ident"float"
  of "bstr", "bytes":
    newNimNode(nnkBracketExpr).add(ident("seq"), ident("byte"))
  of "tstr", "text":
    ident"string"
  of "tdate", "time", "biguint", "bignint", "bigint", "integer", "unsigned", "decfrac",
      "bigfloat", "eb64url", "eb64legacy", "eb16", "encoded-cbor", "uri", "b64url",
      "b64legacy", "regexp", "mime-message", "cbor-any", "number", "false", "true",
      "nil", "null", "undefined":
    raise newCborCddlError("unsupported type " & $s)
  else:
    ident(s)

proc entriesOf(n: CddlNode): lent seq[CddlNode] {.raises: [CborCddlError].} =
  ## Members of a map, array or group; a group choice has no Nim equivalent.
  for c in n.children:
    if c.kind == nkGroupChoice:
      raise newCborCddlError("unsupported group choice in " & $n.kind)
  n.children

proc toNimTyp(node: CddlNode, isOptional = false): NimNode {.raises: [CborCddlError].} =
  template n(): untyped =
    node.unparen

  let typ =
    case n.kind
    of nkTypeRef:
      toSimpleNimTyp(n.val.text)
    of nkArray:
      let entries = entriesOf(n)
      if entries.len != 1:
        raise newCborCddlError("unsupported array of len: " & $entries.len)
      let inner = toNimTyp(entries[0].body)
      newNimNode(nnkBracketExpr).add(ident("seq"), inner)
    of nkMap:
      let entries = entriesOf(n)
      if entries.len != 1:
        raise newCborCddlError("unsupported map of len: " & $entries.len)
      if entries[0].val.occur.kind notin repeatedMap:
        raise newCborCddlError("unsupported single key map")
      let keyNode = entries[0].key.unparen
      if keyNode.kind != nkTypeRef:
        raise newCborCddlError("unsupported map key " & $keyNode.kind)
      let key = toSimpleNimTyp(keyNode.val.text)
      let val = toNimTyp(entries[0].body)
      newNimNode(nnkBracketExpr).add(ident("Table"), key, val)
    else:
      raise newCborCddlError("unsupported type " & $n.kind)
  if isOptional:
    newNimNode(nnkBracketExpr).add(ident("Opt"), typ)
  else:
    typ

proc toLitNode(n: CddlNode): NimNode {.raises: [CborCddlError].} =
  template s(): untyped =
    n.val.text

  doAssert n.kind == nkValue
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

proc toKeyNode(n: CddlNode): NimNode {.raises: [CborCddlError].} =
  ## The Nim field name a member key stands for.
  let k = n.key.unparen
  case k.kind
  of nkTypeRef: # a bareword, or a name used as a key
    ident(k.val.text)
  of nkValue:
    let s = k.val.text
    doAssert s.len > 0
    if s[0] == '"':
      doAssert s.len >= 2
      doAssert s[^1] == '"'
      ident(s[1 ..< s.high])
    else:
      ident(s)
  else:
    raise newCborCddlError("unsupported member key " & $k.kind)

proc toEnumFieldName(s: string, i: int): NimNode =
  if s.len >= 2 and s[0].isAlphaAscii and s[1].isAlphaAscii:
    ident(toLowerAscii(s[0 .. 1] & $i))
  else:
    ident("e" & $i)

proc literalsMap(cddl: CddlSchema): TableRef[string, CddlNode] =
  ## map of rule_name -> literal_val
  result = newTable[string, CddlNode]()
  for rule in cddl.children:
    if rule.val.ruleKind in typeRules and rule.body.unparen.kind == nkValue:
      result[rule.val.ruleText] = rule.body.unparen

proc isOptional(n: CddlNode): bool =
  n.val.occur.kind == CddlOccurKind.ocOptional

proc fromCddlImpl*(s: string): NimNode {.raises: [CborCddlError].} =
  template body(): untyped =
    rule.body.unparen

  result = newNimNode(nnkTypeSection)
  let cddl = parseCddl(s, ignoreComments = true)
  let lits = literalsMap(cddl)
  for rule in cddl.children:
    doAssert rule.kind == nkRule
    doAssert rule.val.ruleKind in typeRules
    let value =
      case body.kind
      of nkMap:
        let entries = entriesOf(body)
        if entries.len == 1 and entries[0].val.occur.kind in repeatedMap:
          toNimTyp(body)
        else:
          let fields = newNimNode(nnkRecList)
          for f in entries:
            fields.add newNimNode(nnkIdentDefs).add(
              newNimNode(nnkPostfix).add(ident("*"), toKeyNode(f)),
              toNimTyp(f.body, f.isOptional),
              newEmptyNode(),
            )
          newNimNode(nnkObjectTy).add(newEmptyNode(), newEmptyNode(), fields)
      of nkUnion:
        var fields = default(seq[NimNode])
        for i, parenthesized in body.children.pairs():
          let variant = parenthesized.unparen
          case variant.kind
          of nkTypeRef:
            let v = lits.getOrDefault(variant.val.text, default(CddlNode))
            if v.kind == nkUnset:
              raise newCborCddlError("union variant not found: " & $variant.val.text)
            fields.add newNimNode(nnkEnumFieldDef).add(
              ident(variant.val.text), toLitNode(v)
            )
          of nkValue:
            fields.add newNimNode(nnkEnumFieldDef).add(
              toEnumFieldName(rule.val.ruleText, i), toLitNode(variant)
            )
          else:
            raise newCborCddlError("unsupported type " & $variant.kind)
        newNimNode(nnkEnumTy).add(newEmptyNode()).add(fields)
      of nkTypeRef, nkArray:
        toNimTyp(body)
      of nkValue:
        default(NimNode) # lits map contains this field
      else:
        raise newCborCddlError("unsupported type " & $body.kind)
    case body.kind
    of nkValue:
      discard
    of nkUnion:
      result.add newNimNode(nnkTypeDef).add(
        newNimNode(nnkPragmaExpr).add(
          newNimNode(nnkPostfix).add(ident("*"), ident(rule.val.ruleText)),
          newNimNode(nnkPragma).add(ident("pure")),
        ),
        newEmptyNode(),
        value,
      )
    else:
      result.add newNimNode(nnkTypeDef).add(
        newNimNode(nnkPostfix).add(ident("*"), ident(rule.val.ruleText)),
        newEmptyNode(),
        value,
      )
  when defined(CborLogGeneratedTypes):
    debugEcho repr(result)

{.pop.}

macro fromCddl*(s: static[string]): untyped =
  fromCddlImpl(s)
