# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  unittest2,
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
