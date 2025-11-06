# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  pkg/unittest2,
  pkg/stew/byteutils,
  ./utils,
  ../cbor_serialization/pkg/results,
  ../cbor_serialization/std/options,
  ../cbor_serialization

type
  ObjectWithOptionalFields = object
    a: Opt[int]
    b: Option[string]
    c: int

  OWOF = object
    a: Opt[int]
    b: Option[string]
    c: int

createCborFlavor YourCbor, omitOptionalFields = false
YourCbor.defaultSerialization Result
YourCbor.defaultSerialization Option

createCborFlavor MyCbor, omitOptionalFields = true
MyCbor.defaultSerialization Result
MyCbor.defaultSerialization Option

YourCbor.defaultSerialization ObjectWithOptionalFields
MyCbor.defaultSerialization ObjectWithOptionalFields

type
  FruitX = enum
    BananaX = "BaNaNa"
    AppleX = "ApplE"
    GrapeX = "VVV"

  Drawer = enum
    One
    Two

FruitX.configureCborSerialization(EnumAsString)
Cbor.configureCborSerialization(Drawer, EnumAsNumber)
MyCbor.configureCborSerialization(Drawer, EnumAsString)

proc writeValue*(w: var CborWriter, val: OWOF) {.gcsafe, raises: [IOError].} =
  w.writeObject:
    w.writeField("a", val.a)
    w.writeField("b", val.b)
    w.writeField("c", val.c)

#func toReader(input: seq[byte]): CborReader[DefaultFlavor] =
#  var stream = unsafeMemoryInput(input)
#  CborReader[DefaultFlavor].init(stream)

