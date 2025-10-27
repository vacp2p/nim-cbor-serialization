import cbor_serialization, stew/[byteutils]

var output = memoryOutput()
var writer = Cbor.Writer.init(output)

# ANCHOR: Nesting
writer.writeObject:
  writer.writeField("status", "ok")
  writer.writeName("data")
  writer.writeArray:
    for i in 0 ..< 2:
      writer.writeObject:
        writer.writeField("id", i)
        writer.writeField("name", "item" & $i)
# ANCHOR_END: Nesting

echo output.getOutput(seq[byte]).to0xHex()
