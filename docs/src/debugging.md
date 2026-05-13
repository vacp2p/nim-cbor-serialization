# Debugging

This section provides an overview of the `cbor_serialization` debugging tools.

## Diagnostic Notation

The CBOR diagnostic notation is a human-readable format defined in [RFC8949](https://www.rfc-editor.org/rfc/rfc8949.html#section-8) and [RFC8610](https://www.rfc-editor.org/rfc/rfc8610#appendix-G). It's based on JSON, but it's not compatible with it.

The `toEdn` API will decode CBOR bytes into a string in diagnostic notation format:

```nim
{{#include ../examples/debugging0.nim:Edn}}
```

Notation summary:

- Non-finite floating-point: `Infinity`, `-Infinity`, `NaN`
- Tags: `tagNumer(tagValue)`, ex: `0("2013-03-21T20:04:00Z")`
- Byte strings: `h'base16Value'`, ex: `h'01020304'`
- Simple: `simple(simpleValue)`, ex: `simple(42)`
- Non-string map keys: `{key: value}`, ex: `{1: 2}`, `{[1]: 2}`, `{{1: 2}: 3}`
- Indefinite length: Undercore + space after `{`, `[`; ex: `{_ "a": "b"}`, `[_ 1, 2]`
- Other values borrow the notation from JSON.
