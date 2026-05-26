# CDDL

This section provides an overview of the `cbor_serialization` CDDL tools.

## Parsing

Concise Data Definition Language (CDDL) is a notation to describe CBOR and JSON. It is defined in [RFC8610](https://datatracker.ietf.org/doc/html/rfc8610).

The `fromCddl` API will parse a CDDL and generate Nim types out of it. It can be imported from the `type_generator` module:

```nim
{{#include ../examples/cddl0.nim:Import}}
```

It accepts the CDDL as a string, which can be hardcoded or read from a file using `staticRead`:

```nim
{{#include ../examples/cddl0.nim:Request}}
```

The `Request` object defined in the CDDL is generated and exported so it can be used from other modules:

```nim
{{#include ../examples/cddl0.nim:Encode}}
```

### Supported constructs

| CDDL construct | Nim output |
| --- | --- |
| Map types `{ key: type, ... }` | `object` |
| Type choices `a / b / c` | `enum` |
| Simple type references `foo = tstr` | `type` alias |
| Array types `[* T]` | `seq[T]` |
| Table types `{ * tstr => T }` | `Table[string, T]` |
| Optional fields `? key: type` | `Opt[T]` |

### Supported types

| CDDL type | Nim output |
| --- | --- |
| `any` | `CborBytes` |
| `uint`, `int`, `float32`, `float64`, `float`, `bool` | same |
| negative int `nint` | `int` |
| `float16`, `float16-32` | `float32` |
| `float32-64` | `float` |
| `bstr`, `bytes` | `seq[byte]` |
| `tstr`, `text` | `string` |

