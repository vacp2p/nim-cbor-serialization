{.push gcsafe, raises: [].}

# ANCHOR: Import
import cbor_serialization
# ANCHOR_END: Import

# ANCHOR: Custom
type CborRpcId = distinct CborBytes

proc readValue*(
    r: var Cbor.Reader, val: var CborRpcId
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

proc writeValue*(w: var Cbor.Writer, val: CborRpcId) {.raises: [IOError].} =
  w.writeValue(CborBytes(val)) # Preserve the original content

# ANCHOR_END: Custom

# ANCHOR: Request
type Request = object
  cborrpc: string
  `method`: string
  params: seq[int]
  id: CborRpcId # CBOR blob

let encoded = Cbor.encode(Request(id: Cbor.encode("test").CborRpcId))
let decoded = Cbor.decode(encoded, Request)
doAssert Cbor.decode(decoded.id.CborBytes.toBytes(), string) == "test"

# ANCHOR_END: Custom
