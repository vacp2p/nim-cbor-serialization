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

proc writeValue*(writer: var CborWriter, value: IpAddress) {.raises: [IOError].} =
  writeValue(writer, $value)

proc readValue*(reader: var CborReader, value: var IpAddress) =
  let s = reader.readValue(string)
  try:
    value = parseIpAddress s
  except CatchableError:
    raiseUnexpectedValue(reader, "Invalid IP address")

proc writeValue*(writer: var CborWriter, value: Port) {.raises: [IOError].} =
  writeValue(writer, uint16 value)

proc readValue*(reader: var CborReader, value: var Port) =
  value = Port reader.readValue(uint16)

proc writeValue*(writer: var CborWriter, value: AddressFamily) {.raises: [IOError].} =
  writeValue(writer, $value)

proc readValue*(reader: var CborReader, value: var AddressFamily) =
  value = parseEnum[AddressFamily](reader.readValue(string))
