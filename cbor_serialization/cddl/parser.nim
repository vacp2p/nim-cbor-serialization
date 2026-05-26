# cbor-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

#{.push raises: [], gcsafe.}

import std/strutils
import npeg, results

export results

type
  OccurKind* = enum
    ocOne ## no occurrence marker -> exactly 1
    ocOptional ## "?"
    ocOneOrMore ## "+"
    ocZeroOrMore ## "*"
    ocRange ## n*m  (lo / hi); hi may be absent

  Occur* = object
    kind*: OccurKind
    lo*: uint
    hi*: Opt[uint]

  FieldKind* = enum
    fkUnset
    fkSimpleType ## named type or prelude name: tstr, uint, MyType ...
    fkValue ## literal value used as type: 0, "ok", ...
    fkMap ## inline { ... }
    fkArray ## inline [ ... ]
    fkGroup ## inline ( ... ) or &( ... )
    fkUnion ## type1 / type2 / ...  or  grpchoice // grpchoice
    fkTagged ## #6.N(type)
    fkAny ## bare #
    fkGeneric ## id<...>  ~id<...>  &id<...>  or rangeop/ctlop expression

  FieldType* = object
    kind*: FieldKind
    # fkSimpleType:
    name*: string
    # fkValue:
    valueText*: string
    # fkMap, fkArray, fkGroup:
    fields*: seq[Field]
    # fkUnion:
    variants*: seq[FieldType]
    # fkTagged:
    tagNumber*: string
    inner*: ref FieldType
    # fkGeneric:
    genericBase*: string
    genericArgs*: seq[FieldType]
    # fkAny:
    # discard

  KeyKind* = enum
    kkNone ## positional (no memberkey)
    kkName ## bareword:       name: type
    kkValue ## value key:      "k" => type   1 => type
    kkType ## type1 key:      type1 S ["^" S] "=>" type

  Field* = object
    occur*: Occur
    keyKind*: KeyKind
    keyText*: string ## raw text of the key (empty for kkNone)
    isCut*: bool ## true when "^" was present
    typ*: FieldType

  RuleKind* = enum
    rkType ## typename  = type
    rkGroup ## groupname = grpent  (//= or =)

  Rule* = object
    name*: string
    genericParams*: seq[string]
    kind*: RuleKind
    typeExpr*: FieldType ## set for rkType
    groupEntries*: seq[Field] ## set for rkGroup

  CddlSchema* = seq[Rule]

  CborCddlError* = object of CatchableError

  ParseState* = object
    schema*: CddlSchema

    ruleName: string
    ruleGenParams: seq[string]
    ruleKind: RuleKind

    wip: Field

    # Push on '{' '[' '(' '<' entry, pop on closing delimiter
    nested: seq[Field]

    # Aux fields
    variants: seq[FieldType]
    opLhs: FieldType
    opText: string

proc newCddlError(s: string, matchLen, matchMax: int): ref CborCddlError =
  let posA = max(0, min(s.high, matchLen))
  let posB = max(-1, min(s.high, matchMax))
  let lineA = s[0 ..< posA].count('\n') + 1
  let lineB = s[0 ..< max(0, posB)].count('\n') + 1
  let line =
    if lineA != lineB:
      $lineA & "-" & $lineB
    else:
      $lineA
  (ref CborCddlError)(
    msg: "CBOR CDDL failed to parse line " & line & ": " & s[posA .. posB]
  )