suite "Test writer":
  test "results option top level some YourCbor":
    var val = Opt.some(123)
    let cbor = YourCbor.encode(val)
    check cbor.hex == "0x187b"
    checkCbor cbor, 123

  test "results option top level none YourCbor":
    var val = Opt.none(int)
    let cbor = YourCbor.encode(val)
    check cbor.hex == "0xf6"
    checkCbor cbor, cborNull

  test "results option top level some MyCbor":
    var val = Opt.some(123)
    let cbor = MyCbor.encode(val)
    check cbor.hex == "0x187b"
    checkCbor cbor, 123

  test "results option top level none MyCbor":
    var val = Opt.none(int)
    let cbor = MyCbor.encode(val)
    check cbor.hex == "0xf6"
    checkCbor cbor, cborNull

  test "results option array some YourCbor":
    var val = [Opt.some(123), Opt.some(345)]
    let cbor = YourCbor.encode(val)
    check cbor.hex == "0x82187b190159"
    checkCbor cbor, [123, 345]

  test "results option array none YourCbor":
    var val = [Opt.some(123), Opt.none(int), Opt.some(777)]
    let cbor = YourCbor.encode(val)
    check cbor.hex == "0x83187bf6190309"
    checkCbor cbor, [Opt.some(123), Opt.none(int), Opt.some(777)]

  test "results option array some MyCbor":
    var val = [Opt.some(123), Opt.some(345)]
    let cbor = MyCbor.encode(val)
    check cbor.hex == "0x82187b190159"
    checkCbor cbor, [123, 345]

  test "results option array none MyCbor":
    var val = [Opt.some(123), Opt.none(int), Opt.some(777)]
    let cbor = MyCbor.encode(val)
    check cbor.hex == "0x83187bf6190309"
    checkCbor cbor, [Opt.some(123), Opt.none(int), Opt.some(777)]

  test "object with optional fields":
    let x = ObjectWithOptionalFields(a: Opt.some(123), b: some("nano"), c: 456)

    let y = ObjectWithOptionalFields(a: Opt.none(int), b: none(string), c: 999)

    let u = YourCbor.encode(x)
    check u.hex == "0xa36161187b6162646e616e6f61631901c8"
    checkCbor u, x

    let v = YourCbor.encode(y)
    check v.hex == "0xa36161f66162f661631903e7" # {"a": null, "b": null, "c": 999}
    checkCbor v, y

    let xx = MyCbor.encode(x)
    check xx.hex == "0xa36161187b6162646e616e6f61631901c8"
    checkCbor xx, x

    let yy = MyCbor.encode(y)
    check yy.hex == "0xa161631903e7" # {"c": 999}
    checkCbor yy, y

  test "writeField with object with optional fields":
    let x = OWOF(a: Opt.some(123), b: some("nano"), c: 456)

    let y = OWOF(a: Opt.none(int), b: none(string), c: 999)

    let xx = MyCbor.encode(x)
    check xx.hex == "0xbf6161187b6162646e616e6f61631901c8ff"
    checkCbor xx, x
    let yy = MyCbor.encode(y)
    check yy.hex == "0xbf61631903e7ff" # {"c": 999}
    checkCbor yy, y

    let uu = YourCbor.encode(x)
    check uu.hex == "0xbf6161187b6162646e616e6f61631901c8ff"
    checkCbor uu, x
    let vv = YourCbor.encode(y)
    check vv.hex == "0xbf6161f66162f661631903e7ff" # {"a": null, "b": null, "c": 999}
    checkCbor vv, y

  test "Enum value representation primitives":
    when DefaultFlavor.flavorEnumRep() == EnumAsString:
      check true
    elif DefaultFlavor.flavorEnumRep() == EnumAsNumber:
      check false
    elif DefaultFlavor.flavorEnumRep() == EnumAsStringifiedNumber:
      check false

    DefaultFlavor.flavorEnumRep(EnumAsNumber)
    when DefaultFlavor.flavorEnumRep() == EnumAsString:
      check false
    elif DefaultFlavor.flavorEnumRep() == EnumAsNumber:
      check true
    elif DefaultFlavor.flavorEnumRep() == EnumAsStringifiedNumber:
      check false

    DefaultFlavor.flavorEnumRep(EnumAsStringifiedNumber)
    when DefaultFlavor.flavorEnumRep() == EnumAsString:
      check false
    elif DefaultFlavor.flavorEnumRep() == EnumAsNumber:
      check false
    elif DefaultFlavor.flavorEnumRep() == EnumAsStringifiedNumber:
      check true

    DefaultFlavor.flavorEnumRep(EnumAsString)

  test "Enum value representation of DefaultFlavor":
    type ExoticFruits = enum
      DragonFruit
      SnakeFruit
      StarFruit

    DefaultFlavor.flavorEnumRep(EnumAsNumber)
    let u = Cbor.encode(DragonFruit)
    check u.hex == "0x00"
    checkCbor u, 0

    DefaultFlavor.flavorEnumRep(EnumAsString)
    let v = Cbor.encode(SnakeFruit)
    check v.hex == "0x6a536e616b654672756974"
    checkCbor v, SnakeFruit
    checkCbor v, "SnakeFruit"

    DefaultFlavor.flavorEnumRep(EnumAsStringifiedNumber)
    let w = Cbor.encode(StarFruit)
    check w.hex == "0x6132"
    checkCbor w, "2"

  test "EnumAsString of DefaultFlavor/Cbor":
    type
      Fruit = enum
        Banana = "BaNaNa"
        Apple = "ApplE"
        JackFruit = "VVV"

      ObjectWithEnumField = object
        fruit: Fruit

    Cbor.flavorEnumRep(EnumAsString)
    let u = Cbor.encode(Banana)
    check u.hex == "0x6642614e614e61"
    checkCbor u, Banana
    checkCbor u, "BaNaNa"

    let v = Cbor.encode(Apple)
    check v.hex == "0x654170706c45"
    checkCbor v, Apple
    checkCbor v, "ApplE"

    let w = Cbor.encode(JackFruit)
    check w.hex == "0x63565656"
    checkCbor w, JackFruit
    checkCbor w, "VVV"

    Cbor.flavorEnumRep(EnumAsStringifiedNumber)
    let x = Cbor.encode(JackFruit)
    check x.hex == "0x6132"
    checkCbor x, "2"

    Cbor.flavorEnumRep(EnumAsNumber)
    let z = Cbor.encode(Banana)
    check z.hex == "0x00"
    checkCbor z, 0

    Cbor.flavorEnumRep(EnumAsString)
    let obj = ObjectWithEnumField(fruit: Banana)
    let zz = Cbor.encode(obj)
    check zz.hex == "0xa16566727569746642614e614e61"
    checkCbor zz, obj

  test "Individual enum configuration":
    Cbor.flavorEnumRep(EnumAsNumber)
    # Although the flavor config is EnumAsNumber
    # FruitX is configured as EnumAsAstring
    let z = Cbor.encode(BananaX)
    check z.hex == "0x6642614e614e61"
    checkCbor z, "BaNaNa"

    # configuration: Cbor.configureCborSerialization(Drawer, EnumAsNumber)
    let u = Cbor.encode(Two)
    check u.hex == "0x01"
    checkCbor u, 1

    # configuration: MyCbor.configureCborSerialization(Drawer, EnumAsString)
    let v = MyCbor.encode(One)
    check v.hex == "0x634f6e65"
    checkCbor v, "One"

