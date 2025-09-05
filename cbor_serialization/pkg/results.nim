# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import pkg/results, ../../cbor_serialization/[reader, writer]

export results

template shouldWriteObjectField*[T](field: Result[T, void]): bool =
  field.isOk

proc writeValue*[T](
    writer: var CborWriter, value: Result[T, void]
) {.raises: [IOError].} =
  mixin writeValue

  if value.isOk:
    writer.writeValue value.get
  else:
    writer.writeValue cborNull

proc readValue*[T](
    reader: var CborReader, value: var Result[T, void]
) {.raises: [IOError, SerializationError].} =
  mixin readValue

  if reader.parser.cborKind() in {CborValueKind.Null, CborValueKind.Undefined}:
    reset value
    discard reader.parseSimpleValue()
  else:
    value.ok reader.readValue(T)

func isFieldExpected*[T, E](_: type[Result[T, E]]): bool {.compileTime.} =
  false
