# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[macros, strutils], unittest2, ../cbor_serialization/tools/cddl/type_generator

proc removeSyms(ast: NimNode): NimNode =
  proc inspect(node: NimNode): NimNode =
    case node.kind
    of {nnkIdent, nnkSym}:
      # remove `gensymX
      return ident(split($node, '`')[0])
    of nnkEmpty:
      return node
    of nnkLiterals:
      return node
    of nnkOpenSymChoice:
      return inspect(node[0])
    else:
      var rTree = node.kind.newTree()
      for child in node:
        rTree.add inspect(child)
      return rTree

  result = inspect(ast)

proc checkCddl(cddl: string, expected: NimNode) =
  let gened = fromCddlImpl(cddl.unindent)
  if gened != expected.removeSyms:
    checkpoint("FAILED: " & repr(gened))
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
        age*: int
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
