# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[strutils, options],
  unittest2,
  results,
  stew/byteutils,
  serialization,
  ./utils,
  ../cbor_serialization/pkg/results,
  ../cbor_serialization/std/options,
  ../cbor_serialization

createCborFlavor StringyCbor

proc writeValue(w: var CborWriter[StringyCbor], value: seq[byte]) =
  writeValue(w, toHex(value))

proc writeValue*(
    w: var CborWriter[StringyCbor], val: SomeInteger
) {.raises: [IOError].} =
  writeValue(w, $val)

proc readValue*(r: var CborReader[StringyCbor], v: var SomeSignedInt) =
  try:
    v = type(v) parseBiggestInt readValue(r, string)
  except ValueError as err:
    raiseUnexpectedValue(r.parser, "A signed integer encoded as string " & err.msg)

proc readValue*(r: var CborReader[StringyCbor], v: var SomeUnsignedInt) =
  try:
    v = type(v) parseBiggestUInt readValue(r, string)
  except ValueError as err:
    raiseUnexpectedValue(r.parser, "An unsigned integer encoded as string " & err.msg)

type
  Container = object
    name: string
    x: int
    y: uint64
    list: seq[int64]

  OptionalFields = object
    one: Opt[string]
    two: Option[int]

  SpecialTypes = object
    one: CborVoid
    two: CborNumber
    three: CborNumber
    four: CborValueRef

  ListOnly = object
    list: seq[int64]

Container.useDefaultSerializationIn StringyCbor

createCborFlavor OptCbor
OptionalFields.useDefaultSerializationIn OptCbor

#{
#  "one": "this text will gone",
#  "two": -789,
#  "three": 999,
#  "four" : {
#    "apple": [1, true, "three"],
#    "banana": {
#      "chip": 123,
#      "z": null,
#      "v": false
#    }
#  }
#}
const cborText =
  "0xA4636F6E65737468697320746578742077696C6C20676F6E656374776F3903146574687265651903E764666F7572A2656170706C658301F56574687265656662616E616E61A36463686970187B617AF66176F4"

#{
#  "list": null
#}
const cborTextWithNullFields = "0xA1646C697374F6"

createCborFlavor NullyFields, skipNullFields = true, requireAllFields = false

Container.useDefaultSerializationIn NullyFields
ListOnly.useDefaultSerializationIn NullyFields

suite "Test CborFlavor":
  dualTest "basic test":
    let c = Container(name: "c", x: -10, y: 20, list: @[1'i64, 2, 25])
    let encoded = StringyCbor.encode(c)
    # {"name":"c","x":"-10","y":"20","list":["1","2","25"]}
    check encoded.hex ==
      "0xa4646e616d6561636178632d31306179623230646c6973748361316132623235"

    let decoded = StringyCbor.decode(encoded, Container)
    check decoded == Container(name: "c", x: -10, y: 20, list: @[1, 2, 25])

  dualTest "optional fields":
    let a = OptionalFields(one: Opt.some("hello"))
    let b = OptionalFields(two: some(567))
    let c = OptionalFields(one: Opt.some("burn"), two: some(333))

    let aa = OptCbor.encode(a)
    check aa.hex == "0xa1636f6e656568656c6c6f" # {"one":"hello"}
    checkCbor aa, a

    let bb = OptCbor.encode(b)
    check bb.hex == "0xa16374776f190237" # {"two":567}
    checkCbor bb, b

    let cc = OptCbor.encode(c)
    check cc.hex == "0xa2636f6e65646275726e6374776f19014d" # {"one":"burn","two":333}
    checkCbor cc, c

  dualTest "Write special types":
    let vv = Cbor.decode(cborText.unhex, SpecialTypes)
    let xx = Cbor.encode(vv)
    var ww = Cbor.decode(xx, SpecialTypes)
    check:
      ww == vv
      # {"two":-789,"three":999,"four":{"apple":[1,true,"three"],"banana":{"chip":123,"z":null,"v":false}}}
      xx.hex ==
        "0xA36374776F3903146574687265651903E764666F7572A2656170706C658301F56574687265656662616E616E61A36463686970187B617AF66176F4".toLowerAscii

  dualTest "object with null fields":
    expect CborReaderError:
      let x = Cbor.decode(cborTextWithNullFields.unhex, Container)
      discard x

    let x = NullyFields.decode(cborTextWithNullFields.unhex, Container)
    check x.list.len == 0

    # field should not processed at all
    let y = NullyFields.decode(cborTextWithNullFields.unhex, ListOnly)
    check y.list.len == 0

  dualTest "Enum value representation primitives":
    NullyFields.flavorEnumRep(EnumAsString)
    when NullyFields.flavorEnumRep() == EnumAsString:
      check true
    elif NullyFields.flavorEnumRep() == EnumAsNumber:
      check false
    elif NullyFields.flavorEnumRep() == EnumAsStringifiedNumber:
      check false

    NullyFields.flavorEnumRep(EnumAsNumber)
    when NullyFields.flavorEnumRep() == EnumAsString:
      check false
    elif NullyFields.flavorEnumRep() == EnumAsNumber:
      check true
    elif NullyFields.flavorEnumRep() == EnumAsStringifiedNumber:
      check false

    NullyFields.flavorEnumRep(EnumAsStringifiedNumber)
    when NullyFields.flavorEnumRep() == EnumAsString:
      check false
    elif NullyFields.flavorEnumRep() == EnumAsNumber:
      check false
    elif NullyFields.flavorEnumRep() == EnumAsStringifiedNumber:
      check true

  dualTest "Enum value representation of custom flavor":
    type ExoticFruits = enum
      DragonFruit
      SnakeFruit
      StarFruit

    NullyFields.flavorEnumRep(EnumAsNumber)
    let u = NullyFields.encode(DragonFruit)
    check u.hex == "0x00"
    checkCbor u, 0

    NullyFields.flavorEnumRep(EnumAsString)
    let v = NullyFields.encode(SnakeFruit)
    check v.hex == "0x6a536e616b654672756974"
    checkCbor v, "SnakeFruit"

    NullyFields.flavorEnumRep(EnumAsStringifiedNumber)
    let w = NullyFields.encode(StarFruit)
    check w.hex == "0x6132"
    checkCbor w, "2"

  dualTest "EnumAsString of custom flavor":
    type Fruit = enum
      Banana = "BaNaNa"
      Apple = "ApplE"
      JackFruit = "VVV"

    NullyFields.flavorEnumRep(EnumAsString)
    let u = NullyFields.encode(Banana)
    check u.hex == "0x6642614e614e61"
    checkCbor u, Banana
    checkCbor u, "BaNaNa"

    let v = NullyFields.encode(Apple)
    check v.hex == "0x654170706c45"
    checkCbor v, Apple
    checkCbor v, "ApplE"

    let w = NullyFields.encode(JackFruit)
    check w.hex == "0x63565656"
    checkCbor w, JackFruit
    checkCbor w, "VVV"

    NullyFields.flavorEnumRep(EnumAsStringifiedNumber)
    let x = NullyFields.encode(JackFruit)
    check x.hex == "0x6132"
    checkCbor x, "2"

    NullyFields.flavorEnumRep(EnumAsNumber)
    let z = NullyFields.encode(Banana)
    check z.hex == "0x00"
    checkCbor z, 0

  dualTest "custom writer that uses stream":
    let value = @[@[byte 0, 1], @[byte 2, 3]]
    let cbor = StringyCbor.encode(value)
    check cbor.hex == "0x8264303030316430323033"
    checkCbor cbor, ["0001", "0203"]
