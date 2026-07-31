# cbor-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/strutils
import npeg, results
import faststreams/[outputs, textio]

export results

type
  CddlOccurKind* {.pure.} = enum
    ocOne ## no occurrence marker -> exactly 1
    ocOptional ## "?"
    ocOneOrMore ## "+"
    ocZeroOrMore ## "*"
    ocRange ## n*m  (lo / hi); hi may be absent

  CddlOccur* = object
    kind*: CddlOccurKind
    lo*: Opt[uint64]
    hi*: Opt[uint64]

  CddlSepKind* {.pure.} = enum
    ## What separates a member's key from its type
    skNone ## positional (no memberkey)
    skColon ## name: type   "k": type   1: type
    skArrow ## type1 S "=>" type
    skArrowCut ## type1 S "^" S "=>" type

  CddlRuleKind* {.pure.} = enum
    rkType ## typename  = type
    rkTypeExt ## typename  /= type    (extends a type choice)
    rkGroup ## groupname = grpent
    rkGroupExt ## groupname //= grpent  (extends a group choice)

  CddlRangeKind* {.pure.} = enum
    rngInclusive ## ".."   upper bound is part of the range
    rngExclusive ## "..."  upper bound is excluded from the range

  CddlNodeKind* {.pure.} = enum
    ## The children each kind carries are listed after the syntax it stands for
    nkUnset ## nothing; children: -
    nkSchema ## a whole schema; children: rules
    nkRule ## name ?<params> assign body; children: params, body
    nkEntry ## ?occur ?memberkey type; children: ?key, type
    nkParam ## the a and b a rule declares in "id<a, b> = ..."; children: -
    nkTypeRef ## tstr, uint, MyType; children: -
    nkValue ## 0, "ok", h'0a'; children: -
    nkMap ## { ... }; children: members
    nkArray ## [ ... ]; children: members
    nkGroup ## ( ... ); children: members
    nkGroupChoice ## grpchoice // grpchoice; children: alternatives, nkGroup
    nkUnion ## type1 / type2 / ...; children: variants
    nkTagged ## #6.N( ... ); children: type
    nkMajor ## #N  #N.M; children: -
    nkAny ## bare #; children: -
    nkGeneric ## id<...>; children: arguments
    nkRange ## 0..10  0...10; children: lhs, rhs
    nkControl ## bstr .size 16; children: lhs, rhs
    nkParen ## ( type ); children: type
    nkUnwrap ## ~id  ~id<...>; children: type
    nkEnum ## &id  &id<...>  &( ... ); children: type
    nkComment ## ; a comment, on a line of its own; children: -
    nkCommentInline ## ; a comment, after what was written before it; children: -
    nkEmpty ## used for top-level blank lines children: -

  CddlNodeVal* = object
    ## CddlNode value

    # nkRule:
    ruleText*: string
    ruleKind*: CddlRuleKind
    # nkEntry:
    occur*: CddlOccur
    sepKind*: CddlSepKind
    # nkRange:
    rangeKind*: CddlRangeKind
    # nkTagged:
    major*: uint8
    minor*: Opt[uint64]
    # else:
    text*: string

  CddlNode* = object
    # The members of a map, array or group are nkEntry's, except when the
    # group is a choice, in which case there is a single nkGroupChoice child
    kind*: CddlNodeKind
    children*: seq[CddlNode]
    val*: CddlNodeVal

  CddlSchema* = CddlNode
    ## An nkSchema node, whose children are the nkRule's of a schema in source
    ## order, and the comments and blank lines written among them. A container
    ## like any other, so that everything reading or writing one works the same
    ## way here.

  CborCddlError* = object of CatchableError

  Nl = object ## Blank line or comment
    si: int ## where it starts in the source
    kind: CddlNodeKind ## one of nlKinds
    text: string ## from its ';' up to, but not including, its newline

  ParseState = object
    schema: seq[CddlNode] ## the children the nkSchema is built from at the end

    # A copy of what is being parsed, to tell a comment at the end of a line
    # from one written on a line of its own, and a blank line from a line that
    # has something on it
    source: string

    # Read comments and blank lines as the whitespace they stand in for,
    # keeping none
    ignoreComments: bool

    # NLs read but not handed to a node yet, in source order
    pending: seq[Nl]

    ruleName: string
    ruleParams: seq[CddlNode]
    ruleKind: CddlRuleKind

    # The entry being built
    wip: CddlNode

    # Open containers, pushed on '{' '[' '(' '<' and popped on the closing
    # delimiter; each holds the entry that owns the container
    nested: seq[CddlNode]

    # The variants of every type choice being parsed, innermost last, so that
    # a nested choice, ie the "(2 / 3)" in "1 / (2 / 3)", keeps its own
    variantStack: seq[seq[CddlNode]]

    # Operands of a pending rangeop/ctlop expression; a type1 pushes its
    # operand and pops the (possibly combined) result, so nested type1's,
    # ie the "1..32" in "tstr .size (1..32)", don't clobber the outer one
    operandStack: seq[CddlNode]

    # Why an action could not make sense of what it matched, read once the
    # match is over; see parseNum for why this is not raised on the spot
    error: string

# Needed to avoid expensive AST copies;
# if it's too hard to work with in practice
# make CddlNode a ref and drop const support
when (NimMajor, NimMinor) >= (2, 2) and defined(gcOrc):
  proc `=copy`(dst: var CddlNode, src: CddlNode) {.error.}

const
  typeRules* = {rkType, rkTypeExt} ## rules binding a type
  groupRules* = {rkGroup, rkGroupExt} ## rules binding a group entry
  commentKinds* = {nkComment, nkCommentInline}
    ## nodes carrying a comment rather than anything a schema is made of
  nlKinds* = commentKinds + {nkEmpty} ## blank line and comments
  typeKinds* = {
    nkTypeRef, nkValue, nkMap, nkArray, nkGroup, nkUnion, nkTagged, nkMajor, nkAny,
    nkGeneric, nkRange, nkControl, nkParen, nkUnwrap, nkEnum,
  } ## the kinds that can stand where a type is called for

