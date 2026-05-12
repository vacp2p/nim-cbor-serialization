# cbor-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import
  std/[math, strutils],
  pkg/json_serialization,
  stew/[base64, byteutils],
  ../../cbor_serialization/[reader, writer]

# https://www.rfc-editor.org/rfc/rfc8949.html#section-6.1

proc writeToJson*(
    reader: var CborReader, writer: var JsonWriter
) {.raises: [IOError, SerializationError].} =
  mixin writeValue, readValue
  template p(): untyped =
    reader.parser

  case p.cborKind()
  of CborValueKind.Bytes:
    writer.writeValue(Base64Url.encode(reader.readValue(seq[byte])))
  of CborValueKind.String:
    writer.writeValue(reader.readValue(string))
  of CborValueKind.Unsigned:
    writer.writeValue(reader.readValue(uint64))
  of CborValueKind.Negative:
    writer.writeValue(reader.readValue(int64))
  of CborValueKind.Float:
    let f = reader.readValue(float64)
    case f.classify
    of fcNan:
      p.raiseUnexpectedValue("Nan float")
    of fcInf:
      p.raiseUnexpectedValue("Positive infinity float")
    of fcNegInf:
      p.raiseUnexpectedValue("Negative infinity float")
    else:
      writer.writeValue(f)
  of CborValueKind.Object:
    writeObject(writer):
      parseObject(reader, key):
        writer.writeName(key)
        writeToJson(reader, writer)
  of CborValueKind.Array:
    writeArray(writer):
      parseArray(reader):
        writeToJson(reader, writer)
  of CborValueKind.Tag:
    var tag: uint64
    parseTag(reader, tag):
      if tag in {2, 3}: # bignum
        case p.cborKind()
        of CborValueKind.Bytes:
          if tag == 2:
            writer.writeValue(Base64Url.encode(reader.readValue(seq[byte])))
          else:
            doAssert tag == 3
            writer.writeValue("~" & Base64Url.encode(reader.readValue(seq[byte])))
        else:
          p.raiseUnexpectedValue("bytes", $p.cborKind())
      elif tag in {21, 22, 23}: # content hint
        case p.cborKind()
        of CborValueKind.Bytes:
          if tag == 21:
            writer.writeValue(Base64Url.encode(reader.readValue(seq[byte])))
          elif tag == 22:
            writer.writeValue(Base64.encode(reader.readValue(seq[byte])))
          else:
            doAssert tag == 23
            writer.writeValue("0x" & toUpperAscii(toHex(reader.readValue(seq[byte]))))
        else:
          p.raiseUnexpectedValue("bytes", $p.cborKind())
      else:
        writeToJson(reader, writer)
  of CborValueKind.Simple:
    let val = reader.readValue(CborSimpleValue)
    p.raiseUnexpectedValue($val)
  of CborValueKind.Bool:
    writer.writeValue(reader.readValue(bool))
  of CborValueKind.Null:
    let _ = reader.readValue(CborSimpleValue)
    writer.writeValue JsonString("null")
  of CborValueKind.Undefined:
    let _ = reader.readValue(CborSimpleValue)
    p.raiseUnexpectedValue("undefined")

proc cborToJson*(cbor: seq[byte]): string {.raises: [IOError, SerializationError].} =
  var cborStream = unsafeMemoryInput(cbor)
  var reader = CborReader[DefaultFlavor].init(cborStream)
  var jsonStream = memoryOutput()
  var writer = JsonWriter[DefaultFlavor].init(jsonStream)
  reader.writeToJson(writer)
  jsonStream.getOutput(string)
