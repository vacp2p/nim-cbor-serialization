# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import
  std/[strformat],
  faststreams/inputs,
  serialization/[formats, errors, object_serialization],
  ./[format, types]

export inputs, format, types, errors, DefaultFlavor

type CborParser* = object
  stream*: InputStream
  conf*: CborReaderConf
  currDepth*: int

type
  CborReader*[Flavor = DefaultFlavor] = object
    parser*: CborParser

  CborReaderError* = object of CborError
    pos*: int

  CborUnexpectedFieldError* = object of CborReaderError
    encounteredField*: string
    deserializedType*: cstring

  CborUnexpectedValueError* = object of CborReaderError

  CborNotEnoughBytesError* = object of CborUnexpectedValueError

  CborIncompleteObjectError* = object of CborReaderError
    objectType: cstring

  CborIntOverflowError* = object of CborReaderError
    isNegative: bool
    absIntVal: BiggestUInt

Cbor.setReader CborReader
Cbor.defaultReaders()

func valueStr(err: ref CborIntOverflowError): string =
  if err.isNegative:
    result.add '-'
  result.add($err.absIntVal)

method formatMsg*(err: ref CborReaderError, filename: string): string =
  fmt"{filename}({err.pos}) Error while reading cbor data: {err.msg}"

method formatMsg*(err: ref CborIntOverflowError, filename: string): string =
  fmt"{filename}({err.pos}) The value '{err.valueStr}' is outside of the allowed range"

method formatMsg*(err: ref CborUnexpectedValueError, filename: string): string =
  fmt"{filename}({err.pos}) {err.msg}"

method formatMsg*(err: ref CborNotEnoughBytesError, filename: string): string =
  fmt"{filename}({err.pos}) {err.msg}"

method formatMsg*(err: ref CborIncompleteObjectError, filename: string): string =
  fmt"{filename}({err.pos}) Not all required fields were specified when reading '{err.objectType}'"

func raiseUnexpectedValue*(
    p: CborParser, msg: string
) {.noreturn, raises: [CborReaderError].} =
  var ex = new CborUnexpectedValueError
  ex.pos = p.stream.pos
  ex.msg = msg
  raise ex

func raiseUnexpectedValue*(
    p: CborParser, expected, found: string
) {.noreturn, raises: [CborReaderError].} =
  p.raiseUnexpectedValue("Expected: " & expected & " but found: " & found)

template raiseUnexpectedValue*(r: CborReader, msg: string) =
  raiseUnexpectedValue(r.parser, msg)

func raiseNotEnoughBytes*(
    p: CborParser, msg: string
) {.noreturn, raises: [CborReaderError].} =
  var ex = new CborNotEnoughBytesError
  ex.pos = p.stream.pos
  ex.msg = msg
  raise ex

func raiseIntOverflow*(
    p: CborParser, absIntVal: BiggestUInt, isNegative: bool
) {.noreturn, raises: [CborReaderError].} =
  var ex = new CborIntOverflowError
  ex.pos = p.stream.pos
  ex.absIntVal = absIntVal
  ex.isNegative = isNegative
  raise ex

func raiseUnexpectedField*(
    p: CborParser, fieldName: string, deserializedType: cstring
) {.noreturn, raises: [CborReaderError].} =
  var ex = new CborUnexpectedFieldError
  ex.pos = p.stream.pos
  ex.encounteredField = fieldName
  ex.deserializedType = deserializedType
  raise ex

func raiseIncompleteObject*(
    p: CborParser, objectType: cstring
) {.noreturn, raises: [CborReaderError].} =
  var ex = new CborIncompleteObjectError
  ex.pos = p.stream.pos
  ex.objectType = objectType
  raise ex

template raiseIncompleteObject*(r: CborReader, objectType: cstring) =
  raiseIncompleteObject(r.parser, objectType)

proc init*(
    T: type CborParser,
    stream: InputStream,
    conf: CborReaderConf = defaultCborReaderConf,
): T =
  T(stream: stream, conf: conf, currDepth: 0)

proc init*(
    T: type CborReader,
    stream: InputStream,
    conf: CborReaderConf = defaultCborReaderConf,
): T =
  result.parser = CborParser.init(stream, conf)

{.pop.}