# XXX https://github.com/nim-lang/Nim/issues/26081
func `==`*(a, b: CddlNode): bool =
  a.kind == b.kind and a.val == b.val and a.children == b.children

func body*(n: CddlNode): lent CddlNode =
  ## Type a rule binds, or an entry is an occurrence of; the last child either
  ## way, since a rule may have parameters and an entry a key in front of it.
  doAssert n.kind in {nkRule, nkEntry}
  n.children[n.children.high] # "^1" would not be addressable, so not lent

template genericParams*(n: CddlNode): untyped =
  ## The nkParam's an nkRule declares, empty when it is not generic. A view of
  ## the children before the body, so that reading them copies nothing; a
  ## template, since a func cannot hand an openArray back out of the node.
  n.children.toOpenArray(0, n.children.high - 1)

func key*(n: CddlNode): lent CddlNode =
  ## Member key of an entry. Under skColon an nkValue is the literal it was
  ## written as, and an nkTypeRef the bareword RFC 8610 defines as the text
  ## string of that name; under the arrows, the type the key was written as.
  doAssert n.kind == nkEntry and n.val.sepKind != skNone
  n.children[0]

func hasCut*(n: CddlNode): bool =
  ## Whether a match on the key of this entry commits to it, so that a later
  ## entry cannot match the same key. RFC 8610 3.5.4 makes "k: t" a shorthand
  ## for "k ^ => t", so the colon form cuts as well.
  doAssert n.kind == nkEntry
  n.val.sepKind in {skColon, skArrowCut}

iterator entries*(n: CddlNode): lent CddlNode =
  ## Members of a map, array or group, without the comments and blank
  ## lines written among them. Everything walking a container wants this rather than children.
  for i in 0 ..< n.children.len:
    if n.children[i].kind notin nlKinds:
      yield n.children[i]

func entryCount*(n: CddlNode): int =
  ## How many members a map, array or group has, an NL not counted.
  for i in 0 ..< n.children.len:
    if n.children[i].kind notin nlKinds:
      inc result

func firstEntry*(n: CddlNode): lent CddlNode =
  ## The first member of a map, array or group that is not an NL.
  for i in 0 ..< n.children.len:
    if n.children[i].kind notin nlKinds:
      return n.children[i]
  raiseAssert "container has no entries"

func target*(n: CddlNode): lent CddlNode =
  ## Type a tag, a paren or the "~" / "&" operators are applied to; for
  ## "&( ... )" this is the nkGroup itself, otherwise the referenced name as
  ## nkTypeRef/nkGeneric.
  doAssert n.kind in {nkTagged, nkParen, nkUnwrap, nkEnum}
  n.children[0]

func unparen*(n: CddlNode): lent CddlNode =
  ## The type inside any parens it was written in. The grammar allows them
  ## around any type, where they carry no meaning of their own.
  result = n
  while result.kind == nkParen:
    result = result.children[0]

func lhs*(n: CddlNode): lent CddlNode =
  ## Lower bound of a range, or the type a control operator applies to.
  doAssert n.kind in {nkRange, nkControl}
  n.children[0]

func rhs*(n: CddlNode): lent CddlNode =
  ## Upper bound of a range, included only when rangeKind is rngInclusive, or
  ## the controller type of a control operator.
  doAssert n.kind in {nkRange, nkControl}
  n.children[1]

func assignText*(rk: CddlRuleKind): string =
  ## The "=", "/=" or "//=" a rule of this kind is written with, spaced.
  case rk
  of rkType: " = "
  of rkTypeExt: " /= "
  of rkGroup: " = "
  of rkGroupExt: " //= "

func rangeOpText*(rk: CddlRangeKind): string =
  case rk
  of rngInclusive: ".."
  of rngExclusive: "..."

func parseNum(s: string, err: var string, what: string): Opt[uint64] =
  var v = 0'u64
  for c in s:
    if c notin {'0' .. '9'}: # the grammar also admits "0x" and "0b" numbers
      err = what & " is not a decimal number: " & s
      return Opt.none(uint64)
    let digit = uint64(ord(c) - ord('0'))
    if v > (uint64.high - digit) div 10:
      err = what & " out of range: " & s
      return Opt.none(uint64)
    v = v * 10 + digit
  Opt.some(v)

func majorVal(s: string, err: var string): CddlNodeVal =
  ## The "6.32" or "3" a '#' was followed by, as the major type and the number
  ## after its '.'. The leading digit is one by the grammar.
  result = CddlNodeVal(major: uint8(ord(s[0]) - ord('0')))
  let dot = s.find('.')
  if dot >= 0:
    result.minor = parseNum(s[dot + 1 .. ^1], err, "tag number")

func initEntry(): CddlNode =
  ## An entry with an empty type slot, ready to be filled in by the parser.
  CddlNode(kind: nkEntry, children: @[CddlNode()])

template typeSlot(n: untyped): untyped =
  ## Where an entry's type is read into: its last child, so that a member key
  ## can be put in front of it once one is read. Indexed from the front: "^1"
  ## goes through a proc that hands back a copy of the whole subtree.
  n.children[n.children.high]

template `typeSlot=`(n, typ: untyped) =
  # a setter of its own: "n.typeSlot = x" is resolved as one before templates
  n.children[n.children.high] = typ

template members(state: untyped): untyped =
  ## The members read so far into the container that is currently open.
  state.nested[state.nested.high].typeSlot.children

template `members=`(state, nodes: untyped) =
  state.nested[state.nested.high].typeSlot.children = nodes

# XXX fails for refc
#proc namedType(state: var ParseState, name: string): CddlNode =
#  if state.wip.typeSlot.children.len > 0:
#    CddlNode(kind: nkGeneric, val: CddlNodeVal(text: name), children: move(state.wip.typeSlot.children))
#  else:
#    CddlNode(kind: nkTypeRef, val: CddlNodeVal(text: name))

func namedType(name: string, args: sink seq[CddlNode]): CddlNode =
  if args.len > 0:
    CddlNode(kind: nkGeneric, val: CddlNodeVal(text: name), children: args)
  else:
    CddlNode(kind: nkTypeRef, val: CddlNodeVal(text: name))

