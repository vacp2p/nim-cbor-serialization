# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/[net, strutils], chronos/transports/common, ../../cbor_serialization

export net, common

proc write*(writer: var CborWriter, value: IpAddress) {.raises: [IOError].} =
  mixin writeValue
  writeValue(writer, $value)

proc read*(reader: var CborReader, value: var IpAddress) =
  mixin readValue
  let s = reader.readValue(string)
  try:
    value = parseIpAddress s
  except CatchableError:
    raiseUnexpectedValue(reader, "Invalid IP address")

proc write*(writer: var CborWriter, value: Port) {.raises: [IOError].} =
  mixin writeValue
  writeValue(writer, uint16 value)

proc read*(reader: var CborReader, value: var Port) =
  mixin readValue
  value = Port reader.readValue(uint16)

proc write*(writer: var CborWriter, value: AddressFamily) {.raises: [IOError].} =
  mixin writeValue
  writeValue(writer, $value)

proc read*(reader: var CborReader, value: var AddressFamily) =
  mixin readValue
  value = parseEnum[AddressFamily](reader.readValue(string))
