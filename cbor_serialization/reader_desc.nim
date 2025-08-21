# cbor-serialization
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  faststreams/inputs,
  serialization/[formats, errors, object_serialization],
  "."/[format, types]

export
  inputs, format, types, errors,
  DefaultFlavor

type
  CborParser* = object
    stream*: InputStream
    #err*: CborErrorKind
    flags*: CborReaderFlags
    #conf*: CborReaderConf

type
  CborReader*[Flavor = DefaultFlavor] = object
    parser*: CborParser

  CborReaderError* = object of CborError

  UnexpectedFieldError* = object of CborReaderError
    encounteredField*: string
    deserializedType*: cstring

  UnexpectedValueError* = object of CborReaderError

  IntOverflowError* = object of CborReaderError
    isNegative: bool
    absIntVal: BiggestUInt

Cbor.setReader CborReader

func raiseUnexpectedValue*(
    parse: CborParser, msg: string) {.noreturn, raises: [CborReaderError].} =
  var ex = new UnexpectedValueError
  #ex.assignColNumber(parse)
  ex.msg = msg
  raise ex

func raiseUnexpectedValue*(
    parse: CborParser, expected, found: string) {.noreturn, raises: [CborReaderError].} =
  raiseUnexpectedValue(parse, "Expected: " & expected & " Found: " & found)

func raiseIntOverflow*(absIntVal: BiggestUInt, isNegative: bool)
    {.noreturn.} =
  var ex = new IntOverflowError
  ex.absIntVal = absIntVal
  ex.isNegative = isNegative
  raise ex

func raiseUnexpectedField*(fieldName: string, deserializedType: cstring)
    {.noreturn, raises: [CborReaderError].} =
  var ex = new UnexpectedFieldError
  ex.encounteredField = fieldName
  ex.deserializedType = deserializedType
  raise ex

proc init*(
  T: type CborParser,
  stream: InputStream,
  flags: CborReaderFlags = defaultCborReaderFlags,
  #conf: JsonReaderConf = defaultJsonReaderConf
): T =
  T(
    stream: stream,
    flags: flags,
    #conf: conf,
  )

proc init*(
  T: type CborReader,
  stream: InputStream,
  flags: CborReaderFlags,
  #conf: CborReaderConf = defaultCborReaderConf
): T =
  result.parser = CborParser.init(stream, flags) #, conf)

proc init*(T: type CborReader,
           stream: InputStream,
           allowUnknownFields = false,
           requireAllFields = false): T =
  mixin flavorAllowsUnknownFields, flavorRequiresAllFields
  type Flavor = T.Flavor

  var flags = defaultCborReaderFlags
  if allowUnknownFields or flavorAllowsUnknownFields(Flavor):
    flags.incl CborReaderFlag.allowUnknownFields
  if requireAllFields or flavorRequiresAllFields(Flavor):
    flags.incl CborReaderFlag.requireAllFields
  result.parser = CborParser.init(stream, flags)
