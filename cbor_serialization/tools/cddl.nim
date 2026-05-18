import npeg
import strutils
import std/options

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
    hi*: Option[uint]

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

type ParseState* = object
  schema*: CddlSchema

  ruleName: string
  ruleGenParams: seq[string]
  ruleKind: RuleKind

  wip: Field

  # Push on '{' '[' '(' '<' entry, pop on closing delimiter
  nested: seq[Field]

  # Aux fields
  variants: seq[FieldType]
  tagNum: string
  opLhs: FieldType
  opText: string

let cddlParser* = peg("cddl", userdata: ParseState):
  ALPHA <- {'A' .. 'Z'} | {'a' .. 'z'}
  EALPHA <- ALPHA | '@' | '_' | '$'
  DIGIT <- {'0' .. '9'}
  DIGIT1 <- {'1' .. '9'}
  HEXDIG <- DIGIT | {'A' .. 'F'} | {'a' .. 'f'}
  BINDIG <- '0' | '1'

  CRLF <- ('\x0D' * '\x0A') | '\x0A'
  PCHAR <- {'\x20' .. '\x7E'} | {'\x80' .. '\xFF'}
  COMMENT <- ';' * *PCHAR * CRLF
  NL <- COMMENT | CRLF
  WS <- ' ' | NL
  S <- *WS

  id <- EALPHA * *(*('-' | '.') * (EALPHA | DIGIT))
  uint <- ("0x" * +HEXDIG) | ("0b" * +BINDIG) | (DIGIT1 * *DIGIT) | '0'
  int_v <- ?'-' * uint
  exponent <- ?('+' | '-') * +DIGIT
  fraction <- +DIGIT
  hexfloat <- ?'-' * "0x" * +HEXDIG * ?('.' * +HEXDIG) * 'p' * exponent
  number <- hexfloat | (int_v * ?('.' * fraction) * ?('e' * exponent))
  SESC <- '\\' * ({'\x20' .. '\x7E'} | {'\x80' .. '\xFF'})
  SCHAR <-
    {'\x20' .. '\x21'} | {'\x23' .. '\x5B'} | {'\x5D' .. '\x7E'} | {'\x80' .. '\xFF'} |
    SESC
  text <- '"' * *SCHAR * '"'
  BCHAR <- {'\x20' .. '\x26'} | {'\x28' .. '\x5B'} | {'\x5D' .. '\xFF'} | SESC | CRLF
  bsqual <- "b64" | 'h'
  bytes <- ?bsqual * '\'' * *BCHAR * '\''
  value <- number | text | bytes
  rangeop <- "..." | ".."
  ctlop <- '.' * id

  occurRange <- >?uint * '*' * >?uint do:
    userdata.wip.occur.kind = if ($1).len + ($2).len > 0: ocRange else: ocZeroOrMore
    if ($1).len > 0:
      userdata.wip.occur.lo = parseUInt($1)
    if ($2).len > 0:
      userdata.wip.occur.hi = some(parseUInt($2))

  occurOneOrMore <- '+' do:
    userdata.wip.occur.kind = ocOneOrMore

  occurOptional <- '?' do:
    userdata.wip.occur.kind = ocOptional

  # occur <- ?uint * '*' * ?uint | '+' | '?'
  occur <- occurRange | occurOneOrMore | occurOptional

  genericargPush <- '<' * S do:
    reset(userdata.wip.typ)
    userdata.nested.add userdata.wip

  genericargType1 <- >type1 do:
    userdata.nested[^1].typ.genericArgs.add userdata.wip.typ

  # genericarg <- '<' * S * type1 * S * *(',' * S * type1 * S) * '>'
  genericarg <-
    genericargPush * genericargType1 * S * *(',' * S * genericargType1 * S) * '>' do:
    userdata.wip = userdata.nested.pop()

  genericparmId <- >id do:
    userdata.ruleGenParams.add $1

  # genericparm <- '<' * S * id * S * *(',' * S * id * S) * '>'
  genericparm <- '<' * S * genericparmId * S * *(',' * S * genericparmId * S) * '>'

  # ~id [genericarg]
  type2UnwrapBase <- '~' * S * >id do:
    reset(userdata.wip.typ)
    userdata.wip.typ.genericBase = $1

  type2Unwrap <- type2UnwrapBase * ?genericarg do:
    userdata.wip.typ = FieldType(
      kind: fkGeneric,
      genericBase: userdata.wip.typ.genericBase,
      genericArgs: userdata.wip.typ.genericArgs,
    )

  # &(group)
  type2GroupEnumPush <- '&' * S * '(' * S do:
    reset(userdata.wip.typ)
    userdata.nested.add userdata.wip

  type2GroupEnum <- type2GroupEnumPush * group * S * ')' do:
    userdata.wip = userdata.nested.pop()
    userdata.wip.typ.kind = fkGroup

  # &id [genericarg]
  type2GroupNameBase <- '&' * S * >id do:
    reset(userdata.wip.typ)
    userdata.wip.typ.genericBase = $1

  type2GroupName <- type2GroupNameBase * ?genericarg do:
    userdata.wip.typ = FieldType(
      kind: fkGeneric,
      genericBase: userdata.wip.typ.genericBase,
      genericArgs: userdata.wip.typ.genericArgs,
    )

  # #6 [.uint] (type)
  type2TagWithNum <- '.' * >uint do:
    userdata.tagNum = "6." & $1

  type2TagNoNum <- 0 do:
    userdata.tagNum = "6"

  type2Tag <- '#' * '6' * (type2TagWithNum | type2TagNoNum) * '(' * S * typ * S * ')' do:
    let inner = new FieldType
    inner[] = userdata.wip.typ
    userdata.wip.typ =
      FieldType(kind: fkTagged, tagNumber: userdata.tagNum, inner: inner)

  # #N [.uint]  (major type, N != 6 handled by ordering)
  type2Major <- '#' * >(DIGIT * ?('.' * uint)) do:
    userdata.wip.typ = FieldType(kind: fkSimpleType, name: "#" & $1)

  # bare #
  type2Any <- '#' do:
    userdata.wip.typ = FieldType(kind: fkAny)

  # ( S typ S )
  type2ParenPush <- '(' * S do:
    reset(userdata.wip.typ)
    userdata.nested.add userdata.wip

  type2Paren <- type2ParenPush * typ * S * ')' do:
    let ft = userdata.wip.typ
    userdata.wip = userdata.nested.pop()
    #if userdata.wip.typ.fields.len > 0:
    #  userdata.wip.typ.kind = fkGroup
    #else:
    userdata.wip.typ = ft

  # { S group S }
  type2MapPush <- '{' * S do:
    reset(userdata.wip.typ)
    userdata.nested.add userdata.wip

  type2Map <- type2MapPush * group * S * '}' do:
    userdata.wip = userdata.nested.pop()
    userdata.wip.typ.kind = fkMap

  # [ S group S ]
  type2ArrayPush <- '[' * S do:
    reset(userdata.wip.typ)
    userdata.nested.add userdata.wip

  type2Array <- type2ArrayPush * group * S * ']' do:
    userdata.wip = userdata.nested.pop()
    userdata.wip.typ.kind = fkArray

  typename <- id do:
    reset(userdata.wip.typ)

  type2Value <- >value do:
    userdata.wip.typ = FieldType(kind: fkValue, valueText: $1)

  type2TypeName <- >typename * ?genericarg do:
    userdata.wip.typ =
      if userdata.wip.typ.genericArgs.len > 0:
        FieldType(
          kind: fkGeneric, genericBase: $1, genericArgs: userdata.wip.typ.genericArgs
        )
      else:
        FieldType(kind: fkSimpleType, name: $1)

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

  type1WithOpLhs <- >(rangeop | ctlop) do:
    userdata.opLhs = userdata.wip.typ
    userdata.opText = $1

  type1WithOp <- type2 * S * type1WithOpLhs * S * type2 do:
    userdata.wip.typ = FieldType(
      kind: fkGeneric,
      genericBase: userdata.opText,
      genericArgs: @[userdata.opLhs, userdata.wip.typ],
    )

  # type1 <- type2 * ?(S * (rangeop | ctlop) * S * type2)
  type1 <- type1WithOp | type2

  typType1 <- >type1 do:
    userdata.variants.add userdata.wip.typ

  # typ <- type1 * *(S * '/' * S * type1)
  typ <- typType1 * *(S * '/' * S * typType1) do:
    if userdata.variants.len > 1:
      userdata.wip.typ = FieldType(kind: fkUnion, variants: userdata.variants)
    userdata.variants.setLen 0

  # type1 S ["^" S] "=>"
  memberkeyType <- >type1 * S * >(?('^')) * S * "=>" do:
    userdata.wip.keyKind = kkType
    userdata.wip.keyText = $1
    userdata.wip.isCut = ($2 == "^")
    reset(userdata.wip.typ)

  # bareword ":"
  memberkeyName <- >id * S * ':' do:
    userdata.wip.keyKind = kkName
    userdata.wip.keyText = $1
    reset(userdata.wip.typ)

  # value ":"
  memberkeyValue <- >value * S * ':' do:
    userdata.wip.keyKind = kkValue
    userdata.wip.keyText = $1
    reset(userdata.wip.typ)

  # memberkey = type1 S ["^" S] "=>" / bareword S ":" / value S ":"
  memberkey <- memberkeyType | memberkeyName | memberkeyValue

  optcom <- S * ?(',' * S)

  grpentReset <- 0 do:
    reset(userdata.wip)

  grpentCommit <- 0 do:
    if userdata.nested.len > 0:
      userdata.nested[^1].typ.fields.add userdata.wip

  grpentInlineGroupPush <- '(' * S do:
    reset(userdata.wip.typ)
    userdata.nested.add userdata.wip

  grpentInlineGroup <- grpentInlineGroupPush * group * S * ')' do:
    userdata.wip = userdata.nested.pop()
    userdata.wip.typ.kind = fkGroup

  # grpent = [occur S] [memberkey S] type
  #        / [occur S] "(" S group S ")"
  grpent <-
    grpentReset *
    ((?(occur * S) * ?(memberkey * S) * typ) | (?(occur * S) * grpentInlineGroup)) *
    grpentCommit

  grpchoice <- *(grpent * optcom)

  # group = grpchoice *(S "//" S grpchoice)
  group <- grpchoice * *(S * "//" * S * grpchoice)

  ruleTypename <- >typename do:
    userdata.ruleName = $1

  # assigng = "=" / "//="  -- group assignment
  ruleAssignG <- ("//=" | "=") do:
    userdata.ruleKind = rkGroup

  # assignt = "=" / "/="   -- type assignment (adds "/=")
  ruleAssignT <- ("/=" | "=") do:
    userdata.ruleKind = rkType

  # rule = typename [genericparm] S assignt S type
  #      / groupname [genericparm] S assigng S grpent
  rule <- (
    (ruleTypename * ?genericparm * S * ruleAssignG * S * grpent) |
    (ruleTypename * ?genericparm * S * ruleAssignT * S * typ)
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
    doAssert userdata.nested.len == 0
    userdata.ruleName = ""
    userdata.ruleGenParams.setLen 0
    reset(userdata.wip.typ)

  # cddl = S 1*(rule S)
  cddl <- S * +(rule * S) * !1

proc parseCddl*(source: string): tuple[ok: bool, schema: CddlSchema] =
  var state = ParseState()
  let r = cddlParser.match(source, state)
  (r.ok, state.schema)

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
