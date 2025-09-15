import cbor_serialization, stew/[byteutils]

var output = memoryOutput()
var writer = CborWriter[DefaultFlavor].init(output)

# ANCHOR: Nesting
writer.writeObject:
  writer.writeMember("status", "ok")
  writer.writeName("data")
  writer.writeArray:
    for i in 0 ..< 2:
      writer.writeObject:
        writer.writeMember("id", i)
        writer.writeMember("name", "item" & $i)
# ANCHOR_END: Nesting

echo output.getOutput(seq[byte]).to0xHex()