func isOwnLine(source: string, si: int): bool =
  ## Whether the comment starting here is the first thing written on its line.
  var i = si - 1
  while i >= 0 and source[i] in {' ', '\t', '\r'}:
    dec i
  i < 0 or source[i] == '\n'

proc dropPendingFrom(state: var ParseState, si: int) =
  ## Forget the NLs read from here on. A branch the parser abandons leaves
  ## behind whatever it read, so it goes before anything is read a second time:
  ## the branch that replaces it reads its own NLs again, at the same
  ## offsets.
  while state.pending.len > 0 and state.pending[^1].si >= si:
    discard state.pending.pop()

proc addComment(state: var ParseState, text: string, si: int) =
  ## Hold on to a comment until a rule or an entry takes it.
  if state.ignoreComments:
    return
  state.dropPendingFrom(si)
  state.pending.add Nl(
    si: si,
    kind: if isOwnLine(state.source, si): nkComment else: nkCommentInline,
    text: text,
  )

proc addBlank(state: var ParseState, si: int) =
  ## Add blank line; fold multiple blank lines into one
  if state.ignoreComments or state.nested.len > 0 or not isOwnLine(state.source, si):
    return
  state.dropPendingFrom(si)
  if state.pending.len > 0 and state.pending[^1].kind == nkEmpty:
    return
  state.pending.add Nl(si: si, kind: nkEmpty)

proc flushNl(state: var ParseState, dest: var seq[CddlNode], blanks = false) =
  ## Write the NLs read so far into dest.
  for i in 0 ..< state.pending.len:
    if blanks or state.pending[i].kind != nkEmpty:
      dest.add CddlNode(
        kind: state.pending[i].kind, val: CddlNodeVal(text: state.pending[i].text)
      )
  state.pending.setLen 0

proc openContainer(state: var ParseState) =
  ## Start reading the members of a container into the type slot of the entry
  ## that owns it - the entry has to be kept because parsing those members
  ## overwrites it - and begin a fresh entry for the first member.
  reset(state.wip.typeSlot)
  state.nested.add move(state.wip) # finished with; hand it over, don't copy
  state.wip = initEntry()
  state.flushNl(state.members)

proc closeContainer(state: var ParseState, kind: CddlNodeKind) =
  ## Give the container its kind and the entry that owns it back.
  # anything read after the last member was written inside here, and there is
  # no way back to these members once the container is popped
  state.flushNl(state.members)
  state.wip = state.nested.pop()
  state.wip.typeSlot.kind = kind

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

{.pop.} # {.push raises: [], gcsafe.}

