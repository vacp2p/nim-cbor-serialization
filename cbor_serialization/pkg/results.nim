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

type ResultType[T] = Result[T, void]

template shouldWriteObjectField*[T](field: Result[T, void]): bool =
  field.isOk

proc writeValue*(writer: var CborWriter, value: ResultType) {.raises: [IOError].} =
  mixin writeValue

  if value.isOk:
    writer.writeValue value.get
  else:
    writer.writeValue cborNull

proc readValue*(
    reader: var CborReader, value: var ResultType
) {.raises: [IOError, SerializationError].} =
  mixin readValue

  if reader.parser.cborKind() in {CborValueKind.Null, CborValueKind.Undefined}:
    reset value
    discard reader.parseSimpleValue()
  else:
    value.ok reader.readValue(typeof(value).T)

func isFieldExpected*[T, E](_: type[Result[T, E]]): bool {.compileTime.} =
  false
