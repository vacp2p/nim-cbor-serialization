import cbor_serialization

# ANCHOR: Decode
let rawCbor = Cbor.encode((name: "localhost", port: 42))
type
  NimServer = object
    name: string
    port: int

  MixedServer = object
    name: CborValueRef
    port: int

  RawServer = object
    name: CborBytes
    port: CborBytes

var conf = defaultCborReaderConf
conf.nestedDepthLimit = 0

# decode into native Nim
let native = Cbor.decode(rawCbor, NimServer)

# decode into mixed Nim + CborValueRef
let mixed = Cbor.decode(rawCbor, MixedServer)

# decode any value into nested cbor raw
let raw = Cbor.decode(rawCbor, RawServer)

# decode any valid CBOR, using the `cbor_serialization` node type
let value = Cbor.decode(rawCbor, CborValueRef)

# ANCHOR_END: Decode

# ANCHOR: Reader
var reader = CborReader[DefaultFlavor].init(memoryInput(rawCbor))
let native2 = reader.readValue(NimServer)

# Overwrite an existing instance
var reader2 = CborReader[DefaultFlavor].init(memoryInput(rawCbor))
var native3: NimServer
reader2.readValue(native3)
# ANCHOR_END: Reader

# ANCHOR: Encode
# Convert object to cbor raw
let blob = Cbor.encode(native)
# ANCHOR_END: Encode

# ANCHOR: Writer
var output = memoryOutput()
var writer = CborWriter[DefaultFlavor].init(output)
writer.writeValue(native)
echo Cbor.decode(output.getOutput(seq[byte]), NimServer)
# ANCHOR_END: Writer
