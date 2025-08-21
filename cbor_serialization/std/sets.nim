# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import stew/shims/sets, ../../cbor_serialization/[reader, writer]
export sets

type SetType = OrderedSet | HashSet | set

proc writeValue*(writer: var CborWriter, value: SetType) {.raises: [IOError].} =
  writer.writeIterable value

proc readValue*(
    reader: var CborReader, value: var SetType
) {.raises: [IOError, SerializationError].} =
  type ElemType = type(value.items)
  value = init SetType
  for elem in readArray(reader, ElemType):
    value.incl elem