# https://datatracker.ietf.org/doc/html/rfc8610#appendix-A
# https://datatracker.ietf.org/doc/html/rfc8610#appendix-B
# https://github.com/zevv/npeg#ordering-of-rules-in-a-grammar
proc parseCddl*(source: string): CddlSchema {.raises: [CborCddlError].} =
  let parser = peg("cddl", userdata: ParseState):
    cddl <- S * +(rule * S) * !1

    #rule <- (typename * ?genericparm * S * assignt * S * typ) |
    #        (groupname * ?genericparm * S * assigng * S * grpent)
    rule <- (
      (ruleTypename * ?genericparm * S * ruleAssignt * S * typ) |
      (ruleTypename * ?genericparm * S * ruleAssigng * S * grpent)
    ) do:
      let top =
        if userdata.nested.len > 0:
          userdata.nested.pop()
        else:
          Field()
      userdata.schema.add(
        Rule(
          name: userdata.ruleName,
          genericParams: userdata.ruleGenParams,
          kind: userdata.ruleKind,
          typeExpr: userdata.wip.typ,
          groupEntries: top.typ.fields,
        )
      )
      # XXX group fails the assert
      #doAssert userdata.nested.len == 0
      userdata.ruleName = ""
      userdata.ruleGenParams.setLen 0
      reset(userdata.wip.typ)

    ruleTypename <- >id do:
      userdata.ruleName = $1

    # assigng <- '=' | "//="
    ruleAssigng <- '=' | "//=" do:
      userdata.ruleKind = rkGroup

    # assignt <- '=' | "/="
    ruleAssignt <- '=' | "/=" do:
      userdata.ruleKind = rkType

    group <- grpchoice * *(S * "//" * S * grpchoice)

    grpchoice <- *(grpent * optcom)

    optcom <- S * ?(',' * S)

    # grpent <- (?(occur * S) * ?(memberkey * S) * typ) |
    #           (?(occur * S) * groupname * ?genericarg) |  ; preempted by above
    #           (?(occur * S) * '(' * S * group * S * ')')
    grpent <-
      grpentReset *
      ((?(occur * S) * ?(memberkey * S) * typ) | (?(occur * S) * grpentInlineGroup)) *
      grpentCommit

    grpentReset <- 0 do:
      reset(userdata.wip)

    grpentCommit <- 0 do:
      if userdata.nested.len > 0:
        userdata.nested[^1].typ.fields.add userdata.wip

    grpentInlineGroup <- grpentInlineGroupPush * group * S * ')' do:
      userdata.wip = userdata.nested.pop()
      userdata.wip.typ.kind = fkGroup

    grpentInlineGroupPush <- '(' * S do:
      reset(userdata.wip.typ)
      userdata.nested.add userdata.wip

    # memberkey <- (type1 * S * ?('^' * S) * "=>") |
    #              (bareword * S * ':') |
    #              (value * S * ':')
    memberkey <- memberkeyType | memberkeyName | memberkeyValue

    memberkeyType <- >type1 * S * >?('^' * S) * "=>" do:
      reset(userdata.wip.typ)
      userdata.wip.keyKind = kkType
      userdata.wip.keyText = $1
      userdata.wip.isCut = ($2).len > 0

    memberkeyName <- >bareword * S * ':' do:
      reset(userdata.wip.typ)
      userdata.wip.keyKind = kkName
      userdata.wip.keyText = $1

    memberkeyValue <- >value * S * ':' do:
      reset(userdata.wip.typ)
      userdata.wip.keyKind = kkValue
      userdata.wip.keyText = $1

    # typ <- type1 * *(S * '/' * S * type1)
    typ <- typType1 * *(S * '/' * S * typType1) do:
      if userdata.variants.len > 1:
        userdata.wip.typ = FieldType(kind: fkUnion, variants: userdata.variants)
      userdata.variants.setLen 0

    typType1 <- >type1 do:
      userdata.variants.add userdata.wip.typ

    # type1 <- type2 * ?(S * (rangeop | ctlop) * S * type2)
    type1 <- type1WithOp | type2

    type1WithOp <- type2 * S * type1WithOpLhs * S * type2 do:
      userdata.wip.typ = FieldType(
        kind: fkGeneric,
        genericBase: userdata.opText,
        genericArgs: @[userdata.opLhs, userdata.wip.typ],
      )

    type1WithOpLhs <- >(rangeop | ctlop) do:
      userdata.opLhs = userdata.wip.typ
      userdata.opText = $1

    # type2 <- value |
    #        (typename * ?genericarg) |
    #        ('(' * S * typ * S * ')') |
    #        ('{' * S * group * S * '}') |
    #        ('[' * S * group * S * ']') |
    #        ('~' * S * typename * ?genericarg) |
    #        ('&' * S * '(' * S * group * S * ')') |
    #        ('&' * S * groupname * ?genericarg) |
    #        ('#' * '6' * ?('.' * uintx) * '(' * S * typ * S * ')') |
    #        ('#' * DIGIT * ?('.' * uintx)) |
    #        '#'
    type2 <-
      type2Value | type2TypeName | type2Paren | type2Map | type2Array | type2Unwrap |
      type2GroupEnum | type2GroupName | type2Tag | type2Major | type2Any

    type2Value <- >value do:
      userdata.wip.typ = FieldType(kind: fkValue, valueText: $1)

    # (typename * ?genericarg)
    type2TypeName <- >type2TypeNameBase * ?genericarg do:
      userdata.wip.typ =
        if userdata.wip.typ.genericArgs.len > 0:
          FieldType(
            kind: fkGeneric, genericBase: $1, genericArgs: userdata.wip.typ.genericArgs
          )
        else:
          FieldType(kind: fkSimpleType, name: $1)

    type2TypeNameBase <- typename do:
      reset(userdata.wip.typ)

    # ('(' * S * typ * S * ')')
    type2Paren <- type2ParenPush * typ * S * ')' do:
      let ft = userdata.wip.typ
      userdata.wip = userdata.nested.pop()
      #if userdata.wip.typ.fields.len > 0:
      #  userdata.wip.typ.kind = fkGroup
      #else:
      userdata.wip.typ = ft

    type2ParenPush <- '(' * S do:
      reset(userdata.wip.typ)
      userdata.nested.add userdata.wip

    # ('{' * S * group * S * '}')
    type2Map <- type2MapPush * group * S * '}' do:
      userdata.wip = userdata.nested.pop()
      userdata.wip.typ.kind = fkMap

    type2MapPush <- '{' * S do:
      reset(userdata.wip.typ)
      userdata.nested.add userdata.wip

    # ('[' * S * group * S * ']')
    type2Array <- type2ArrayPush * group * S * ']' do:
      userdata.wip = userdata.nested.pop()
      userdata.wip.typ.kind = fkArray

    type2ArrayPush <- '[' * S do:
      reset(userdata.wip.typ)
      userdata.nested.add userdata.wip

    # ('~' * S * typename * ?genericarg)
    type2Unwrap <- type2UnwrapBase * ?genericarg do:
      userdata.wip.typ = FieldType(
        kind: fkGeneric,
        genericBase: userdata.wip.typ.genericBase,
        genericArgs: userdata.wip.typ.genericArgs,
      )

    type2UnwrapBase <- '~' * S * >typename do:
      reset(userdata.wip.typ)
      userdata.wip.typ.genericBase = $1

    # ('&' * S * '(' * S * group * S * ')')
    type2GroupEnum <- type2GroupEnumPush * group * S * ')' do:
      userdata.wip = userdata.nested.pop()
      userdata.wip.typ.kind = fkGroup

    type2GroupEnumPush <- '&' * S * '(' * S do:
      reset(userdata.wip.typ)
      userdata.nested.add userdata.wip

    # ('&' * S * groupname * ?genericarg)
    type2GroupName <- type2GroupNameBase * ?genericarg do:
      userdata.wip.typ = FieldType(
        kind: fkGeneric,
        genericBase: userdata.wip.typ.genericBase,
        genericArgs: userdata.wip.typ.genericArgs,
      )

    type2GroupNameBase <- '&' * S * >groupname do:
      reset(userdata.wip.typ)
      userdata.wip.typ.genericBase = $1

    # ('#' * '6' * ?('.' * uint) * '(' * S * typ * S * ')')
    type2Tag <- '#' * >('6' * ?('.' * uint)) * '(' * S * typ * S * ')' do:
      let inner = new FieldType
      inner[] = userdata.wip.typ
      userdata.wip.typ = FieldType(kind: fkTagged, tagNumber: $1, inner: inner)

    # ('#' * DIGIT * ?('.' * uintx))
    type2Major <- '#' * >(DIGIT * ?('.' * uint)) do:
      userdata.wip.typ = FieldType(kind: fkSimpleType, name: $1)

    # (#)
    type2Any <- '#' do:
      userdata.wip.typ = FieldType(kind: fkAny)

    # genericarg <- '<' * S * type1 * S * *(',' * S * type1 * S) * '>'
    genericarg <-
      genericargPush * genericargType1 * S * *(',' * S * genericargType1 * S) * '>' do:
      userdata.wip = userdata.nested.pop()

    genericargPush <- '<' * S do:
      reset(userdata.wip.typ)
      userdata.nested.add userdata.wip

    genericargType1 <- >type1 do:
      userdata.nested[^1].typ.genericArgs.add userdata.wip.typ

    # genericparm <- '<' * S * id * S * *(',' * S * id * S) * '>'
    genericparm <- '<' * S * genericparmId * S * *(',' * S * genericparmId * S) * '>'

    genericparmId <- >id do:
      userdata.ruleGenParams.add $1

    # occur <- ?uint * '*' * ?uint | '+' | '?'
    occur <- occurRange | occurOneOrMore | occurOptional

    occurRange <- >?uint * '*' * >?uint do:
      userdata.wip.occur.kind = if ($1).len + ($2).len > 0: ocRange else: ocZeroOrMore
      if ($1).len > 0:
        userdata.wip.occur.lo = parseUInt($1)
      if ($2).len > 0:
        userdata.wip.occur.hi = Opt.some(parseUInt($2))

    occurOneOrMore <- '+' do:
      userdata.wip.occur.kind = ocOneOrMore

    occurOptional <- '?' do:
      userdata.wip.occur.kind = ocOptional

    bareword <- id
    typename <- id
    groupname <- id

    value <- number | text | bytes
    text <- '"' * *SCHAR * '"'
    bytes <- ?bsqual * '\'' * *BCHAR * '\''
    bsqual <- 'h' | "b64"
    rangeop <- "..." | ".."
    ctlop <- '.' * id
    id <- EALPHA * *(*('-' | '.') * (EALPHA | DIGIT))
    number <- hexfloat | (int * ?('.' * fraction) * ?('e' * exponent))
    hexfloat <- ?'-' * "0x" * +HEXDIG * ?('.' * +HEXDIG) * 'p' * exponent
    int <- ?'-' * uint
    uint <- (DIGIT1 * *DIGIT) | ("0x" * +HEXDIG) | ("0b" * +BINDIG) | "0"
    fraction <- +DIGIT
    exponent <- ?('+' | '-') * +DIGIT
    SCHAR <-
      {'\x20' .. '\x21', '\x23' .. '\x5B', '\x5D' .. '\x7E', '\x80' .. '\xFF'} | SESC
    BCHAR <-
      {'\x20' .. '\x26', '\x28' .. '\x5B', '\x5D' .. '\x7E', '\x80' .. '\xFF'} | SESC |
      CRLF
    SESC <- '\\' * {'\x20' .. '\x7E', '\x80' .. '\xFF'}

    S <- *WS
    WS <- SP | NL
    SP <- ' '
    NL <- COMMENT | CRLF
    COMMENT <- ';' * *PCHAR * CRLF
    PCHAR <- {'\x20' .. '\x7E', '\x80' .. '\xFF'}
    CRLF <- ('\x0D' * '\x0A') | '\x0A'

    BINDIG <- '0' | '1'
    HEXDIG <- DIGIT | {'A' .. 'F'} | {'a' .. 'f'}
    DIGIT1 <- {'1' .. '9'}
    DIGIT <- {'0' .. '9'}
    EALPHA <- ALPHA | '@' | '_' | '$'
    ALPHA <- {'A' .. 'Z'} | {'a' .. 'z'}

  var state = ParseState()
  let r =
    try:
      parser.match(source, state)
    except NPegException as exc:
      raise newCddlError(source, exc.matchLen, exc.matchMax)
    # match throws Exception error...
    except CatchableError as exc:
      raise (ref CborCddlError)(msg: "CBOR CDDL parser error: " & exc.msg, parent: exc)
    except Defect as exc:
      raise exc
    except Exception:
      raiseAssert "Unexpected Exception"
  if r.ok:
    doAssert r.matchLen == source.len
    state.schema
  else:
    raise newCddlError(source, r.matchLen, r.matchMax)

