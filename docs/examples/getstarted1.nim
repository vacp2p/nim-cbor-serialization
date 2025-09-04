{.push gcsafe, raises: [].}

# ANCHOR: Import
import cbor_serialization
# ANCHOR_END: Import

# ANCHOR: Custom
type CborRpcId = distinct CborRaw

proc readValue*(
    r: var CborReader, val: var CborRpcId
) {.raises: [IOError, CborReaderError].} =
  let ckind = r.parser.cborKind()
  case ckind
  of CborValueKind.Number, CborValueKind.String, CborValueKind.Null:
    # Keep the original value without further processing
    var raw: CborRaw
    r.parseValue(raw)
    val = CborRpcId(raw)
  else:
    r.parser.raiseUnexpectedValue("Invalid RequestId, got " & $ckind)

proc writeValue*(w: var CborWriter, val: CborRpcId) {.raises: [IOError].} =
  w.writeValue(CborRaw(val)) # Preserve the original content

# ANCHOR_END: Custom

# ANCHOR: Request
type Request = object
  cborrpc: string
  `method`: string
  params: seq[int]
  id: CborRpcId # CBOR blob

let encoded = Cbor.encode((id: Cbor.encode("test").CborRpcId))
let decoded = Cbor.decode(encoded, Request)
echo Cbor.decode(decoded.id.CborRaw.toBytes(), string)

# ANCHOR_END: Custom
