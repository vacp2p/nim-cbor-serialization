# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import std/strutils, stew/shims/tables, ../../cbor_serialization/[reader, writer]

export tables

type TableType = OrderedTable | Table

proc writeImpl(writer: var CborWriter, value: TableType) {.raises: [IOError].} =
  writer.beginObject()
  for key, val in value:
    writer.writeField $key, val
  writer.endObject()

template to*(a: string, b: typed): untyped =
  {.error: "doesnt support keys with type " & $type(b).}

template to*(a: string, b: type int): int =
  parseInt(a)

template to*(a: string, b: type float): float =
  parseFloat(a)

template to*(a: string, b: type string): string =
  a

proc readImpl(
    reader: var CborReader, value: var TableType
) {.raises: [IOError, SerializationError].} =
  try:
    type KeyType = type(value.keys)
    type ValueType = type(value.values)
    value = init TableType
    for key, val in readObject(reader, string, ValueType):
      value[to(key, KeyType)] = val
  except ValueError as ex:
    reader.raiseUnexpectedValue("TableType: " & ex.msg)

# TODO: https://github.com/nim-lang/Nim/issues/25174

template write*(writer: var CborWriter, value: OrderedTable) =
  writeImpl(writer, value)

template write*(writer: var CborWriter, value: Table) =
  writeImpl(writer, value)

template read*(reader: var CborReader, value: var OrderedTable) =
  readImpl(reader, value)

template read*(reader: var CborReader, value: var Table) =
  readImpl(reader, value)
