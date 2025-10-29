{.push gcsafe, raises: [].}

# ANCHOR: Import
import cbor_serialization, cbor_serialization/pkg/results
export cbor_serialization, results
# ANCHOR_END: Import

# ANCHOR: Create
createCborFlavor CrpcSys,
  automaticObjectSerialization = false,
  requireAllFields = true,
  omitOptionalFields = true, # Don't output `none` values when writing
  allowUnknownFields = false

CrpcSys.defaultSerialization(Result)
# ANCHOR_END: Create

# ANCHOR: Custom
type CborRpcId = distinct CborBytes

proc readValue*(
    r: var CrpcSys.Reader, val: var CborRpcId
) {.raises: [IOError, CborReaderError].} =
  let ckind = r.parser.cborKind()
  case ckind
  of CborValueKind.Unsigned, CborValueKind.Negative, CborValueKind.String,
      CborValueKind.Null:
    # Keep the original value without further processing
    var raw: CborBytes
    r.parseValue(raw)
    val = CborRpcId(raw)
  else:
    r.parser.raiseUnexpectedValue("Invalid RequestId, got " & $ckind)

proc writeValue*(w: var CrpcSys.Writer, val: CborRpcId) {.raises: [IOError].} =
  w.writeValue(CborBytes(val)) # Preserve the original content

# ANCHOR_END: Custom

# ANCHOR: Request
type Request = object
  cborrpc: string
  `method`: string
  params: Opt[seq[int]]
  id: Opt[CborRpcId]

# ANCHOR_END: Request

# ANCHOR: Auto
# Allow serializing the `Request` type - serializing other types will result in
# a compile-time error because `automaticObjectSerialization` is false!
CrpcSys.defaultSerialization Request
# ANCHOR_END: Auto

# ANCHOR: Encode
let cbor = Cbor.encode(
  Request(
    cborrpc: "2.0",
    `method`: "subtract",
    params: Opt.some(@[42, 3]),
    id: Opt.some(Cbor.encode(1).CborRpcId),
  )
)

let decoded = CrpcSys.decode(cbor, Request)
echo decoded
# ANCHOR_END: Encode

doAssert CrpcSys.encode(decoded) == cbor