# https://datatracker.ietf.org/doc/html/rfc8610#appendix-A
# https://datatracker.ietf.org/doc/html/rfc8610#appendix-B
# https://github.com/zevv/npeg#ordering-of-rules-in-a-grammar
proc parseCddl*(
    source: string, ignoreComments = false
): CddlSchema {.raises: [CborCddlError], gcsafe.} =
  ## Parse a CDDL schema into its rules. With ignoreComments a comment, and the
  ## blank lines a schema is laid out with, are read as the whitespace they
  ## stand in for and nothing is kept of them, so that what comes back is rules
  ## and their members and nothing else; leave it off to keep the nkComment,
  ## nkCommentInline and nkEmpty nodes written among them.
  let parser = peg("cddl", userdata: ParseState):
    cddl <- S * +(rule * S) * !1

    #rule <- (typename * ?genericparm * S * assignt * S * typ) |
    #        (groupname * ?genericparm * S * assigng * S * grpent)
    rule <- (
      (ruleTypename * ?genericparm * S * ruleAssignt * S * typ) |
      (ruleTypename * ?genericparm * S * ruleAssigng * S * grpent)
    ) do:
      # the body goes after the parameters read so far, as the last child
      userdata.ruleParams.add(
        if userdata.ruleKind in groupRules:
          move(userdata.wip)
        else:
          move(userdata.wip.typeSlot)
      )
      userdata.schema.add CddlNode(
        kind: nkRule,
        val: CddlNodeVal(ruleText: userdata.ruleName, ruleKind: userdata.ruleKind),
        children: move(userdata.ruleParams),
      )
      userdata.wip = initEntry()

    ruleTypename <- >id do:
      userdata.ruleName = $1
      userdata.ruleParams.setLen 0
      userdata.flushNl(userdata.schema, blanks = true)

    # assigng <- '=' | "//="
    ruleAssigng <- >('=' | "//=") do:
      userdata.ruleKind = if $1 == "//=": rkGroupExt else: rkGroup

    # assignt <- '=' | "/="
    ruleAssignt <- >('=' | "/=") do:
      userdata.ruleKind = if $1 == "/=": rkTypeExt else: rkType

    # group <- grpchoice * *(S * "//" * S * grpchoice)
    group <- grpchoice * *(S * "//" * S * grpchoice) do:
      var alts = move(userdata.members)
      userdata.members =
        if alts.len == 1:
          move(alts[0].children)
        else:
          @[CddlNode(kind: nkGroupChoice, children: move(alts))]

    grpchoice <- *(grpent * optcom) do:
      # the members read since the last "//" - the ones not made an
      # alternative yet - are the alternative this choice stands for
      var first = userdata.members.len
      while first > 0 and userdata.members[first - 1].kind != nkGroup:
        dec first
      var alt = CddlNode(kind: nkGroup)
      for i in first ..< userdata.members.len:
        alt.children.add move(userdata.members[i])
      userdata.members.setLen first
      userdata.members.add move(alt)

    optcom <- S * ?(',' * S) do:
      if userdata.nested.len > 0:
        userdata.flushNl(userdata.members)

    # grpent <- (?(occur * S) * ?(memberkey * S) * typ) |
    #           (?(occur * S) * groupname * ?genericarg) |  ; preempted by above
    #           (?(occur * S) * '(' * S * group * S * ')')
    grpent <-
      ((?(occur * S) * ?(memberkey * S) * typ) | (?(occur * S) * grpentInlineGroup)) do:
      if userdata.nested.len > 0:
        userdata.members.add move(userdata.wip)
        userdata.wip = initEntry()

    grpentInlineGroup <- grpentInlineGroupPush * group * S * ')' do:
      userdata.closeContainer(nkGroup)

    grpentInlineGroupPush <- '(' * S do:
      userdata.openContainer()

    # memberkey <- (type1 * S * ?('^' * S) * "=>") |
    #              (bareword * S * ':') |
    #              (value * S * ':')
    memberkey <- memberkeyType | memberkeyName | memberkeyValue

    memberkeyType <- >type1 * S * >?('^' * S) * "=>" do:
      userdata.wip.val.sepKind = if ($2).len > 0: skArrowCut else: skArrow
      let readKey = move(userdata.wip.typeSlot)
      userdata.wip.children = @[readKey, CddlNode()]

    memberkeyName <- >bareword * S * ':' do:
      userdata.wip.val.sepKind = skColon
      userdata.wip.children =
        @[CddlNode(kind: nkTypeRef, val: CddlNodeVal(text: $1)), CddlNode()]

    memberkeyValue <- >value * S * ':' do:
      userdata.wip.val.sepKind = skColon
      userdata.wip.children =
        @[CddlNode(kind: nkValue, val: CddlNodeVal(text: $1)), CddlNode()]

    # typ <- type1 * *(S * '/' * S * type1)
    typ <- typFirstVariant * *(S * '/' * S * typVariant) do:
      var variants = userdata.variantStack.pop()
      userdata.wip.typeSlot =
        if variants.len > 1:
          CddlNode(kind: nkUnion, children: move(variants))
        else:
          move(variants[0])

    typFirstVariant <- type1 do:
      userdata.variantStack.add @[move(userdata.wip.typeSlot)]

    typVariant <- type1 do:
      userdata.variantStack[userdata.variantStack.high].add move(userdata.wip.typeSlot)

    # type1 <- type2 * ?(S * (rangeop | ctlop) * S * type2)
    type1 <- type1Operand * ?type1WithOp do:
      userdata.wip.typeSlot = userdata.operandStack.pop()

    type1WithOp <- S * >(rangeop | ctlop) * S * type1Operand do:
      let rhs = userdata.operandStack.pop()
      let lhs = userdata.operandStack.pop()
      let op = $1
      userdata.operandStack.add(
        if op == ".." or op == "...":
          CddlNode(
            kind: nkRange,
            val:
              CddlNodeVal(rangeKind: (if op == "...": rngExclusive else: rngInclusive)),
            children: @[lhs, rhs],
          )
        else:
          CddlNode(kind: nkControl, val: CddlNodeVal(text: op), children: @[lhs, rhs])
      )

    type1Operand <- type2 do:
      userdata.operandStack.add move(userdata.wip.typeSlot)

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
      userdata.wip.typeSlot = CddlNode(kind: nkValue, val: CddlNodeVal(text: $1))

    # (typename * ?genericarg)
    type2TypeName <- >refName * ?genericarg do:
      userdata.wip.typeSlot = namedType($1, move(userdata.wip.typeSlot.children))

    # ('(' * S * typ * S * ')')
    type2Paren <- '(' * S * typ * S * ')' do:
      let inner = move(userdata.wip.typeSlot)
      userdata.wip.typeSlot = CddlNode(kind: nkParen, children: @[inner])

    # ('{' * S * group * S * '}')
    type2Map <- type2MapPush * group * S * '}' do:
      userdata.closeContainer(nkMap)

    type2MapPush <- '{' * S do:
      userdata.openContainer()

    # ('[' * S * group * S * ']')
    type2Array <- type2ArrayPush * group * S * ']' do:
      userdata.closeContainer(nkArray)

    type2ArrayPush <- '[' * S do:
      userdata.openContainer()

    # ('~' * S * typename * ?genericarg)
    type2Unwrap <- '~' * S * >refName * ?genericarg do:
      let named = namedType($1, move(userdata.wip.typeSlot.children))
      userdata.wip.typeSlot = CddlNode(kind: nkUnwrap, children: @[named])

    # ('&' * S * '(' * S * group * S * ')')
    type2GroupEnum <- type2GroupEnumPush * group * S * ')' do:
      userdata.closeContainer(nkGroup)
      let grp = move(userdata.wip.typeSlot)
      userdata.wip.typeSlot = CddlNode(kind: nkEnum, children: @[grp])

    type2GroupEnumPush <- '&' * S * '(' * S do:
      userdata.openContainer()

    # ('&' * S * groupname * ?genericarg)
    type2GroupName <- '&' * S * >refName * ?genericarg do:
      let named = namedType($1, move(userdata.wip.typeSlot.children))
      userdata.wip.typeSlot = CddlNode(kind: nkEnum, children: @[named])

    # ('#' * '6' * ?('.' * uint) * '(' * S * typ * S * ')')
    type2Tag <- '#' * >('6' * ?('.' * uint)) * '(' * S * typ * S * ')' do:
      let inner = move(userdata.wip.typeSlot)
      userdata.wip.typeSlot =
        CddlNode(kind: nkTagged, val: majorVal($1, userdata.error), children: @[inner])

    # ('#' * DIGIT * ?('.' * uintx))
    type2Major <- '#' * >(DIGIT * ?('.' * uint)) do:
      userdata.wip.typeSlot = CddlNode(kind: nkMajor, val: majorVal($1, userdata.error))

    # (#)
    type2Any <- '#' do:
      userdata.wip.typeSlot = CddlNode(kind: nkAny)

    # genericarg <- '<' * S * type1 * S * *(',' * S * type1 * S) * '>'
    genericarg <-
      genericargPush * genericargType1 * S * *(',' * S * genericargType1 * S) * '>' do:
      # the arguments stay in the type slot, for the name in front to take
      userdata.closeContainer(nkUnset)

    genericargPush <- '<' * S do:
      userdata.openContainer()

    genericargType1 <- >type1 do:
      userdata.members.add move(userdata.wip.typeSlot)

    # genericparm <- '<' * S * id * S * *(',' * S * id * S) * '>'
    genericparm <- '<' * S * genericparmId * S * *(',' * S * genericparmId * S) * '>'

    genericparmId <- >id do:
      userdata.ruleParams.add CddlNode(kind: nkParam, val: CddlNodeVal(text: $1))

    # occur <- ?uint * '*' * ?uint | '+' | '?'
    occur <- occurRange | occurOneOrMore | occurOptional

    occurRange <- >?uint * '*' * >?uint do:
      userdata.wip.val.occur.kind =
        if ($1).len + ($2).len > 0: ocRange else: ocZeroOrMore
      if ($1).len > 0:
        userdata.wip.val.occur.lo = parseNum($1, userdata.error, "occurrence bound")
      if ($2).len > 0:
        userdata.wip.val.occur.hi = parseNum($2, userdata.error, "occurrence bound")

    occurOneOrMore <- '+' do:
      userdata.wip.val.occur.kind = ocOneOrMore

    occurOptional <- '?' do:
      userdata.wip.val.occur.kind = ocOptional

    # groupname or typename
    refName <- id do:
      reset(userdata.wip.typeSlot)

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
    NL <- COMMENT | NEWLINE
    COMMENT <- >(';' * *PCHAR) * CRLF do:
      userdata.addComment($1, @1)
    NEWLINE <- >CRLF do:
      userdata.addBlank(@1)
    PCHAR <- {'\x20' .. '\x7E', '\x80' .. '\xFF'}
    CRLF <- ('\x0D' * '\x0A') | '\x0A'

    BINDIG <- '0' | '1'
    HEXDIG <- DIGIT | {'A' .. 'F'} | {'a' .. 'f'}
    DIGIT1 <- {'1' .. '9'}
    DIGIT <- {'0' .. '9'}
    EALPHA <- ALPHA | '@' | '_' | '$'
    ALPHA <- {'A' .. 'Z'} | {'a' .. 'z'}

  var state =
    ParseState(wip: initEntry(), source: source, ignoreComments: ignoreComments)

  let r =
    try:
      # XXX not unsafe, see https://github.com/zevv/npeg/issues/28
      {.cast(gcsafe).}:
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
  if state.error.len > 0:
    raise (ref CborCddlError)(msg: "CBOR CDDL parser error: " & state.error)
  if r.ok:
    doAssert r.matchLen == source.len
    state.flushNl(state.schema, blanks = true)
    CddlNode(kind: nkSchema, children: move(state.schema))
  else:
    raise newCddlError(source, r.matchLen, r.matchMax)

