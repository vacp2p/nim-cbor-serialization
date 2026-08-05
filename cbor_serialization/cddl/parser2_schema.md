# Parser2 schema

Ideally this would live in a test, `type_generator` would parse it and test it VS the
`CddlNode` in `./parser2.nim`. Because it uses a union, it's not possible.
`type_generator` does not have support for union -> Nim case object, yet.

```text
; CDDL describing the CDDL parser's own AST, ie the CddlNode of
; cbor_serialization/cddl/parser2.nim, as it would be serialized to CBOR.
;
; The generator turns each rule below into the Nim type of the same name, so
; the names here are the ones parser2 declares. An enum is written as one rule
; per value, bound to the ordinal, plus a rule choosing between them.

; ---------------------------------------------------------------- occurrence

ocOne = 0        ; no occurrence marker -> exactly 1
ocOptional = 1   ; "?"
ocOneOrMore = 2  ; "+"
ocZeroOrMore = 3 ; "*"
ocRange = 4      ; n*m (lo / hi); hi may be absent

CddlOccurKind = ocOne / ocOptional / ocOneOrMore / ocZeroOrMore / ocRange

; both bounds are only set for ocRange, and each only when it was written:
; "0*3" and "*3" mean the same, and are not the same
CddlOccur = {
  kind: CddlOccurKind,
  ? lo: uint,
  ? hi: uint,
}

; ---------------------------------------------------------------- member key

skNone = 0    ; positional (no memberkey)
skColon = 1   ; value key:  name: type   "k": type   1: type
skArrow = 2    ; type1 key:  type1 S "=>" type
skArrowCut = 3 ; type1 key:  type1 S "^" S "=>" type

CddlSepKind = skNone / skColon / skArrow / skArrowCut

; ---------------------------------------------------------------------- rule

rkType = 0     ; typename  = type
rkTypeExt = 1  ; typename /= type     (extends a type choice)
rkGroup = 2    ; groupname  = grpent
rkGroupExt = 3 ; groupname //= grpent (extends a group choice)

CddlRuleKind = rkType / rkTypeExt / rkGroup / rkGroupExt

; --------------------------------------------------------------------- range

rngInclusive = 0 ; ".."  upper bound is part of the range
rngExclusive = 1 ; "..." upper bound is excluded from the range

CddlRangeKind = rngInclusive / rngExclusive

; ---------------------------------------------------------------- node kinds

; the children each kind carries are listed after the syntax it stands for
nkUnset = 0          ; nothing; children: -
nkSchema = 1         ; a whole schema; children: rules
nkRule = 2           ; name ?<params> assign body; children: params, body
nkEntry = 3          ; ?occur ?memberkey type; children: ?key, type
nkParam = 4          ; the a and b a rule declares in "id<a, b> = ..."; children: -
nkTypeRef = 5        ; tstr, uint, MyType; children: -
nkValue = 6          ; 0, "ok", h'0a'; children: -
nkMap = 7            ; { ... }; children: members
nkArray = 8          ; [ ... ]; children: members
nkGroup = 9          ; ( ... ); children: members
nkGroupChoice = 10   ; grpchoice // grpchoice; children: alternatives, nkGroup
nkUnion = 11         ; type1 / type2 / ...; children: variants
nkTagged = 12        ; #6.N( ... ); children: type
nkMajor = 13         ; #N  #N.M; children: -
nkAny = 14           ; bare #; children: -
nkGeneric = 15       ; id<...>; children: arguments
nkRange = 16         ; 0..10  0...10; children: lhs, rhs
nkControl = 17       ; bstr .size 16; children: lhs, rhs
nkParen = 18         ; ( type ); children: type
nkUnwrap = 19        ; ~id  ~id<...>; children: type
nkEnum = 20          ; &id  &id<...>  &( ... ); children: type
nkComment = 21       ; a comment, on a line of its own; children: -
nkCommentInline = 22 ; a comment, after what was written before it; children: -
nkEmpty = 23         ; the blank lines between two rules of a schema, however
                     ; many were written in a row; children: -

CddlNodeKind = nkUnset / nkSchema / nkRule / nkEntry / nkParam / nkTypeRef /
               nkValue / nkMap / nkArray / nkGroup / nkGroupChoice / nkUnion /
               nkTagged / nkMajor / nkAny / nkGeneric / nkRange / nkControl /
               nkParen / nkUnwrap / nkEnum / nkComment / nkCommentInline /
               nkEmpty

; ---------------------------------------------------------------------- node

CddlRuleVal = {ruleText: tstr, ruleKind: CddlRuleKind}

CddlEntryVal = {
  occur: CddlOccur,
  sepKind: CddlSepKind,
}

CddlRangeVal = {rangeKind: CddlRangeKind}

; the token the node was written as, for the kinds whose payload is only that:
; nkParam the parameter name, nkTypeRef the type or group name, nkGeneric the
; base name, nkControl the operator name with its '.', nkValue the literal as
; written
CddlTextVal = {text: tstr}

CddlMajorVal = {major: 0..7, ? minor: uint}

CddlNodeVal =
  CddlRuleVal / CddlEntryVal / CddlRangeVal / CddlTextVal / CddlMajorVal

; A node is its kind, its children, and the payload that kind carries
CddlNode = {
  kind: CddlNodeKind,
  children: [* CddlNode],
  ? val: CddlNodeVal,
}
```
