{.push gcsafe, raises: [].}

# ANCHOR: Import
import cbor_serialization, cbor_serialization/json_utils
# ANCHOR_END: Import

# ANCHOR: json
let jsonDecoded = """{"cborrpc":"2.0","method":"subtract","params":[42,3],"id":1}"""
# ANCHOR: json

# ANCHOR: toCbor
let encoded = toCbor(jsonDecoded.JsonString)
# ANCHOR_END: toCbor

# ANCHOR: toJson
doAssert toJson(encoded.CborBytes) == jsonDecoded
# ANCHOR_END: toJson