{.push raises: [], gcsafe.}

type WidthSink = object
  ## Counts what would be written to it rather than writing it, so that a
  ## choice can be measured without a rendering being built. The emitters that
  ## take one are generic over their sink, so what is counted here and what is
  ## written out can never come from two different pieces of code.
  width: int

proc write(
    w: var WidthSink, s: string
) {.raises: [IOError], hint[XCannotRaiseY]: off.} =
  w.width += s.len

proc write(w: var WidthSink, c: char) {.raises: [IOError], hint[XCannotRaiseY]: off.} =
  w.width += 1

func writeText(
    w: var WidthSink, x: SomeUnsignedInt
) {.raises: [IOError], hint[XCannotRaiseY]: off.} =
  var v = x
  inc w.width
  while v >= 10:
    v = v div 10
    inc w.width

proc emitInline[S](dst: var S, n: CddlNode) {.raises: [IOError].}

proc inlineWidth(n: CddlNode): int {.raises: [IOError].} =
  ## How wide emitInline would write this node, without writing it.
  var w = WidthSink()
  emitInline(w, n)
  w.width

proc emitParams[S](dst: var S, n: CddlNode, sep: string) {.raises: [IOError].} =
  ## The "<a, b>" a generic rule declares; nothing when it declares none.
  if n.genericParams.len > 0:
    dst.write '<'
    for i in 0 ..< n.genericParams.len:
      if i > 0:
        dst.write sep
      dst.write n.genericParams[i].val.text
    dst.write '>'

proc emitIn[S](dst: var S, n: CddlNode, needsParens = false) {.raises: [IOError].} =
  ## Write a node in the parens the position it is used in calls for; the ones
  ## written in the source are nkParen nodes and write themselves.
  if needsParens:
    dst.write '('
    emitInline(dst, n)
    dst.write ')'
  else:
    emitInline(dst, n)

proc emitList[S](dst: var S, nodes: seq[CddlNode], sep: string) {.raises: [IOError].} =
  var first = true
  for i in 0 ..< nodes.len: # by index: "for i, c in nodes" would copy each c
    if nodes[i].kind notin nlKinds: # one would swallow what follows it
      if not first:
        dst.write sep
      first = false
      emitIn(dst, nodes[i])

proc emitOperand[S](dst: var S, n: CddlNode) {.raises: [IOError].} =
  ## Operands of an operator are type2's, so anything composite needs parens
  ## to read back the way it was written.
  emitIn(dst, n, n.kind in {nkUnion, nkRange, nkControl})

proc emitOccur[S](dst: var S, o: CddlOccur) {.raises: [IOError].} =
  case o.kind
  of ocOne:
    discard
  of ocOptional:
    dst.write '?'
  of ocOneOrMore:
    dst.write '+'
  of ocZeroOrMore:
    dst.write '*'
  of ocRange:
    if o.lo.isSome:
      dst.writeText o.lo.get()
    dst.write '*'
    if o.hi.isSome:
      dst.writeText o.hi.get()

proc emitMajor[S](dst: var S, n: CddlNode) {.raises: [IOError].} =
  ## The "6.32" or "3" an nkTagged or nkMajor was written as, without its '#'.
  dst.writeText n.val.major
  if n.val.minor.isSome:
    dst.write '.'
    dst.writeText n.val.minor.get()

