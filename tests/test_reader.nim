# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import faststreams, unittest2, serialization, ./utils, ../cbor_serialization/reader

createCborFlavor NullFields, skipNullFields = true

func toReader(input: seq[byte]): CborReader[DefaultFlavor] =
  var stream = memoryInput(input)
  CborReader[DefaultFlavor].init(stream)

func toReaderNullFields(input: seq[byte]): CborReader[NullFields] =
  var stream = memoryInput(input)
  CborReader[NullFields].init(stream)

#{
#  "string" : "hello world",
#  "number" : -123.456,
#  "int":    789,
#  "bool"  : true    ,
#  "null"  : null  ,
#  "array"  : [  true, 567.89  ,   "string in array"  , null, [ 123 ] ]
#}
const cbor1 =
  "0xA666737472696E676B68656C6C6F20776F726C64666E756D626572FBC05EDD2F1A9FBE7763696E7419031564626F6F6CF5646E756C6CF665617272617985F5FB4081BF1EB851EB856F737472696E6720696E206172726179F681187B"

#{
#  "string" : 25,
#  "number" : 123,
#  "int":    789,
#  "bool"  : 22    ,
#  "null"  : 0
#}
const cbor2 =
  "0xA566737472696E671819666E756D626572187B63696E7419031564626F6F6C16646E756C6C00"

#{
#    "one": [1,true,null],
#    "two": 123,
#    "three": "help",
#    "four": "012",
#    "five": "345",
#    "six": true,
#    "seven": 555,
#    "eight": "mTwo",
#    "nine": 77,
#    "ten": 88,
#    "eleven": 88.55,
#    "twelve": [true, false],
#    "thirteen": [3,4],
#    "fourteen": {
#      "one": "world",
#      "two": false
#    }
#}
const cbor3 =
  "0xAE636F6E658301F5F66374776F187B6574687265656468656C7064666F75726330313264666976656333343563736978F565736576656E19022B656569676874646D54776F646E696E65184D6374656E185866656C6576656EFB4056233333333333667477656C766582F5F468746869727465656E82030468666F75727465656EA2636F6E6565776F726C646374776FF4"

type
  MasterEnum = enum
    mOne
    mTwo
    mThree

  SecondObject = object
    one: string
    two: bool

  MasterReader = object
    one: CborValueRef
    two: int
    three: string
    four: seq[char]
    five: array[3, char]
    six: bool
    seven: ref int
    eight: MasterEnum
    nine: int32
    ten: int16
    eleven: float64
    twelve: seq[bool]
    thirteen: array[mTwo .. mThree, int]
    fourteen: SecondObject

  SpecialTypes = object
    `string`: CborVoid
    `number`: CborValueRef
    `int`: CborNumber
    `bool`: CborValueRef
    `null`: CborValueRef
    `array`: CborValueRef

createCborFlavor AllowUnknownOnCbor,
  automaticObjectSerialization = true, allowUnknownFields = true
createCborFlavor AllowUnknownOffCbor,
  automaticObjectSerialization = true, allowUnknownFields = false

suite "CborReader basic test":
  test "readArray iterator":
    var r = toReader "0x83F4F5F4".unhex
    var list: seq[bool]
    for x in r.readArray(bool):
      list.add x
    check list == @[false, true, false]

  test "readObjectFields iterator":
    var r = toReader cbor1.unhex
    var keys: seq[string]
    var val: CborValueRef
    for key in r.readObjectFields(string):
      keys.add key
      r.parseValue(val)
    check keys == @["string", "number", "int", "bool", "null", "array"]

  test "readObject iterator":
    var r = toReader cbor2.unhex
    var keys: seq[string]
    var vals: seq[uint64]
    for k, v in r.readObject(string, uint64):
      keys.add k
      vals.add v

    check:
      keys == @["string", "number", "int", "bool", "null"]
      vals == @[25'u64, 123, 789, 22, 0]

  test "readValue":
    var r = toReader cbor3.unhex
    var valOrig: MasterReader
    r.readValue(valOrig)
    # workaround for https://github.com/nim-lang/Nim/issues/24274
    let val = valOrig
    check:
      val.one == arrNode(@[numNode(1), boolNode(true), nullNode()])
      val.two == 123
      val.three == "help"
      val.four == "012"
      val.five == "345"
      val.six == true
      val.seven[] == 555
      val.eight == mTwo
      val.nine == 77
      val.ten == 88
      val.eleven == 88.55
      val.twelve == [true, false]
      val.thirteen == [3, 4]
      val.fourteen == SecondObject(one: "world", two: false)

  test "Special Types":
    var r = toReader cbor1.unhex
    var val: SpecialTypes
    r.readValue(val)

    check:
      val.`number`.kind == CborValueKind.Float
      val.`number`.floatVal == -123.456
      val.`int`.integer == 789
      val.`bool`.kind == CborValueKind.Bool
      val.`bool`.boolVal == true
      val.`null`.kind == CborValueKind.Null
      val.`array` ==
        arrNode(
          @[
            boolNode(true),
            floatNode(567.89),
            strNode("string in array"),
            nullNode(),
            arrNode(@[numNode(123)]),
          ]
        )

  proc execReadObjectFields(r: var CborReader): int =
    var val: CborValueRef
    for key in r.readObjectFields():
      r.parseValue(val)
      inc result

  test "readObjectFields of null fields":
    # {"something":null, "bool":true, "string":null}
    var r =
      toReaderNullFields("0xA369736F6D657468696E67F664626F6F6CF566737472696E67F6".unhex)
    check execReadObjectFields(r) == 1

    # {"something":null,"bool":true,"string":"moon"}
    var y =
      toReader("0xA369736F6D657468696E67F664626F6F6CF566737472696E67646D6F6F6E".unhex)
    check execReadObjectFields(y) == 3

    # {"something":null,"bool":true,"string":"moon"}
    var z = toReaderNullFields(
      "0xA369736F6D657468696E67F664626F6F6CF566737472696E67646D6F6F6E".unhex
    )
    check execReadObjectFields(z) == 2

  proc execReadObject(r: var CborReader): int =
    for k, v in r.readObject(string, int):
      inc result

  test "readObjectFields of null fields":
    # {"something":null, "bool":123, "string":null}
    var r = toReaderNullFields(
      "0xA369736F6D657468696E67F664626F6F6C187B66737472696E67F6".unhex
    )
    check execReadObject(r) == 1

    expect CborReaderError:
      # {"something":null,"bool":78,"string":345}
      var y =
        toReader("0xA369736F6D657468696E67F664626F6F6C184E66737472696E67190159".unhex)
      check execReadObject(y) == 3

    # {"something":null,"bool":999,"string":100}
    var z = toReaderNullFields(
      "0xA369736F6D657468696E67F664626F6F6C1903E766737472696E671864".unhex
    )
    check execReadObject(z) == 2

  test "readValue of array":
    # [false, true, false]
    var r = toReader "0x83F4F5F4".unhex
    check r.readValue(array[3, bool]) == [false, true, false]

  test "readValue of array error":
    # [false, true, false]
    var r = toReader "0x83F4F5F4".unhex
    expect CborReaderError:
      discard r.readValue(array[2, bool])

  test "readValue of object without fields":
    type NoFields = object

    block:
      var stream = memoryInput(cbor1.unhex)
      var r = CborReader[AllowUnknownOnCbor].init(stream)

      check:
        r.readValue(NoFields) == NoFields()

    block:
      var stream = memoryInput(cbor1.unhex)
      var r = CborReader[AllowUnknownOffCbor].init(stream)

      expect(CborReaderError):
        discard r.readValue(NoFields)
