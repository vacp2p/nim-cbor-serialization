# cbor-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/[formatfloat, math], stew/byteutils, serialization, ./reader

export serialization, reader

proc addEscaped(res: var string, value: string) =
  template addPrefixSlash(c) =
    res.add '\\'
    res.add c

  const hexChars = "0123456789abcde"
  for c in value:
    case c
    of '\b':
      addPrefixSlash 'b'
    # \x08
    of '\t':
      addPrefixSlash 't'
    # \x09
    of '\n':
      addPrefixSlash 'n'
    # \x0a
    of '\f':
      addPrefixSlash 'f'
    # \x0c
    of '\r':
      addPrefixSlash 'r'
    # \x0d
    of '"':
      addPrefixSlash '\"'
    of '\\':
      addPrefixSlash '\\'
    of '\x00' .. '\x07', '\x0b', '\x0e' .. '\x1f':
      res.add "\\u00"
      res.add hexChars[(uint8(c) shr 4) and 0x0f]
      res.add hexChars[uint8(c) and 0x0f]
    else:
      res.add c

proc hasIndefLen(reader: var CborReader): bool {.raises: [IOError].} =
  doAssert reader.parser.stream.readable
  let x = reader.parser.stream.peek()
  (x and 0b0001_1111) == cborMinorIndef

# TODO: chunks show as concatenated string/bytes;
#       PR https://github.com/vacp2p/nim-cbor-serialization/pull/17
#       gives access to "prelude" which can be used to anotate the chunk split

# https://www.rfc-editor.org/rfc/rfc8949.html#section-8
# https://www.rfc-editor.org/rfc/rfc8610#appendix-G
proc toEdnImpl(
    reader: var CborReader
): string {.raises: [IOError, SerializationError].} =
  mixin readValue
  template p(): untyped =
    reader.parser

  result = ""
  case p.cborKind()
  of CborValueKind.Bytes:
    result.add "h'"
    result.add toHex(reader.readValue(seq[byte]))
    result.add '\''
  of CborValueKind.String:
    result.add '"'
    result.addEscaped reader.readValue(string)
    result.add '"'
  of CborValueKind.Unsigned:
    result.add $reader.readValue(uint64)
  of CborValueKind.Negative:
    let val = reader.readValue(CborNumber)
    if val.integer == uint64.high:
      result.add "-18446744073709551616"
    else:
      result.add '-'
      result.add $(val.integer + 1)
  of CborValueKind.Float:
    let f = reader.readValue(float64)
    case f.classify
    of fcNan:
      result.add "NaN"
    of fcInf:
      result.add "Infinity"
    of fcNegInf:
      result.add "-Infinity"
    else:
      result.addFloatRoundtrip f
  of CborValueKind.Object:
    result.add '{'
    if reader.hasIndefLen():
      result.add "_ "
    var i = 0
    parseObjectCustomKey(reader):
      if i > 0:
        result.add ", "
      result.add toEdnImpl(reader)
      result.add ": "
    do:
      result.add toEdnImpl(reader)
      inc i
    result.add '}'
  of CborValueKind.Array:
    result.add '['
    if reader.hasIndefLen():
      result.add "_ "
    var i = 0
    parseArray(reader):
      if i > 0:
        result.add ", "
      result.add toEdnImpl(reader)
      inc i
    result.add ']'
  of CborValueKind.Tag:
    var tag: uint64
    parseTag(reader, tag):
      result.add $tag
      result.add '('
      result.add toEdnImpl(reader)
      result.add ')'
  of CborValueKind.Simple, CborValueKind.Bool, CborValueKind.Null,
      CborValueKind.Undefined:
    result.add $reader.readValue(CborSimpleValue)

# CBOR Sequence: https://datatracker.ietf.org/doc/html/rfc8742#section-4.2
proc toEdnSeqImpl(
    reader: var CborReader
): string {.raises: [IOError, SerializationError].} =
  result = reader.toEdnImpl()
  var i = 0
  while reader.parser.stream.readable():
    result.add ", "
    result.add reader.toEdnImpl()
    inc i

proc toEdn*(
    cbor: CborBytes, Flavor = DefaultFlavor
): string {.raises: [SerializationError].} =
  ## Converts `cbor` content into Diagnostic Notation
  var stream = unsafeMemoryInput(seq[byte](cbor))
  var reader = CborReader[Flavor].init(stream)
  try:
    reader.toEdnSeqImpl()
  except IOError:
    raiseAssert "memoryOutput is exception-free"