proc emitKeyPrefix[S](dst: var S, n: CddlNode) {.raises: [IOError].} =
  case n.val.sepKind
  of skNone:
    discard
  of skColon:
    emitIn(dst, n.key)
    dst.write ": "
  of skArrow:
    emitIn(dst, n.key)
    dst.write " => "
  of skArrowCut:
    emitIn(dst, n.key)
    dst.write " ^ => "

proc emitInline[S](dst: var S, n: CddlNode) {.raises: [IOError].} =
  case n.kind
  of nkUnset:
    dst.write "<unset>"
  of nkSchema:
    emitList(dst, n.children, " ")
  of nkRule:
    dst.write n.val.ruleText
    emitParams(dst, n, ", ")
    dst.write assignText(n.val.ruleKind)
    emitIn(dst, n.body)
  of nkEntry:
    if n.val.occur.kind != ocOne:
      emitOccur(dst, n.val.occur)
      dst.write ' '
    emitKeyPrefix(dst, n)
    emitIn(dst, n.body)
  of nkParam, nkTypeRef, nkValue:
    dst.write n.val.text
  of nkMap:
    dst.write '{'
    emitList(dst, n.children, ", ")
    dst.write '}'
  of nkArray:
    dst.write '['
    emitList(dst, n.children, ", ")
    dst.write ']'
  of nkGroup:
    dst.write '('
    emitList(dst, n.children, ", ")
    dst.write ')'
  of nkGroupChoice:
    # the alternatives are groups, but their entries are written out bare:
    # the "( ... )" of the enclosing container is the one that delimits them
    for i in 0 ..< n.children.len:
      if i > 0:
        dst.write " // "
      if n.children[i].kind == nkGroup:
        emitList(dst, n.children[i].children, ", ")
      else:
        emitIn(dst, n.children[i])
  of nkUnion:
    for i in 0 ..< n.children.len:
      if i > 0:
        dst.write " / "
      emitIn(dst, n.children[i], n.children[i].kind == nkUnion)
  of nkParen:
    dst.write '('
    emitInline(dst, n.target)
    dst.write ')'
  of nkTagged:
    dst.write '#'
    emitMajor(dst, n)
    dst.write '('
    emitIn(dst, n.target)
    dst.write ')'
  of nkMajor:
    dst.write '#'
    emitMajor(dst, n)
  of nkAny:
    dst.write '#'
  of nkGeneric:
    dst.write n.val.text
    dst.write '<'
    emitList(dst, n.children, ", ")
    dst.write '>'
  of nkRange:
    emitOperand(dst, n.lhs)
    dst.write rangeOpText(n.val.rangeKind)
    emitOperand(dst, n.rhs)
  of nkControl:
    emitOperand(dst, n.lhs)
    dst.write ' '
    dst.write n.val.text
    dst.write ' '
    emitOperand(dst, n.rhs)
  of nkUnwrap:
    dst.write '~'
    emitIn(dst, n.target)
  of nkEnum:
    dst.write '&'
    emitIn(dst, n.target)
  of nkComment, nkCommentInline:
    dst.write n.val.text # on its own; among other nodes emitList leaves it out
  of nkEmpty:
    discard # a line with nothing on it has nothing to write on one line

template intoString(body: untyped): string =
  ## Run the emitters against a memory stream and hand back what they wrote,
  ## or against a string when there is no stream to be had.
  var stream = memoryOutput()
  var dst {.inject.}: OutputStream = stream
  try:
    body
  except IOError:
    raiseAssert "memoryOutput is exception-free"
  stream.getOutput(string)

proc occurText*(o: CddlOccur): string =
  ## The "?", "+", "*" or "n*m" an occurrence was written as; empty for ocOne.
  intoString emitOccur(dst, o)

proc majorText*(n: CddlNode): string =
  ## The "6.32" or "3" an nkTagged or nkMajor was written as, without its '#'.
  doAssert n.kind in {nkTagged, nkMajor}
  intoString emitMajor(dst, n)

const
  prettyIndent = "  " ## one level of indentation
  prettyWrap* = 80
    ## the column a type choice is given before it is broken over lines of its
    ## own. Maps, arrays and groups are structure and always break; a choice is
    ## an expression, and one of two variants reads worse for being split up

func prettyDelims(k: CddlNodeKind): (char, char) =
  case k
  of nkMap:
    ('{', '}')
  of nkArray:
    ('[', ']')
  else:
    ('(', ')')

proc emitIndent(dst: var OutputStream, indent: int) {.raises: [IOError].} =
  for _ in 0 ..< indent:
    dst.write prettyIndent

proc emitPretty(dst: var OutputStream, n: CddlNode, indent: int) {.raises: [IOError].}

proc emitPrettyIn(
    dst: var OutputStream, n: CddlNode, indent: int, needsParens = false
) {.raises: [IOError].} =
  ## As emitIn, for a node that may still hold a container to be broken open.
  if needsParens:
    dst.write '('
    emitPretty(dst, n, indent)
    dst.write ')'
  else:
    emitPretty(dst, n, indent)

proc emitPrettyOperand(
    dst: var OutputStream, n: CddlNode, indent: int
) {.raises: [IOError].} =
  emitPrettyIn(dst, n, indent, n.kind in {nkUnion, nkRange, nkControl})

proc emitLines(
    dst: var OutputStream, nodes: seq[CddlNode], indent: int, sep: string
) {.raises: [IOError].} =
  var onLine = false
  for i in 0 ..< nodes.len:
    if nodes[i].kind == nkCommentInline and onLine:
      dst.write ' '
      dst.write nodes[i].val.text
      continue
    if onLine:
      dst.write '\n'
    onLine = true
    if nodes[i].kind == nkEmpty:
      continue # indenting a line with nothing on it would only trail spaces
    emitIndent(dst, indent)
    if nodes[i].kind in commentKinds:
      dst.write nodes[i].val.text
    else:
      emitPretty(dst, nodes[i], indent)
      dst.write sep
  if onLine:
    dst.write '\n'

