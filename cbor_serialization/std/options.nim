# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/options, ../../cbor_serialization/[reader, writer]
export options

template shouldWriteObjectField*(field: Option): bool =
  field.isSome

proc writeValue*(writer: var CborWriter, value: Option) {.raises: [IOError].} =
  mixin writeValue

  if value.isSome:
    writer.writeValue value.get
  else:
    writer.writeValue cborNull

proc readValue*[T](
    reader: var CborReader, value: var Option[T]
) {.raises: [IOError, SerializationError].} =
  mixin readValue

  if reader.parser.cborKind() in {CborValueKind.Null, CborValueKind.Undefined}:
    reset value
    discard reader.parseSimpleValue()
  else:
    value = some reader.readValue(T)
