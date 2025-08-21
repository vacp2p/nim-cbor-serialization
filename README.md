# nim-json-serialization

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)
![Github action](https://github.com/vacp2p/nim-cbor-serialization/workflows/CI/badge.svg)

## Introduction

<!-- ANCHOR: Features -->

`nim-cbor-serialization` is a library in the [nim-serialization](https://github.com/status-im/nim-serialization) family for turning Nim objects into [CBOR](https://cbor.io/) and back. Features include:

- Efficient coding of CBOR directly to and from Nim data types
  - Full type-based customization of both encoding and decoding
  - Flavors for defining multiple CBOR serialization styles per Nim type
  - Efficient skipping of data items for partial CBOR parsing
- Flexibility in mixing type-based and dynamic CBOR access
  - Structured `CborValueRef` node type for DOM-style access to parsed data
  - Flat `CborRaw` type for passing nested CBOR data between abstraction layers
- [RFC8949 spec compliance](https://www.rfc-editor.org/rfc/rfc8949.html)
  - Passes [CBORTestVectors](https://github.com/cbor/test-vectors/)
  - Customizable parser strictness including support for non-standard extensions
- Well-defined handling of malformed / malicious inputs with configurable parsing limits

<!-- ANCHOR_END: Features -->

## Getting started

```nim
requires "cbor_serialization"
```

Create a type and use it to encode and decode CBOR:

```nim
import cbor_serialization, stew/[byteutils]

type Request = object
  cborrpc: string
  `method`: string

# {"cborrpc": "2.0", "method": "name"}
let cbor = hexToSeqByte "0xA26763626F7272706363322E30666D6574686F64646E616D65"
let decoded = Cbor.decode(cbor, Request)

echo decoded.jsonrpc
echo Cbor.encode(decoded).to0xHex()
```

## Documentation

See the [user guide](https://vacp2p.github.io/nim-cbor-serialization/).

## Contributing

Contributions are welcome - please make sure to add test coverage for features and fixes!

`json_serialization` follows the [Status Nim Style Guide](https://status-im.github.io/nim-style-guide/).

## License

Licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. These files may not be copied, modified, or distributed except according to those terms.
