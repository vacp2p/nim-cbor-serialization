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
  std/[math, strutils], stew/[base64, byteutils], json_serialization, ./[reader, writer]

export JsonString, CborBytes, SerializationError

# https://www.rfc-editor.org/rfc/rfc8949.html#section-6.1
proc writeToJson*(
    reader: var CborReader, writer: var JsonWriter, substitute = true
) {.raises: [IOError, SerializationError].} =
  mixin writeValue, readValue
  template p(): untyped =
    reader.parser

  template substituteOrRaise(msg: string): untyped =
    if substitute:
      writer.writeValue JsonString("null")
    else:
      p.raiseUnexpectedValue(msg)

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
      substituteOrRaise("Nan float")
    of fcInf:
      substituteOrRaise("Positive infinity float")
    of fcNegInf:
      substituteOrRaise("Negative infinity float")
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
      case tag
      of 2, 21:
        writer.writeValue(Base64Url.encode(reader.readValue(seq[byte])))
      of 3:
        writer.writeValue("~" & Base64Url.encode(reader.readValue(seq[byte])))
      of 22:
        writer.writeValue(Base64.encode(reader.readValue(seq[byte])))
      of 23:
        writer.writeValue("0x" & toUpperAscii(toHex(reader.readValue(seq[byte]))))
      else:
        writeToJson(reader, writer)
  of CborValueKind.Simple:
    let val = reader.readValue(CborSimpleValue)
    substituteOrRaise($val)
  of CborValueKind.Bool:
    writer.writeValue(reader.readValue(bool))
  of CborValueKind.Null:
    let _ = reader.readValue(CborSimpleValue)
    writer.writeValue JsonString("null")
  of CborValueKind.Undefined:
    let _ = reader.readValue(CborSimpleValue)
    substituteOrRaise("undefined")

proc toJson*(
    cbor: CborBytes, substitute = true, pretty = false
): string {.raises: [SerializationError].} =
  var cborStream = unsafeMemoryInput(seq[byte](cbor))
  var reader = CborReader[DefaultFlavor].init(cborStream)
  var jsonStream = memoryOutput()
  var writer = JsonWriter[DefaultFlavor].init(jsonStream, pretty)
  try:
    reader.writeToJson(writer, substitute)
  except IOError:
    raiseAssert "memoryOutput is exception-free"
  jsonStream.getOutput(string)

# https://www.rfc-editor.org/rfc/rfc8949.html#section-6.2
proc writeToCbor*(
    reader: var JsonReader, writer: var CborWriter
) {.raises: [IOError, SerializationError].} =
  mixin writeValue, readValue

  case reader.tokKind
  of JsonValueKind.String:
    writer.writeValue(reader.readValue(string))
  of JsonValueKind.Number:
    let num = reader.readValue(JsonNumber[uint64])
    if num.isFloat():
      writer.writeValue(reader.toFloat(num, float64))
    elif num.sign == JsonSign.Neg:
      writer.writeValue(reader.toInt(num, int64, portable = false))
    else:
      writer.writeValue(reader.toInt(num, uint64, portable = false))
  of JsonValueKind.Object:
    writeObject(writer):
      parseObjectWithoutSkip(reader, key):
        writer.writeName(key)
        writeToCbor(reader, writer)
  of JsonValueKind.Array:
    writeArray(writer):
      parseArray(reader):
        writeToCbor(reader, writer)
  of JsonValueKind.Bool:
    writer.writeValue(reader.readValue(bool))
  of JsonValueKind.Null:
    reader.parseNull()
    writer.writeValue(cborNull)

proc toCbor*(
    json: JsonString, definiteLen = false
): seq[byte] {.raises: [SerializationError].} =
  var jsonStream = unsafeMemoryInput(string(json))
  var reader = JsonReader[DefaultFlavor].init(jsonStream)
  var cborStream = memoryOutput()
  var writer = CborWriter[DefaultFlavor].init(cborStream)
  try:
    reader.writeToCbor(writer)
  except IOError:
    raiseAssert "memoryOutput is exception-free"
  if definiteLen:
    # XXX writeToCbor writes map/array as streams (indefinite length);
    #     decode-encode dance will convert indefinite to definite length;
    #     implement definiteLen mode in writeObject/Array to avoid this
    Cbor.encode(Cbor.decode(cborStream.getOutput(seq[byte]), CborValueRef))
  else:
    cborStream.getOutput(seq[byte])
