# ANCHOR: Import
{.push gcsafe, raises: [].} # Encourage exception handling hygiene in procedures!

import cbor_serialization
export cbor_serialization
# ANCHOR_END: Import

# ANCHOR: Request
type Request = object
  cborrpc: string
  `method`: string # Quote Nim keywords
  params: seq[int] # Map CBOR array to `seq`
  id: int

# ANCHOR_END: Request

# ANCHOR: Encode
# Encode a Request type into a CBOR blob
let encoded =
  Cbor.encode(Request(cborrpc: "2.0", `method`: "subtract", params: @[42, 3], id: 1))
# ANCHOR_END: Encode

# ANCHOR: Decode
# Decode the CBOR blob into our Request type
let decoded = Cbor.decode(encoded, Request)

doAssert decoded.id == 1
# ANCHOR_END: Decode

# ANCHOR: Errors
try:
  # Oops, a string was used for the `id` field!
  discard Cbor.decode(Cbor.encode((id: "test")), Request)
  doAssert false
except CborError as exc:
  # "<string>" helps identify the source of the data - this can be a
  # filename, URL or something else that helps the user find the error
  echo "Failed to parse data: ", exc.formatMsg("<string>")
# ANCHOR_END: Errors
