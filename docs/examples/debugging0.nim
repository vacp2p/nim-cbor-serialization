# ANCHOR: Import
{.push gcsafe, raises: [].}

import cbor_serialization, cbor_serialization/edn
# ANCHOR_END: Import

# ANCHOR: Request
type Request = object
  cborrpc: string
  `method`: string
  params: seq[int]
  id: int

# ANCHOR_END: Request

# ANCHOR: Encode
let encoded =
  Cbor.encode(Request(cborrpc: "2.0", `method`: "subtract", params: @[42, 3], id: 1))
# ANCHOR_END: Encode

# ANCHOR: Edn
# Decode the CBOR blob into Diagnostic Notation
doAssert CborBytes(encoded).toEdn() ==
  """{"cborrpc": "2.0", "method": "subtract", "params": [42, 3], "id": 1}"""
# ANCHOR_END: Edn
