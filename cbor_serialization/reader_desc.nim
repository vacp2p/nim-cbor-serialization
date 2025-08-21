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
  "."/[format, types]

export inputs, format, types, errors, DefaultFlavor

type CborParser* = object
  stream*: InputStream
  flags*: CborReaderFlags
  conf*: CborReaderConf
  currDepth*: int

type
  CborReader*[Flavor = DefaultFlavor] = object
    parser*: CborParser

  CborReaderError* = object of CborError

  UnexpectedFieldError* = object of CborReaderError
    encounteredField*: string
    deserializedType*: cstring

  UnexpectedValueError* = object of CborReaderError

  IncompleteObjectError* = object of CborReaderError
    objectType: cstring

  IntOverflowError* = object of CborReaderError
    isNegative: bool
    absIntVal: BiggestUInt

Cbor.setReader CborReader

func valueStr(err: ref IntOverflowError): string =
  if err.isNegative:
    result.add '-'
  result.add($err.absIntVal)

template tryFmt(expr: untyped): string =
  try:
    expr
  except CatchableError as err:
    err.msg

method formatMsg*(err: ref CborReaderError, filename: string): string =
  tryFmt:
    fmt"{filename} Error while reading json file: {err.msg}"

method formatMsg*(err: ref IntOverflowError, filename: string): string =
  tryFmt:
    fmt"{filename} The value '{err.valueStr}' is outside of the allowed range"

method formatMsg*(err: ref UnexpectedValueError, filename: string): string =
  tryFmt:
    fmt"{filename} {err.msg}"

method formatMsg*(err: ref IncompleteObjectError, filename: string): string =
  tryFmt:
    fmt"{filename} Not all required fields were specified when reading '{err.objectType}'"

func raiseUnexpectedValue*(msg: string) {.noreturn, raises: [CborReaderError].} =
  var ex = new UnexpectedValueError
  ex.msg = msg
  raise ex

func raiseUnexpectedValue*(
    expected, found: string
) {.noreturn, raises: [CborReaderError].} =
  raiseUnexpectedValue("Expected: " & expected & " but found: " & found)

func raiseIntOverflow*(
    absIntVal: BiggestUInt, isNegative: bool
) {.noreturn, raises: [CborReaderError].} =
  var ex = new IntOverflowError
  ex.absIntVal = absIntVal
  ex.isNegative = isNegative
  raise ex

func raiseUnexpectedField*(
    fieldName: string, deserializedType: cstring
) {.noreturn, raises: [CborReaderError].} =
  var ex = new UnexpectedFieldError
  ex.encounteredField = fieldName
  ex.deserializedType = deserializedType
  raise ex

func raiseIncompleteObject*(
    objectType: cstring
) {.noreturn, raises: [CborReaderError].} =
  var ex = new IncompleteObjectError
  ex.objectType = objectType
  raise ex

proc init*(
    T: type CborParser,
    stream: InputStream,
    flags: CborReaderFlags = defaultCborReaderFlags,
    conf: CborReaderConf = defaultCborReaderConf,
): T =
  T(stream: stream, flags: flags, conf: conf, currDepth: 0)

proc init*(
    T: type CborReader,
    stream: InputStream,
    flags: CborReaderFlags,
    conf: CborReaderConf = defaultCborReaderConf,
): T =
  result.parser = CborParser.init(stream, flags, conf)

proc init*(
    T: type CborReader,
    stream: InputStream,
    allowUnknownFields = false,
    requireAllFields = false,
): T =
  mixin flavorAllowsUnknownFields, flavorRequiresAllFields
  type Flavor = T.Flavor

  var flags = defaultCborReaderFlags
  if allowUnknownFields or flavorAllowsUnknownFields(Flavor):
    flags.incl CborReaderFlag.allowUnknownFields
  if requireAllFields or flavorRequiresAllFields(Flavor):
    flags.incl CborReaderFlag.requireAllFields
  result.parser = CborParser.init(stream, flags)

{.pop.}
