import cbor_serialization, stew/[byteutils]

var output = memoryOutput()
var writer = Cbor.Writer.init(output)

writer.beginArray()

for i in 0 ..< 2:
  writer.beginObject()

  writer.writeField("id", i)
  writer.writeField("name", "item" & $i)

  writer.endObject()

writer.endArray()

echo output.getOutput(seq[byte]).to0xHex()
