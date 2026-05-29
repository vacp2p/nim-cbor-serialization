# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/[macros, strutils], unittest2, ../cbor_serialization/cddl/type_generator

proc fixAst(ast: NimNode): NimNode =
  proc inspect(node: NimNode): NimNode =
    case node.kind
    of {nnkIdent, nnkSym}:
      # remove `gensymX
      ident(split($node, '`')[0])
    of nnkEmpty:
      node
    of nnkLiterals:
      node
    of nnkCall:
      var ret = newNimNode(nnkBracketExpr)
      for i in 1 ..< node.len:
        ret.add inspect(node[i])
      ret
    else:
      var rTree = node.kind.newTree()
      for child in node:
        rTree.add inspect(child)
      rTree

  inspect(ast)

proc checkCddl(cddl: string, expected: NimNode) =
  let gened = fromCddlImpl(cddl.unindent)
  if gened != expected.fixAst:
    checkpoint("FAILED: Got: " & repr(gened) & "\nExpected: " & repr(expected.fixAst))
    fail()

suite "Test CDDL type generator":
  staticTest "map should generate an object":
    const cddl =
      """
      Person = {
        age: int,
        name: tstr,
        employer: tstr,
      }"""
    let expected = quote:
      type Person* = object
        age*: int64
        name*: string
        employer*: string

    checkCddl(cddl, expected)

  staticTest "map => should generate an object":
    const cddl =
      """
      Person = {
        age => int,
        name => tstr,
        employer => tstr,
      }"""
    let expected = quote:
      type Person* = object
        age*: int64
        name*: string
        employer*: string

    checkCddl(cddl, expected)

  staticTest "map of string keys should generate an object":
    const cddl =
      """
      Person = {
        "age" => int,
        "name" => tstr,
        "employer" => tstr,
      }"""
    let expected = quote:
      type Person* = object
        age*: int64
        name*: string
        employer*: string

    checkCddl(cddl, expected)

  staticTest "literal variant should generate an enum":
    const cddl =
      """
      ca = 0
      cb = 1
      cc = 2
      Choices = ca / cb / cc
      """
    let expected = quote:
      type Choices* {.pure.} = enum
        ca = 0
        cb = 1
        cc = 2

    checkCddl(cddl, expected)

  staticTest "literal variant of numbers should generate an enum":
    const cddl =
      """
      Choices = 0 / 1 / 2
      """
    let expected = quote:
      type Choices* {.pure.} = enum
        ch0 = 0
        ch1 = 1
        ch2 = 2

    checkCddl(cddl, expected)

  staticTest "literal variant of strings should generate an enum":
    const cddl =
      """
      Choices = "foo" / "bar" / "baz"
      """
    let expected = quote:
      type Choices* {.pure.} = enum
        ch0 = "foo"
        ch1 = "bar"
        ch2 = "baz"

    checkCddl(cddl, expected)

  staticTest "simple type should generate an alias":
    const cddl =
      """
      Foo = tstr
      Bar = int
      Baz = Bar
      """
    let expected = quote:
      type
        Foo* = string
        Bar* = int64
        Baz* = Bar

    checkCddl(cddl, expected)

  staticTest "array should generate a seq":
    const cddl =
      """
      IntSeq = [* int]
      """
    let expected = quote:
      type IntSeq* = seq[int64]

    checkCddl(cddl, expected)

  staticTest "map should generate a Table":
    const cddl =
      """
      IntMap = { * tstr => int }
      """
    let expected = quote:
      type IntMap* = Table[string, int64]

    checkCddl(cddl, expected)

  staticTest "optional should generate an Opt[T]":
    const cddl =
      """
      Foo = { ? opt: int }
      """
    let expected = quote:
      type Foo* = object
        opt*: Opt[int64]

    checkCddl(cddl, expected)

  staticTest "all type fields object":
    const cddl =
      """
      Bar = int
      Foo = {
        x01: any,
        x02: int,
        x03: uint,
        x04: float32,
        x05: float64,
        x06: float,
        x07: bool,
        x08: nint,
        x09: float16,
        x10: float16-32,
        x11: float32-64,
        x12: bstr,
        x13: bytes,
        x14: tstr,
        x15: text,
        x16: Bar,
        x16: { * tstr => int },
        x17: [* int],
        ? x18: int
      }"""
    let expected = quote:
      type
        Bar* = int64
        Foo* = object
          x01*: CborBytes
          x02*: int64
          x03*: uint64
          x04*: float32
          x05*: float64
          x06*: float
          x07*: bool
          x08*: int64
          x09*: float32
          x10*: float32
          x11*: float
          x12*: seq[byte]
          x13*: seq[byte]
          x14*: string
          x15*: string
          x16*: Bar
          x16*: Table[string, int64]
          x17*: seq[int64]
          x18*: Opt[int64]

    checkCddl(cddl, expected)

fromCddl(
  """
  ok = "ok"
  error = "error"
  Status = ok / error
  Response = {status: Status, message: text}
  """
)

suite "Test CDDL generated types":
  test "response object":
    check $Status.ok == "ok"
    check $Status.error == "error"
    discard Response(status: Status.ok, message: "foo")