proc emitPretty(dst: var OutputStream, n: CddlNode, indent: int) {.raises: [IOError].} =
  ## Write a node with every container it holds broken open, one member to a
  ## line, indented a level further in for each container it sits inside.
  ## Anything that is not a container is written the way emitInline writes it.
  case n.kind
  of nkSchema:
    emitLines(dst, n.children, indent, "")
  of nkRule:
    dst.write n.val.ruleText
    emitParams(dst, n, ", ")
    dst.write assignText(n.val.ruleKind)
    emitPretty(dst, n.body, indent)
  of nkEntry:
    if n.val.occur.kind != ocOne:
      emitOccur(dst, n.val.occur)
      dst.write ' '
    emitKeyPrefix(dst, n)
    emitPretty(dst, n.body, indent)
  of nkMap, nkArray, nkGroup:
    let (open, close) = prettyDelims(n.kind)
    dst.write open
    if n.children.len == 1 and n.children[0].kind notin nlKinds and
        n.children[0].kind != nkGroupChoice and n.children[0].val.sepKind == skNone:
      emitPretty(dst, n.children[0], indent)
    elif n.children.len > 0:
      # a choice writes out its own alternatives, and a comma after the last
      # of them would read as one more entry of that alternative
      var isChoice = false
      for i in 0 ..< n.children.len:
        if n.children[i].kind == nkGroupChoice:
          isChoice = true
      dst.write '\n'
      emitLines(dst, n.children, indent + 1, if isChoice: "" else: ",")
      emitIndent(dst, indent)
    dst.write close
  of nkGroupChoice:
    # each alternative stays on a line of its own: breaking their entries out
    # too would leave the "//" between them looking like it separates entries
    for i in 0 ..< n.children.len:
      if i > 0:
        dst.write " //\n"
        emitIndent(dst, indent)
      if n.children[i].kind == nkGroup:
        emitList(dst, n.children[i].children, ", ")
      else:
        emitIn(dst, n.children[i])
  of nkParen:
    dst.write '('
    emitPretty(dst, n.target, indent)
    dst.write ')'
  of nkTagged:
    dst.write '#'
    emitMajor(dst, n)
    dst.write '('
    emitPretty(dst, n.target, indent)
    dst.write ')'
  of nkUnwrap:
    dst.write '~'
    emitPretty(dst, n.target, indent)
  of nkEnum:
    dst.write '&'
    emitPretty(dst, n.target, indent)
  of nkUnion:
    # a short choice stays on its line; a long one gets a variant per line, the
    # first carrying on from whatever the choice was written after. What the
    # head of that line already took is not counted, so the wrap is a little
    # later than it looks - close enough for something with no line of its own
    if indent * prettyIndent.len + inlineWidth(n) <= prettyWrap:
      emitInline(dst, n)
    else:
      for i in 0 ..< n.children.len:
        if i > 0:
          dst.write " /\n"
          emitIndent(dst, indent + 1)
        emitPrettyIn(dst, n.children[i], indent + 1, n.children[i].kind == nkUnion)
  of nkRange:
    emitPrettyOperand(dst, n.lhs, indent)
    dst.write rangeOpText(n.val.rangeKind)
    emitPrettyOperand(dst, n.rhs, indent)
  of nkControl:
    emitPrettyOperand(dst, n.lhs, indent)
    dst.write ' '
    dst.write n.val.text
    dst.write ' '
    emitPrettyOperand(dst, n.rhs, indent)
  of nkGeneric:
    dst.write n.val.text
    dst.write '<'
    var first = true
    for i in 0 ..< n.children.len:
      if n.children[i].kind notin nlKinds:
        if not first:
          dst.write ", "
        first = false
        emitPrettyIn(dst, n.children[i], indent)
    dst.write '>'
  else:
    # a value, a reference, a major type or a comment: nothing below to open
    emitInline(dst, n)

func sameTree(a, b: CddlNode, withNl: bool): bool =
  ## Whether the two are the same schema. Without withNl the comments and
  ## blank lines on either side are passed over, which is what a rendering that
  ## leaves them out has to be held to.
  if a.kind != b.kind or a.val != b.val:
    return false
  var ai, bi = 0
  while true:
    if not withNl:
      while ai < a.children.len and a.children[ai].kind in nlKinds:
        inc ai
      while bi < b.children.len and b.children[bi].kind in nlKinds:
        inc bi
    if ai >= a.children.len or bi >= b.children.len:
      return ai >= a.children.len and bi >= b.children.len
    if not sameTree(a.children[ai], b.children[bi], withNl):
      return false
    inc ai
    inc bi

proc verify(n: CddlNode, cddl: string, pretty: bool) {.raises: [CborCddlError].} =
  ## Parse the cddl and check the result is equal to `n`.
  if n.kind notin {nkSchema, nkRule}:
    raise (ref CborCddlError)(msg: "The CDDL must be a schema or a rule")
  let back = parseCddl(cddl)
  let same =
    if n.kind == nkSchema:
      sameTree(n, back, pretty)
    else:
      # a rule is written as the one rule of a schema, so unwrap it to compare
      back.entryCount == 1 and sameTree(n, back.firstEntry, pretty)
  if not same:
    raise (ref CborCddlError)(msg: "Invalid CDDL result; it does not match the input")

proc toCddl*(
    n: CddlNode, pretty = false, verify = true
): string {.raises: [CborCddlError].} =
  ## Render a node as the CDDL it was parsed from. If `verify`
  ## is true, the `n` will be checked to match the resulting cddl.
  ## The verification is expensive, so if this is called at runtime
  ## it's good to enabled it only in debug mode.
  let ret =
    if pretty:
      intoString emitPretty(dst, n, 0)
    else:
      intoString emitInline(dst, n)
  if verify:
    verify(n, ret, pretty)
  ret