proc showTypeInline*(ft: FieldType): string =
  ## Compact single-line rendering used for Generic<...> arg lists.
  case ft.kind
  of fkUnset:
    "<nil>"
  of fkSimpleType:
    ft.name
  of fkValue:
    ft.valueText
  of fkAny:
    "#"
  of fkGeneric:
    var gargs: seq[string]
    for v in ft.genericArgs:
      gargs.add showTypeInline(v)
    ft.genericBase & "<" & gargs.join(",") & ">"
  else:
    "<?>"

proc showType*(ft: FieldType, indent = 0): string =
  let pad = "  ".repeat(indent)
  case ft.kind
  of fkUnset:
    pad & "<nil>"
  of fkSimpleType:
    pad & "SimpleType(" & ft.name & ")"
  of fkValue:
    pad & "Value(" & ft.valueText & ")"
  of fkAny:
    pad & "Any"
  of fkUnion:
    var s = pad & "Union[\n"
    for v in ft.variants:
      s &= showType(v, indent + 1) & "\n"
    s & pad & "]"
  of fkTagged:
    pad & "Tagged(" & ft.tagNumber & ")\n" & showType(ft.inner[], indent + 1)
  of fkGeneric:
    var gargs: seq[string]
    for v in ft.genericArgs:
      gargs.add showTypeInline(v)
    pad & "Generic(" & ft.genericBase & "<" & gargs.join(",") & ">)"
  of fkMap:
    var s = pad & "Map{\n"
    for f in ft.fields:
      s &= pad & "  [" & $f.occur.kind & "]"
      if f.keyText != "":
        s &= " key=" & f.keyText & "(" & $f.keyKind & ")"
      s &= "\n"
      if f.typ.kind != fkUnset:
        s &= showType(f.typ, indent + 2) & "\n"
    s & pad & "}"
  of fkArray:
    var s = pad & "Array[\n"
    for f in ft.fields:
      s &= pad & "  [" & $f.occur.kind & "]"
      if f.keyText != "":
        s &= " key=" & f.keyText
      s &= "\n"
      if f.typ.kind != fkUnset:
        s &= showType(f.typ, indent + 2) & "\n"
    s & pad & "]"
  of fkGroup:
    var s = pad & "Group(\n"
    for f in ft.fields:
      s &= pad & "  [" & $f.occur.kind & "]"
      if f.keyText != "":
        s &= " key=" & f.keyText
      s &= "\n"
      if f.typ.kind != fkUnset:
        s &= showType(f.typ, indent + 2) & "\n"
    s & pad & ")"
