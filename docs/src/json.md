# JSON

This section provides an overview of the `cbor_serialization` json tools.

## JSON to CBOR

JSON can be converted to CBOR with the `toCbor(JsonString): seq[byte]` API.
The implementation converts JSON as described in [RFC8949](https://www.rfc-editor.org/rfc/rfc8949.html#section-6.2).

Requires the `json_serialization` nimble package.

Import `json_utils`:

```nim
{{#include ../examples/json0.nim:Import}}
```

Encode a JSON string to CBOR bytes:

```nim
{{#include ../examples/json0.nim:json}}
```

```nim
{{#include ../examples/json0.nim:toCbor}}
```

## CBOR to JSON

CBOR can be converted to JSON with the `toJson(CborBytes): string` API.
The implementation converts CBOR as described in [RFC8949](https://www.rfc-editor.org/rfc/rfc8949.html#section-6.1).

Note some CBOR types do not have direct analogs in JSON:

- NaN, -Infinity, Infinity, undefined, and simple values are converted to null.
- `seq[byte]` is base64 encoded.
- Tags 2, 21 and 22 are base64 encoded.
- Tag 3 is base64 encoded and prefixed with `~`.
- Tag 23 is hex encoded.
- All tag numbers are lost (not encoded); only their value is encoded.
- Non-string map keys are stringified using `toJson` which can create key collisions.

Requires the `json_serialization` nimble package.

Import `json_utils`:

```nim
{{#include ../examples/json0.nim:Import}}
```

Encode CBOR bytes to a JSON string:

```nim
{{#include ../examples/json0.nim:toJson}}
```