proc emitLabel(dst: var OutputStream, n: CddlNode) {.raises: [IOError].} =
  case n.kind
  of nkUnset:
    dst.write "<unset>"
  of nkSchema:
    dst.write "Schema"
  of nkRule:
    # the parameters are shown here rather than as children of their own
    dst.write "Rule "
    dst.write n.val.ruleText
    emitParams(dst, n, ",")
    dst.write " ["
    dst.write $n.val.ruleKind
    dst.write ']'
  of nkEntry:
    dst.write "Entry ["
    dst.write $n.val.occur.kind
    dst.write ']'
    if n.val.occur.kind == ocRange:
      dst.write ' '
      emitOccur(dst, n.val.occur)
    if n.val.sepKind != skNone:
      dst.write " key(" # the key is the first child
      dst.write $n.val.sepKind
      dst.write ')'
  of nkParam:
    dst.write "Param("
    dst.write n.val.text
    dst.write ')'
  of nkTypeRef:
    dst.write "TypeRef("
    dst.write n.val.text
    dst.write ')'
  of nkValue:
    dst.write "Value("
    dst.write n.val.text
    dst.write ')'
  of nkMap:
    dst.write "Map"
  of nkArray:
    dst.write "Array"
  of nkGroup:
    dst.write "Group"
  of nkGroupChoice:
    dst.write "GroupChoice"
  of nkUnion:
    dst.write "Union"
  of nkTagged:
    dst.write "Tagged(#"
    emitMajor(dst, n)
    dst.write ')'
  of nkMajor:
    dst.write "Major(#"
    emitMajor(dst, n)
    dst.write ')'
  of nkAny:
    dst.write "Any"
  of nkGeneric:
    dst.write "Generic("
    dst.write n.val.text
    dst.write ')'
  of nkRange:
    dst.write "Range("
    dst.write rangeOpText(n.val.rangeKind)
    dst.write ')'
  of nkControl:
    dst.write "Control("
    dst.write n.val.text
    dst.write ')'
  of nkParen:
    dst.write "Paren"
  of nkUnwrap:
    dst.write "Unwrap"
  of nkEnum:
    dst.write "Enum"
  of nkComment:
    dst.write "Comment("
    dst.write n.val.text
    dst.write ')'
  of nkCommentInline:
    dst.write "CommentInline("
    dst.write n.val.text
    dst.write ')'
  of nkEmpty:
    dst.write "Empty"

proc emitTree(dst: var OutputStream, n: CddlNode, indent: int) {.raises: [IOError].} =
  emitIndent(dst, indent)
  emitLabel(dst, n)
  for i in 0 ..< n.children.len:
    if n.children[i].kind != nkParam: # a rule shows those in its own label
      dst.write '\n'
      emitTree(dst, n.children[i], indent + 1)

proc dumpTree*(n: CddlNode): string =
  ## Indented tree rendering of a node and all of its children.
  intoString emitTree(dst, n, 0)

func allIn(
    nodes: seq[CddlNode], kinds: set[CddlNodeKind], first = 0, last = int.high
): bool =
  ## Whether every node in first .. last is of one of these kinds. Taken by
  ## index rather than as a slice, which would copy what it was handed.
  for i in first .. min(last, nodes.high):
    if nodes[i].kind notin kinds:
      return false
  true

func isValid*(n: CddlNode): bool =
  ## Valid a CddlNode tree is constructed correctly
  # - nkUnset: never valid; it's an unfilled slot, no part of a finished tree
  # - nkSchema: only rules, comments and blank lines, no two blanks in a row
  # - nkRule: zero or more nkParam, then exactly one body; a group rule binds
  #   an nkEntry, a type rule binds a type
  # - nkEntry: 1 child under skNone, 2 otherwise, body a type; under skColon
  #   the key must be nkTypeRef or nkValue, under the arrows any type
  # - nkMap/nkArray/nkGroup: entries and comments, or exactly one nkGroupChoice and no entries
  # - nkGroupChoice: >=2 alternatives, all nkGroup (one would have been unwrapped)
  # - nkUnion: >=2 variants, all types
  # - nkTagged: one type, and major == 6, since the grammar admits no other tag
  # - nkRange/nkControl: exactly two type operands
  # - nkParen/nkUnwrap/nkEnum: exactly one type
  # - leaves: no children
  for i in 0 ..< n.children.len:
    if not isValid(n.children[i]):
      return false
  let last = n.children.high
  case n.kind
  of nkUnset:
    false
  of nkSchema:
    var ok = allIn(n.children, {nkRule} + nlKinds)
    for i in 1 ..< n.children.len:
      # a run of blank lines is the one break, so two in a row never stand
      if n.children[i].kind == nkEmpty and n.children[i - 1].kind == nkEmpty:
        ok = false
    ok
  of nkRule:
    if n.children.len == 0 or not allIn(n.children, {nkParam}, last = last - 1):
      false
    elif n.val.ruleKind in groupRules:
      n.children[last].kind == nkEntry
    else:
      n.children[last].kind in typeKinds
  of nkEntry:
    if n.val.sepKind == skNone:
      n.children.len == 1 and n.children[0].kind in typeKinds
    elif n.children.len != 2 or n.children[1].kind notin typeKinds:
      false
    elif n.val.sepKind == skColon:
      n.children[0].kind in {nkTypeRef, nkValue}
    else:
      n.children[0].kind in typeKinds
  of nkMap, nkArray, nkGroup:
    var choices = 0
    var members = 0
    for i in 0 ..< n.children.len:
      case n.children[i].kind
      of nkGroupChoice:
        inc choices
      of nkEntry:
        inc members
      of nkComment, nkCommentInline:
        discard
      else:
        return false
    choices == 0 or (choices == 1 and members == 0)
  of nkGroupChoice:
    n.children.len >= 2 and allIn(n.children, {nkGroup})
  of nkUnion:
    n.children.len >= 2 and allIn(n.children, typeKinds)
  of nkGeneric:
    n.children.len >= 1 and allIn(n.children, typeKinds + commentKinds) and
      n.entryCount >= 1
  of nkTagged:
    n.children.len == 1 and n.children[0].kind in typeKinds and n.val.major == 6
  of nkRange, nkControl:
    n.children.len == 2 and allIn(n.children, typeKinds)
  of nkParen, nkUnwrap, nkEnum:
    n.children.len == 1 and n.children[0].kind in typeKinds
  of nkParam, nkTypeRef, nkValue, nkMajor, nkAny, nkComment, nkCommentInline, nkEmpty:
    n.children.len == 0
