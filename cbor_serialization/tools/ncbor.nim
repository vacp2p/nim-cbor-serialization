# cbor-serialization
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/parseopt, stew/byteutils, ./json_converter

const helpMsg =
  """
ncbor - CBOR/JSON converter

Usage:
  ncbor --encode=json [--pretty] [<cbor-hex>]
  ncbor --encode=cbor [--hex] [<json>]

Options:
  --encode=json    Convert CBOR to JSON
  --encode=cbor    Convert JSON to CBOR
  --hex            Output CBOR as hexadecimal instead of binary (for --encode=cbor)
  --pretty         Output pretty-printed JSON (for --encode=json)
  --help, -h       Show this help message

Arguments:
  For --encode=json: hex-encoded CBOR bytes (e.g. a164746573748301020345)
  For --encode=cbor: JSON string (e.g. '{"key": "value"}')
  If no argument is given, data is read from stdin.
    --encode=json reads binary CBOR from stdin.
    --encode=cbor reads JSON text from stdin.

Examples:
  ncbor --encode=json a164746573748301020345
  echo '{"key": [1, 2, 3]}' | ncbor --encode=cbor
  ncbor --encode=cbor --hex '{"key": "value"}'
  ncbor --encode=json --pretty < data.cbor"""

type EncodeMode = enum
  ModeNone
  ModeToJson
  ModeToCbor

proc main() {.raises: IOError.} =
  var
    mode = ModeNone
    hexOutput = false
    prettyOutput = false
    argument = ""
    hasArg = false

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "encode":
        case p.val
        of "json":
          mode = ModeToJson
        of "cbor":
          mode = ModeToCbor
        else:
          stderr.writeLine "Error: unknown encode format '" & p.val & "'"
          quit(1)
      of "hex":
        hexOutput = true
      of "pretty":
        prettyOutput = true
      of "help", "h":
        echo helpMsg
        quit(0)
      else:
        stderr.writeLine "Error: unknown option '--" & p.key & "'"
        stderr.writeLine "Run 'ncbor --help' for usage."
        quit(1)
    of cmdArgument:
      argument = p.key
      hasArg = true

  if mode == ModeNone:
    stderr.writeLine "Error: --encode option is required"
    stderr.writeLine helpMsg
    quit(1)

  case mode
  of ModeToJson:
    let cborData =
      if hasArg:
        try:
          hexToSeqByte(argument)
        except ValueError as e:
          stderr.writeLine "Error: invalid hex input: " & e.msg
          quit(1)
      else:
        let raw = stdin.readAll()
        toBytes(raw)
    let json =
      try:
        toJson(CborBytes(cborData), pretty = prettyOutput)
      except SerializationError as e:
        stderr.writeLine "Error: " & e.msg
        quit(1)
    echo json
  of ModeToCbor:
    let jsonStr =
      if hasArg:
        argument
      else:
        stdin.readAll()
    let cborData =
      try:
        toCbor(JsonString(jsonStr))
      except SerializationError as e:
        stderr.writeLine "Error: " & e.msg
        quit(1)
    if hexOutput:
      echo toHex(cborData)
    else:
      echo string.fromBytes(cborData)
  of ModeNone:
    discard

main()