type
  DefinText = distinct string
  IndefText = distinct seq[string]
  DefinBytes = distinct seq[byte]
  IndefBytes = distinct seq[seq[byte]]
  StringLikeObj = object
    definText: DefinText
    indefText: IndefText
    definBytes: DefinBytes
    indefBytes: IndefBytes
    marker: int

createCborFlavor StringLikeCbor,
  automaticObjectSerialization = false, automaticPrimitivesSerialization = false

proc writeValue*(
    w: var StringLikeCbor.Writer, val: DefinText
) {.gcsafe, raises: [IOError].} =
  writeText(w, val.string.len):
    for x in val.string:
      w.writeChar(x)

proc writeValue*(
    w: var StringLikeCbor.Writer, val: IndefText
) {.gcsafe, raises: [IOError].} =
  writeText(w):
    for chunk in seq[string](val):
      writeText(w, chunk.len):
        for x in chunk:
          w.writeChar(x)

proc writeValue*(
    w: var StringLikeCbor.Writer, val: seq[string]
) {.gcsafe, raises: [IOError].} =
  writeText(w):
    for chunk in val:
      w.write(chunk)

proc writeValue*(
    w: var StringLikeCbor.Writer, val: seq[seq[string]]
) {.gcsafe, raises: [IOError].} =
  writeArray(w):
    for s in val:
      writeValue(w, s)

proc writeValue*(
    w: var StringLikeCbor.Writer, val: DefinBytes
) {.gcsafe, raises: [IOError].} =
  writeBytes(w, seq[byte](val).len):
    for x in seq[byte](val):
      w.writeByte(x)

proc writeValue*(
    w: var StringLikeCbor.Writer, val: IndefBytes
) {.gcsafe, raises: [IOError].} =
  writeBytes(w):
    for chunk in seq[seq[byte]](val):
      writeBytes(w, chunk.len):
        for x in chunk:
          w.writeByte(x)

proc writeValue*(
    w: var StringLikeCbor.Writer, val: seq[seq[byte]]
) {.gcsafe, raises: [IOError].} =
  writeBytes(w):
    for chunk in val:
      w.write(chunk)

proc writeValue*(
    w: var StringLikeCbor.Writer, val: seq[seq[seq[byte]]]
) {.gcsafe, raises: [IOError].} =
  writeArray(w):
    for s in val:
      writeValue(w, s)

proc writevalue*(w: var StringLikeCbor.Writer, val: int) =
  write(w, val)

proc writevalue*(w: var StringLikeCbor.Writer, val: StringLikeObj) =
  writeRecordValue(w, val)

func toWriter(output: var OutputStream): CborWriter[DefaultFlavor] =
  output = memoryOutput()
  CborWriter[DefaultFlavor].init(output)

suite "Test write text":
  test "definite":
    let cbor = StringLikeCbor.encode("abc".DefinText)
    check cbor.hex == "0x63616263"
    checkCbor cbor, "abc"

  test "indefinite 1 chunk":
    let cbor = StringLikeCbor.encode(@["abc"].IndefText)
    check cbor.hex == "0x7f63616263ff"
    checkCbor cbor, "abc"

  test "indefinite 3 chunks":
    let cbor = StringLikeCbor.encode(@["a", "bc", "def"].IndefText)
    check cbor.hex == "0x7f616162626363646566ff"
    checkCbor cbor, "abcdef"

  test "indefinite with writeValue":
    let cbor = StringLikeCbor.encode(@["a", "bc", "def"])
    check cbor.hex == "0x7f616162626363646566ff"
    checkCbor cbor, "abcdef"

  test "array of indefinite text":
    let cbor = StringLikeCbor.encode(@[@["a", "b"], @["c"]])
    check cbor.hex == "0x9f7f61616162ff7f6163ffff"
    checkCbor cbor, @["ab", "c"]

  test "indefinite nesting not allowed":
    var output: OutputStream
    var w = toWriter output
    writeText(w):
      expect AssertionDefect:
        writeText(w):
          w.writeChar('a')

  test "definite nesting not allowed":
    var output: OutputStream
    var w = toWriter output
    writeText(w, 1):
      expect AssertionDefect:
        writeText(w, 1):
          w.writeChar('a')

  test "indefinite in definite not allowed":
    var output: OutputStream
    var w = toWriter output
    writeText(w, 1):
      expect AssertionDefect:
        writeText(w):
          w.writeChar('a')

  test "bytes in indefinite text not allowed":
    var output: OutputStream
    var w = toWriter output
    writeText(w):
      expect AssertionDefect:
        writeBytes(w, 1):
          w.writeByte('a'.byte)

  test "bytes in definite text not allowed":
    var output: OutputStream
    var w = toWriter output
    writeText(w, 1):
      expect AssertionDefect:
        writeBytes(w, 1):
          w.writeByte('a'.byte)

  test "non-text in indefinite text not allowed":
    var output: OutputStream
    var w = toWriter output
    writeText(w):
      expect AssertionDefect:
        w.write(123)

  test "non-text in definite text not allowed":
    var output: OutputStream
    var w = toWriter output
    writeText(w, 1):
      expect AssertionDefect:
        w.write(123)

  test "text in definite text not allowed":
    var output: OutputStream
    var w = toWriter output
    writeText(w, 1):
      expect AssertionDefect:
        w.write("a")

