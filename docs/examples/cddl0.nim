{.push gcsafe, raises: [].}

# ANCHOR: Import
import cbor_serialization, cbor_serialization/tools/cddl/type_generator
# ANCHOR_END: Import

# ANCHOR: Request
fromCddl """
Request = {
  cborrpc: text     ; CBOR RPC version
  method: text      ; API method name
  params: [* int]   ; API parameters
  id: int
}
"""
# ANCHOR_END: Request

# ANCHOR: Encode
let encoded =
  Cbor.encode(Request(cborrpc: "2.0", `method`: "subtract", params: @[42, 3], id: 1))
# ANCHOR_END: Encode