suite "Test write byte-string":
  test "definite":
    let cbor = StringLikeCbor.encode("abc".toBytes.DefinBytes)
    check cbor.hex == "0x43616263"
    checkCbor cbor, "abc".toBytes

  test "indefinite 1 chunk":
    let cbor = StringLikeCbor.encode(@["abc".toBytes].IndefBytes)
    check cbor.hex == "0x5f43616263ff"
    checkCbor cbor, "abc".toBytes

  test "indefinite 3 chunks":
    let val = @["a".toBytes, "bc".toBytes, "def".toBytes]
    let cbor = StringLikeCbor.encode(val.IndefBytes)
    check cbor.hex == "0x5f416142626343646566ff"
    checkCbor cbor, "abcdef".toBytes

  test "indefinite with byte chunks":
    let val = @["a".toBytes, "bc".toBytes, "def".toBytes]
    let cbor = StringLikeCbor.encode(val)
    check cbor.hex == "0x5f416142626343646566ff"
    checkCbor cbor, "abcdef".toBytes

  test "array of indefinite byte-strings":
    let cbor = StringLikeCbor.encode(@[@["a".toBytes, "b".toBytes], @["c".toBytes]])
    check cbor.hex == "0x9f5f41614162ff5f4163ffff"
    checkCbor cbor, @["ab".toBytes, "c".toBytes]

  test "indefinite nesting not allowed":
    var output: OutputStream
    var w = toWriter output
    writeBytes(w):
      expect AssertionDefect:
        writeBytes(w):
          w.writeByte('a'.byte)

  test "definite nesting not allowed":
    var output: OutputStream
    var w = toWriter output
    writeBytes(w, 1):
      expect AssertionDefect:
        writeBytes(w, 1):
          w.writeByte('a'.byte)

  test "indefinite in definite not allowed":
    var output: OutputStream
    var w = toWriter output
    writeBytes(w, 1):
      expect AssertionDefect:
        writeBytes(w):
          w.writeByte('a'.byte)

  test "text in indefinite bytes not allowed":
    var output: OutputStream
    var w = toWriter output
    writeBytes(w):
      expect AssertionDefect:
        writeText(w, 1):
          w.writeChar('a')

  test "text in definite bytes not allowed":
    var output: OutputStream
    var w = toWriter output
    writeBytes(w, 1):
      expect AssertionDefect:
        writeText(w, 1):
          w.writeChar('a')

  test "non-bytes in indefinite bytes not allowed":
    var output: OutputStream
    var w = toWriter output
    writeBytes(w):
      expect AssertionDefect:
        w.write(123)

  test "non-bytes in definite bytes not allowed":
    var output: OutputStream
    var w = toWriter output
    writeBytes(w, 1):
      expect AssertionDefect:
        w.write(123)

  test "bytes in definite bytes not allowed":
    var output: OutputStream
    var w = toWriter output
    writeBytes(w, 1):
      expect AssertionDefect:
        w.write("a".toBytes)

suite "Test write text/bytes object":
  test "write StringLikeObj":
    type ExpectedObj = object
      definText, indefText: string
      definBytes, indefBytes: seq[byte]
      marker: int

    let val = StringLikeObj(
      definText: "foo".DefinText,
      indefText: @["bar", "baz"].IndefText,
      definBytes: "quz".toBytes.DefinBytes,
      indefBytes: @["qux".toBytes, "quxx".toBytes].IndefBytes,
      marker: 123,
    )
    let cbor = StringLikeCbor.encode(val)
    #echo cbor.hex
    checkCbor cbor,
      ExpectedObj(
        definText: "foo",
        indefText: "barbaz",
        definBytes: "quz".toBytes,
        indefBytes: "quxquxx".toBytes,
        marker: 123,
      )
