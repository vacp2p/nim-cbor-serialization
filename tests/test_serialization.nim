# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  strutils,
  unittest2,
  stew/byteutils,
  serialization/object_serialization,
  serialization/testing/generic_suite,
  ./utils,
  ../cbor_serialization,
  ../cbor_serialization/std/[options, sets, tables],
  ../cbor_serialization/pkg/results

type
  Foo = object
    i: int
    b {.dontSerialize.}: Bar
    s: string

  Bar = object
    sf: seq[Foo]
    z: ref Simple

  Invalid = object
    distance: Mile

  HasUnusualFieldNames = object # Using Nim reserved keyword
    `type`: string
    renamedField {.serializedFieldName("renamed").}: string

  MyKind = enum
    Apple
    Banana

  MyCaseObject = object
    name: string
    case kind: MyKind
    of Banana: banana: int
    of Apple: apple: string

  MyUseCaseObject = object
    field: MyCaseObject

  HasCborBytes = object
    name: string
    data: CborBytes
    id: int

  HasCborNode = object
    name: string
    data: CborValueRef
    id: int

  HasCstring = object
    notNilStr: cstring
    nilStr: cstring

  # Customised parser tests
  FancyInt = distinct int
  FancyUInt = distinct uint
  FancyText = distinct string

  HasFancyInt = object
    name: string
    data: FancyInt

  HasFancyUInt = object
    name: string
    data: FancyUInt

  #HasFancyText = object
  #  name: string
  #  data: FancyText
  TokenRegistry = tuple[entry: CborValueKind]

  HoldsResultOpt* = object
    o*: Opt[Simple]
    r*: ref Simple

  WithCustomFieldRule* = object
    str*: string
    intVal*: int

  OtherOptionTest* = object
    a*: Option[Meter]
    b*: Option[Meter]

  NestedOptionTest* = object
    c*: Option[OtherOptionTest]
    d*: Option[OtherOptionTest]

  SeqOptionTest* = object
    a*: seq[Option[Meter]]
    b*: Meter

  OtherOptionTest2* = object
    a*: Option[Meter]
    b*: Option[Meter]
    c*: Option[Meter]

proc readValue*(
  r: var CborReader[DefaultFlavor], value: var CaseObject
) {.gcsafe, raises: [SerializationError, IOError].}

template readValueImpl(r: var CborReader, value: var CaseObject) =
  var
    kindSpecified = false
    valueSpecified = false
    otherSpecified = false

  for fieldName in readObjectFields(r):
    case fieldName
    of "kind":
      value = CaseObject(kind: r.readValue(ObjectKind))
      kindSpecified = true
      case value.kind
      of A:
        discard
      of B:
        otherSpecified = true
    of "a":
      if kindSpecified:
        case value.kind
        of A:
          r.readValue(value.a)
        of B:
          raiseUnexpectedValue(
            r.parser, "The 'a' field is only allowed for 'kind' = 'A'"
          )
      else:
        raiseUnexpectedValue(
          r.parser, "The 'a' field must be specified after the 'kind' field"
        )
      valueSpecified = true
    of "other":
      if kindSpecified:
        case value.kind
        of A:
          r.readValue(value.other)
        of B:
          raiseUnexpectedValue(
            r.parser, "The 'other' field is only allowed for 'kind' = 'A'"
          )
      else:
        raiseUnexpectedValue(
          r.parser, "The 'other' field must be specified after the 'kind' field"
        )
      otherSpecified = true
    of "b":
      if kindSpecified:
        case value.kind
        of B:
          r.readValue(value.b)
        of A:
          raiseUnexpectedValue(
            r.parser, "The 'b' field is only allowed for 'kind' = 'B'"
          )
      else:
        raiseUnexpectedValue(
          r.parser, "The 'b' field must be specified after the 'kind' field"
        )
      valueSpecified = true
    else:
      raiseUnexpectedField(r.parser, fieldName, "CaseObject")

  if not (kindSpecified and valueSpecified and otherSpecified):
    raiseUnexpectedValue(
      r.parser,
      "The CaseObject value should have sub-fields named " &
        "'kind', and ('a' and 'other') or 'b' depending on 'kind'",
    )

{.push warning[ProveField]: off.} # https://github.com/nim-lang/Nim/issues/22060
proc readValue*(
    r: var CborReader[DefaultFlavor], value: var CaseObject
) {.raises: [SerializationError, IOError].} =
  readValueImpl(r, value)

{.pop.}

template readValueImpl(r: var CborReader, value: var MyCaseObject) =
  var
    nameSpecified = false
    kindSpecified = false
    valueSpecified = false

  for fieldName in readObjectFields(r):
    case fieldName
    of "name":
      r.readValue(value.name)
      nameSpecified = true
    of "kind":
      value = MyCaseObject(kind: r.readValue(MyKind), name: value.name)
      kindSpecified = true
    of "banana":
      if kindSpecified:
        case value.kind
        of Banana:
          r.readValue(value.banana)
        of Apple:
          raiseUnexpectedValue(
            r.parser, "The 'banana' field is only allowed for 'kind' = 'Banana'"
          )
      else:
        raiseUnexpectedValue(
          r.parser, "The 'banana' field must be specified after the 'kind' field"
        )
      valueSpecified = true
    of "apple":
      if kindSpecified:
        case value.kind
        of Apple:
          r.readValue(value.apple)
        of Banana:
          raiseUnexpectedValue(
            r.parser, "The 'apple' field is only allowed for 'kind' = 'Apple'"
          )
      else:
        raiseUnexpectedValue(
          r.parser, "The 'apple' field must be specified after the 'kind' field"
        )
      valueSpecified = true
    else:
      raiseUnexpectedField(r.parser, fieldName, "MyCaseObject")

  if not (nameSpecified and kindSpecified and valueSpecified):
    raiseUnexpectedValue(
      r.parser,
      "The MyCaseObject value should have sub-fields named " &
        "'name', 'kind', and 'banana' or 'apple' depending on 'kind'",
    )

{.push warning[ProveField]: off.} # https://github.com/nim-lang/Nim/issues/22060
proc readValue*(
    r: var CborReader[DefaultFlavor], value: var MyCaseObject
) {.raises: [SerializationError, IOError].} =
  readValueImpl(r, value)

{.pop.}

var customVisit: TokenRegistry

Cbor.useCustomSerialization(WithCustomFieldRule.intVal):
  read:
    try:
      parseInt reader.readValue(string)
    except ValueError:
      raiseUnexpectedValue(reader.parser, "string encoded integer expected")
  write:
    writer.writeValue $value

template registerVisit(reader: var CborReader, body: untyped): untyped =
  customVisit.entry = reader.parser.cborKind()
  body

# Customised parser referring to other parser
proc readValue(reader: var CborReader, value: var FancyInt) =
  try:
    reader.registerVisit:
      value = reader.readValue(int).FancyInt
  except ValueError:
    raiseUnexpectedValue(reader.parser, "string encoded integer expected")

# Customised numeric parser for integer and stringified integer
proc readValue(reader: var CborReader, value: var FancyUInt) =
  try:
    reader.registerVisit:
      var accu = 0u
      case reader.parser.cborKind()
      of CborValueKind.Unsigned, CborValueKind.Negative:
        var val: int64
        reader.readValue(val)
        if val < 0:
          val *= -1
        accu = val.uint
      of CborValueKind.String:
        accu = reader.parseString.parseUInt
      else:
        discard
      value = accu.FancyUInt
  except ValueError:
    raiseUnexpectedValue(reader.parser, "string encoded integer expected")

# Customised numeric parser for text, accepts embedded quote
proc readValue(reader: var CborReader, value: var FancyText) =
  try:
    reader.registerVisit:
      value = reader.parseString().FancyText
  except ValueError:
    raiseUnexpectedValue(reader.parser, "string encoded integer expected")

# TODO `borrowSerialization` still doesn't work
# properly when it's placed in another module:
Meter.borrowSerialization int

template reject(code) {.used.} =
  static:
    doAssert(not compiles(code))

func `==`(lhs, rhs: Meter): bool =
  int(lhs) == int(rhs)

func `==`(lhs, rhs: ref Simple): bool =
  if lhs.isNil:
    return rhs.isNil
  if rhs.isNil:
    return false
  lhs[] == rhs[]

executeReaderWriterTests Cbor

func newSimple(x: int, y: string, d: Meter): ref Simple =
  (ref Simple)(x: x, y: y, distance: d)

var invalid = Invalid(distance: Mile(100))
# The compiler cannot handle this check at the moment
# {.fatal.} seems fatal even in `compiles` context
when false:
  reject invalid.toCbor
else:
  discard invalid

type EnumTestX = enum
  x0
  x1
  x2

type EnumTestY = enum
  y1 = 1
  y3 = 3
  y4
  y6 = 6

EnumTestY.configureCborDeserialization(allowNumericRepr = true)

type EnumTestZ = enum
  z1 = "aaa"
  z2 = "bbb"
  z3 = "ccc"

type EnumTestN = enum
  n1 = "aaa"
  n2 = "bbb"
  n3 = "ccc"

EnumTestN.configureCborDeserialization(stringNormalizer = nimIdentNormalize)

type EnumTestO = enum
  o1
  o2
  o3

EnumTestO.configureCborDeserialization(
  allowNumericRepr = true, stringNormalizer = nimIdentNormalize
)

createCborFlavor MyCbor
MyCbor.defaultSerialization(Option)
MyCbor.defaultSerialization(Result)

createCborFlavor AutoCbor,
  automaticObjectSerialization = true,
  requireAllFields = true,
  allowUnknownFields = true

createCborFlavor RequireAllFieldsOffCbor,
  automaticObjectSerialization = true, requireAllFields = false

createCborFlavor AllowUnknownFieldsOffCbor,
  automaticObjectSerialization = true, allowUnknownFields = false

type
  HasMyCborDefaultBehavior = object
    x*: int
    y*: string

  HasMyCborOverride = object
    x*: int
    y*: string

MyCbor.defaultSerialization HasMyCborDefaultBehavior

proc readValue*(r: var CborReader[MyCbor], value: var HasMyCborOverride) =
  r.readRecordValue(value)

proc writeValue*(w: var CborWriter[MyCbor], value: HasMyCborOverride) =
  w.writeRecordValue(value)

suite "toCbor tests":
  test "encode primitives":
    check:
      1.toCbor.toHex == "01"
      "".toCbor.toHex == "60"
      "abc".toCbor.toHex == "63616263"

  test "enums":
    Cbor.flavorEnumRep(EnumAsString)
    Cbor.roundtripTest x0, "0x627830".unhex # "x0"
    Cbor.roundtripTest x1, "0x627831".unhex # "x1"
    Cbor.roundtripTest x2, "0x627832".unhex # "x2"
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(0), EnumTestX)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(1), EnumTestX)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(2), EnumTestX)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(3), EnumTestX)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("X0"), EnumTestX)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("X1"), EnumTestX)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("X2"), EnumTestX)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("x_0"), EnumTestX)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(""), EnumTestX)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("0"), EnumTestX)
    Cbor.roundtripTest y1, "0x627931".unhex # "y1"
    Cbor.roundtripTest y3, "0x627933".unhex # "y3"
    Cbor.roundtripTest y4, "0x627934".unhex # "y4"
    Cbor.roundtripTest y6, "0x627936".unhex # "y6"
    check:
      Cbor.decode(Cbor.encode(1), EnumTestY) == y1
      Cbor.decode(Cbor.encode(3), EnumTestY) == y3
      Cbor.decode(Cbor.encode(4), EnumTestY) == y4
      Cbor.decode(Cbor.encode(6), EnumTestY) == y6
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(0), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(2), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(5), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(7), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("Y1"), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("Y3"), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("Y4"), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("Y6"), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("y_1"), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(""), EnumTestY)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("1"), EnumTestY)
    Cbor.roundtripTest z1, "0x63616161".unhex # "aaa"
    Cbor.roundtripTest z2, "0x63626262".unhex # "bbb"
    Cbor.roundtripTest z3, "0x63636363".unhex # "ccc"
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(0), EnumTestZ)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("AAA"), EnumTestZ)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("BBB"), EnumTestZ)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("CCC"), EnumTestZ)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("z1"), EnumTestZ)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("a_a_a"), EnumTestZ)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(""), EnumTestZ)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("\ud83d\udc3c"), EnumTestZ)
    Cbor.roundtripTest n1, "0x63616161".unhex # "aaa"
    Cbor.roundtripTest n2, "0x63626262".unhex # "bbb"
    Cbor.roundtripTest n3, "0x63636363".unhex # "ccc"
    check:
      Cbor.decode(Cbor.encode("aAA"), EnumTestN) == n1
      Cbor.decode(Cbor.encode("bBB"), EnumTestN) == n2
      Cbor.decode(Cbor.encode("cCC"), EnumTestN) == n3
      Cbor.decode(Cbor.encode("a_a_a"), EnumTestN) == n1
      Cbor.decode(Cbor.encode("b_b_b"), EnumTestN) == n2
      Cbor.decode(Cbor.encode("c_c_c"), EnumTestN) == n3
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(0), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("AAA"), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("BBB"), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("CCC"), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("Aaa"), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("Bbb"), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("Ccc"), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("n1"), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("_aaa"), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(""), EnumTestN)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("\ud83d\udc3c"), EnumTestN)
    Cbor.roundtripTest o1, "0x626F31".unhex # "o1"
    Cbor.roundtripTest o2, "0x626F32".unhex # "o2"
    Cbor.roundtripTest o3, "0x626F33".unhex # "o3"
    check:
      Cbor.decode(Cbor.encode("o_1"), EnumTestO) == o1
      Cbor.decode(Cbor.encode("o_2"), EnumTestO) == o2
      Cbor.decode(Cbor.encode("o_3"), EnumTestO) == o3
      Cbor.decode(Cbor.encode(0), EnumTestO) == o1
      Cbor.decode(Cbor.encode(1), EnumTestO) == o2
      Cbor.decode(Cbor.encode(2), EnumTestO) == o3
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(3), EnumTestO)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("O1"), EnumTestO)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("O2"), EnumTestO)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("O3"), EnumTestO)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("_o1"), EnumTestO)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode(""), EnumTestO)
    expect UnexpectedValueError:
      discard Cbor.decode(Cbor.encode("\ud83d\udc3c"), EnumTestO)

  test "simple objects":
    var s = Simple(x: 10, y: "test", distance: Meter(20))
    # {"distance":20,"x":10,"y":"test"}
    check s.toCbor == "0xA36864697374616E63651461780A61796474657374".unhex
    checkCbor s.toCbor(), s

  test "handle missing fields":
    # {"distance": 20, "y": "test"}
    let decoded = Cbor.decode("0xA26864697374616E63651461796474657374".unhex, Simple)
    check:
      decoded.x == 0
      decoded.y == "test"
      decoded.distance.int == 20

  test "Custom flavor with explicit serialization":
    var s = Simple(x: 10, y: "test", distance: Meter(20))

    reject:
      discard MyCbor.encode(s)

    let hasDefaultBehavior = HasMyCborDefaultBehavior(x: 10, y: "test")
    let hasOverride = HasMyCborOverride(x: 10, y: "test")

    let cbor1 = MyCbor.encode(hasDefaultBehavior)
    let cbor2 = MyCbor.encode(hasOverride)

    reject:
      let decodedAsMyCbor = MyCbor.decode(cbor2, Simple)

    check:
      # {"x":10,"y":"test"}
      cbor1 == "0xA261780A61796474657374".unhex
      cbor2 == "0xA261780A61796474657374".unhex

      MyCbor.decode(cbor1, HasMyCborDefaultBehavior) == hasDefaultBehavior
      MyCbor.decode(cbor2, HasMyCborOverride) == hasOverride

  test "handle additional fields":
    # {"x": -20, "futureObject": {"a": -1, "b": [1, 2.0, 3.1], "c": null, "d": true}, "futureBool": false, "y": "y value"}
    let cbor =
      "0xA46178336C6675747572654F626A656374A461612061628301F94000FB4008CCCCCCCCCCCD6163F66164F56A667574757265426F6F6CF4617967792076616C7565".unhex
    let decoded = RequireAllFieldsOffCbor.decode(cbor, Simple)
    check:
      decoded.x == -20
      decoded.y == "y value"
      decoded.distance.int == 0
    expect UnexpectedFieldError:
      let shouldNotDecode = Cbor.decode(cbor, Simple)
      echo "This should not have decoded ", shouldNotDecode

  test "all fields are required and present":
    # {"x": 20, "distance": 10, "y": "y value"}
    let cbor = "0xA36178146864697374616E63650A617967792076616C7565".unhex
    let decoded = AutoCbor.decode(cbor, Simple)
    check:
      decoded.x == 20
      decoded.y == "y value"
      decoded.distance.int == 10

  test "all fields were required, but not all were provided":
    # {"x": -20, "distance": 10}
    let cbor = "0xA26178336864697374616E63650A".unhex
    expect IncompleteObjectError:
      let shouldNotDecode = AutoCbor.decode(cbor, Simple)
      echo "This should not have decoded ", shouldNotDecode

  test "all fields were required, but not all were provided (additional fields present instead)":
    # {"futureBool": false, "y": "y value", "futureObject": {"a": -1, "b": [1, 2.0, 3.1], "c": null, "d": true}, "distance": 10}
    let cbor =
      "0xA46A667574757265426F6F6CF4617967792076616C75656C6675747572654F626A656374A461612061628301F94000FB4008CCCCCCCCCCCD6163F66164F56864697374616E63650A".unhex
    expect IncompleteObjectError:
      let shouldNotDecode = AutoCbor.decode(cbor, Simple)
      echo "This should not have decoded ", shouldNotDecode

  test "all fields were required, but none were provided":
    # {}
    let cbor = "0xA0".unhex
    expect IncompleteObjectError:
      let shouldNotDecode = AutoCbor.decode(cbor, Simple)
      echo "This should not have decoded ", shouldNotDecode

  test "all fields are required and provided, and additional ones are present":
    # {"x": 20, "distance": 10, "futureBool": false, "y": "y value", "futureObject": {"a": -1, "b": [1, 2.0, 3.1], "c": null, "d": true}}
    let cbor =
      "0xA56178146864697374616E63650A6A667574757265426F6F6CF4617967792076616C75656C6675747572654F626A656374A461612061628301F94000FB4008CCCCCCCCCCCD6163F66164F5".unhex
    let decoded =
      try:
        AutoCbor.decode(cbor, Simple)
      except SerializationError as err:
        checkpoint "Unexpected deserialization failure: " & err.formatMsg("<input>")
        raise
    check:
      decoded.x == 20
      decoded.y == "y value"
      decoded.distance.int == 10
    expect UnexpectedFieldError:
      let shouldNotDecode = AllowUnknownFieldsOffCbor.decode(cbor, Simple)
      echo "This should not have decoded ", shouldNotDecode

  test "arrays are printed correctly":
    var x = HoldsArray(data: @[1, 2, 3, 4])
    # {"data": [1, 2, 3, 4]}
    check x.toCbor() == "0xA164646174618401020304".unhex
    checkCbor x.toCbor(), x

  test "max unsigned value":
    var uintVal = not BiggestUInt(0)
    let cborValue = Cbor.encode(uintVal)
    check:
      # 18446744073709551615
      cborValue == "0x1BFFFFFFFFFFFFFFFF".unhex
      Cbor.decode(cborValue, BiggestUInt) == uintVal

  test "max signed value":
    let intVal = BiggestInt.high
    let validCborValue = Cbor.encode(intVal)
    # 9223372036854775808
    let invalidCborValue = "0x1B8000000000000000".unhex
    check:
      # 9223372036854775807
      validCborValue == "0x1B7FFFFFFFFFFFFFFF".unhex
      Cbor.decode(validCborValue, BiggestInt) == intVal
    expect IntOverflowError:
      discard Cbor.decode(invalidCborValue, BiggestInt)

  test "min signed value":
    let intVal = BiggestInt.low
    let validCborValue = Cbor.encode(intVal)
    # -9223372036854775809
    let invalidCborValue = "0x3B8000000000000000".unhex
    check:
      # -9223372036854775808
      validCborValue == "0x3B7FFFFFFFFFFFFFFF".unhex
      Cbor.decode(validCborValue, BiggestInt) == intVal
    expect IntOverflowError:
      discard Cbor.decode(invalidCborValue, BiggestInt)

  test "Unusual field names":
    let r = HasUnusualFieldNames(`type`: "uint8", renamedField: "field")
    check:
      # {"type":"uint8", "renamed":"field"}
      r.toCbor == "0xA264747970656575696E74386772656E616D6564656669656C64".unhex
      r == Cbor.decode(r.toCbor(), HasUnusualFieldNames)

  test "Option types":
    check:
      2 == static(HoldsOption.totalSerializedFields)
      1 == static(HoldsOption.totalExpectedFields)

      2 == static(Foo.totalSerializedFields)
      2 == static(Foo.totalExpectedFields)

    let
      h1 = HoldsOption(o: some Simple(x: 1, y: "2", distance: Meter(3)))
      h2 = HoldsOption(r: newSimple(1, "2", Meter(3)))
      h3 = Cbor.decode(h2.toCbor(), HoldsOption)

    # {"r":null,"o":{"distance":3,"x":1,"y":"2"}}
    Cbor.roundtripTest h1, "0xA26172F6616FA36864697374616E63650361780161796132".unhex
    # {"r":{"distance":3,"x":1,"y":"2"}}
    Cbor.roundtripTest h2, "0xA16172A36864697374616E63650361780161796132".unhex
    check h3 == h2
    expect SerializationError:
      #{ "o":{"distance":3,"x":1,"y":"2"}}
      let h4 = AutoCbor.decode(
        "0xA1616FA36864697374616E63650361780161796132".unhex, HoldsOption
      )
      discard h4

  test "Nested option types":
    let
      h3 = OtherOptionTest()
      h4 = OtherOptionTest(a: some Meter(1))
      h5 = OtherOptionTest(b: some Meter(2))
      h6 = OtherOptionTest(a: some Meter(3), b: some Meter(4))

    Cbor.roundtripTest h3, "0xA0".unhex # {}
    Cbor.roundtripTest h4, "0xA1616101".unhex # {"a":1}
    Cbor.roundtripTest h5, "0xA1616202".unhex # {"b":2}
    Cbor.roundtripTest h6, "0xA2616103616204".unhex # {"a":3,"b":4}

    let
      arr = @[some h3, some h4, some h5, some h6, none(OtherOptionTest)]
      results =
        @[
          "0xA26163A06164A0".unhex, # {"c":{},"d":{}}
          "0xA26163A06164A1616101".unhex, # {"c":{},"d":{"a":1}}
          "0xA26163A06164A1616202".unhex, # {"c":{},"d":{"b":2}}
          "0xA26163A06164A2616103616204".unhex, # {"c":{},"d":{"a":3,"b":4}}
          "0xA16163A0".unhex, # {"c":{}}
          "0xA26163A16161016164A0".unhex, # {"c":{"a":1},"d":{}}
          "0xA26163A16161016164A1616101".unhex, # {"c":{"a":1},"d":{"a":1}}
          "0xA26163A16161016164A1616202".unhex, # {"c":{"a":1},"d":{"b":2}}
          "0xA26163A16161016164A2616103616204".unhex, # {"c":{"a":1},"d":{"a":3,"b":4}}
          "0xA16163A1616101".unhex, # {"c":{"a":1}}
          "0xA26163A16162026164A0".unhex, # {"c":{"b":2},"d":{}}
          "0xA26163A16162026164A1616101".unhex, # {"c":{"b":2},"d":{"a":1}}
          "0xA26163A16162026164A1616202".unhex, # {"c":{"b":2},"d":{"b":2}}
          "0xA26163A16162026164A2616103616204".unhex, # {"c":{"b":2},"d":{"a":3,"b":4}}
          "0xA16163A1616202".unhex, # {"c":{"b":2}}
          "0xA26163A26161036162046164A0".unhex, # {"c":{"a":3,"b":4},"d":{}}
          "0xA26163A26161036162046164A1616101".unhex, # {"c":{"a":3,"b":4},"d":{"a":1}}
          "0xA26163A26161036162046164A1616202".unhex, # {"c":{"a":3,"b":4},"d":{"b":2}}
          "0xA26163A26161036162046164A2616103616204".unhex,
            # {"c":{"a":3,"b":4},"d":{"a":3,"b":4}}
          "0xA16163A2616103616204".unhex, # {"c":{"a":3,"b":4}}
          "0xA16164A0".unhex, # {"d":{}}
          "0xA16164A1616101".unhex, # {"d":{"a":1}}
          "0xA16164A1616202".unhex, # {"d":{"b":2}}
          "0xA16164A2616103616204".unhex, # {"d":{"a":3,"b":4}}
          "0xA0".unhex, # {}
        ]
    var r = 0
    for a in arr:
      for b in arr:
        # lent iterator error
        let a = a
        let b = b
        Cbor.roundtripTest NestedOptionTest(c: a, d: b), results[r]
        r.inc

    Cbor.roundtripTest SeqOptionTest(a: @[some 5.Meter, none Meter], b: Meter(5)),
      "0xA261618205F6616205".unhex # {"a":[5,null],"b":5}
    Cbor.roundtripTest OtherOptionTest2(
      a: some 5.Meter, b: none Meter, c: some 10.Meter
    ), "0xA261610561630A".unhex # {"a":5,"c":10}

  test "Result Opt types":
    check:
      false == static(isFieldExpected Opt[Simple])
      2 == static(HoldsResultOpt.totalSerializedFields)
      1 == static(HoldsResultOpt.totalExpectedFields)

    let
      h1 = HoldsResultOpt(o: Opt[Simple].ok Simple(x: 1, y: "2", distance: Meter(3)))
      h2 = HoldsResultOpt(r: newSimple(1, "2", Meter(3)))

    Cbor.roundtripTest h1, "0xA2616FA36864697374616E636503617801617961326172F6".unhex
      # {"o":{"distance":3,"x":1,"y":"2"},"r":null}
    Cbor.roundtripTest h2, "0xA16172A36864697374616E63650361780161796132".unhex
      # {"r":{"distance":3,"x":1,"y":"2"}}

    # {"r":{"distance":3,"x":1,"y":"2"}}
    let h3 = AutoCbor.decode(
      "0xA16172A36864697374616E63650361780161796132".unhex, HoldsResultOpt
    )

    check h3 == h2

    expect SerializationError:
      # {"o":{"distance":3,"x":1,"y":"2"}}
      let h4 = AutoCbor.decode(
        "0xA1616FA36864697374616E63650361780161796132".unhex, HoldsResultOpt
      )
      discard h4

  test "Custom field serialization":
    let obj = WithCustomFieldRule(str: "test", intVal: 10)
    Cbor.roundtripTest obj, "0xA263737472647465737466696E7456616C623130".unhex
      # {"str":"test","intVal":"10"}

  test "Case object as field":
    let
      original =
        MyUseCaseObject(field: MyCaseObject(name: "hello", kind: Apple, apple: "world"))
      decoded = Cbor.decode(Cbor.encode(original), MyUseCaseObject)
    check:
      $original == $decoded

  test "stringLike":
    check:
      "abc" == Cbor.decode(Cbor.encode(['a', 'b', 'c']), string)
      "abc" == Cbor.decode(Cbor.encode(@['a', 'b', 'c']), string)
      ['a', 'b', 'c'] == Cbor.decode(Cbor.encode(@['a', 'b', 'c']), seq[char])
      ['a', 'b', 'c'] == Cbor.decode(Cbor.encode("abc"), seq[char])
      ['a', 'b', 'c'] == Cbor.decode(Cbor.encode(@['a', 'b', 'c']), array[3, char])

    expect CborReaderError:
      discard Cbor.decode(Cbor.encode(@['a', 'b']), array[3, char])

    expect CborReaderError:
      discard Cbor.decode(Cbor.encode(@['a', 'b']), array[1, char])

  proc testCborHolders(HasCborData: type) =
    # {"name": "Data 1", "data": [1, 2, 3, 4], "id": 101}
    let data1 = "0xA3646E616D6566446174612031646461746184010203046269641865".unhex
    # {"name": "Data 2", "data": "some string", "id": 1002}
    let data2 =
      "0xA3646E616D656644617461203264646174616B736F6D6520737472696E676269641903EA".unhex
    # {"name": "Data 3", "data": {"field1": 10, "field2": [1, 2, 3], "field3": "test"}, "id": 10003}
    let data3 =
      "0xA3646E616D65664461746120336464617461A3666669656C64310A666669656C643283010203666669656C64336474657374626964192713".unhex
    let
      d1 = Cbor.decode(data1, HasCborData)
      d2 = Cbor.decode(data2, HasCborData)
      d3 = Cbor.decode(data3, HasCborData)
    when HasCborData is HasCborBytes:
      check:
        d1.data == "0x8401020304".unhex # [1, 2, 3, 4]
        d2.data == "0x6B736F6D6520737472696E67".unhex # "some string"
        # {"field1": 10, "field2": [1, 2, 3], "field3": "test"}
        d3.data ==
          "0xA3666669656C64310A666669656C643283010203666669656C64336474657374".unhex
    else:
      check:
        d1.data == arrNode(@[numNode(1), numNode(2), numNode(3), numNode(4)])
        d2.data == strNode("some string")
        # {"field1": 10, "field2": [1, 2, 3], "field3": "test"}
        d3.data ==
          objNode(
            {
              "field1": numNode(10),
              "field2": arrNode(@[numNode(1), numNode(2), numNode(3)]),
              "field3": strNode("test"),
            }.toOrderedTable
          )
    check:
      d1.name == "Data 1"
      d1.id == 101
      d2.name == "Data 2"
      d2.id == 1002
      d3.name == "Data 3"
      d3.id == 10003
    let
      d1Encoded = Cbor.encode(d1)
      d2Encoded = Cbor.encode(d2)
      d3Encoded = Cbor.encode(d3)
    check:
      d1Encoded == data1
      d2Encoded == data2
      d3Encoded == data3

  test "Holders of CborBytes":
    testCborHolders HasCborBytes

  test "Holders of CborNode":
    testCborHolders HasCborNode

  test "A nil cstring":
    let
      obj1 = HasCstring(notNilStr: "foo", nilStr: nil)
      obj2 = HasCstring(notNilStr: "", nilStr: nil)
      str: cstring = "some value"

    check:
      # {"notNilStr":"foo","nilStr":null}
      Cbor.encode(obj1) == "0xA2696E6F744E696C53747263666F6F666E696C537472F6".unhex
      # {"notNilStr":"","nilStr":null}
      Cbor.encode(obj2) == "0xA2696E6F744E696C53747260666E696C537472F6".unhex
      Cbor.encode(str) == "0x6A736F6D652076616C7565".unhex # "some value"
      Cbor.encode(cstring nil) == "0xF6".unhex # null

    reject:
      # Decoding cstrings is not supported due to lack of
      # clarity regarding the memory allocation approach
      Cbor.decode("0xF6".unhex, cstring)

suite "Custom parser tests":
  test "Fall back to int parser":
    customVisit = TokenRegistry.default
    # {"name": "FancyInt", "data": -12345}
    let cbor = "0xA2646E616D656846616E6379496E746464617461393038".unhex
    let dData = Cbor.decode(cbor, HasFancyInt)

    check dData.name == "FancyInt"
    check dData.data.int == -12345
    check customVisit.entry == CborValueKind.Negative

  test "Uint parser on negative integer":
    customVisit = TokenRegistry.default

    # {"name": "FancyUInt", "data": -12345}
    let cbor = "0xA2646E616D656946616E637955496E746464617461393038".unhex
    let dData = Cbor.decode(cbor, HasFancyUInt)

    check dData.name == "FancyUInt"
    check dData.data.uint == 12345u # abs value
    check customVisit.entry == CborValueKind.Negative

  test "Uint parser on string integer":
    customVisit = TokenRegistry.default

    # {"name": "FancyUInt", "data": "12345"}
    let cbor = "0xA2646E616D656946616E637955496E746464617461653132333435".unhex
    let dData = Cbor.decode(cbor, HasFancyUInt)

    check dData.name == "FancyUInt"
    check dData.data.uint == 12345u
    check customVisit.entry == CborValueKind.String

suite "Parser limits":
  test "Object nestedDepthLimit":
    type
      Obj1 = object
        obj: Obj2

      Obj2 = object
        obj: Obj3

      Obj3 = object
        x: string

    let cbor = Cbor.encode(Obj1())
    check:
      Cbor.decode(cbor, Obj1) == Obj1()
      Cbor.decode(cbor, Obj1, conf = CborReaderConf(nestedDepthLimit: 3)) == Obj1()
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, Obj1, conf = CborReaderConf(nestedDepthLimit: 2))

  test "Array nestedDepthLimit":
    type Arr3 = seq[seq[seq[string]]]
    let val: Arr3 = @[@[@["a", "b"], @["c", "d"]], @[@["e", "f"]]]
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, Arr3) == val
      Cbor.decode(cbor, Arr3, conf = CborReaderConf(nestedDepthLimit: 3)) == val
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, Arr3, conf = CborReaderConf(nestedDepthLimit: 2))

  test "Array/Object mix nestedDepthLimit":
    type
      Obj1 = object
        obj: seq[Obj2]

      Obj2 = object
        x: string

    let val = Obj1(obj: @[Obj2(), Obj2(), Obj2(), Obj2(), Obj2()])
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, Obj1) == val
      Cbor.decode(cbor, Obj1, conf = CborReaderConf(nestedDepthLimit: 3)) == val
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, Obj1, conf = CborReaderConf(nestedDepthLimit: 2))

  test "Tag nestedDepthLimit":
    type
      Tag1 = CborTag[Tag2]
      Tag2 = CborTag[Tag3]
      Tag3 = CborTag[string]

    let val: Tag1 = Tag1(tag: 123, val: Tag2(tag: 456, val: Tag3(tag: 789, val: "foo")))
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, Tag1) == val
      Cbor.decode(cbor, Tag1, conf = CborReaderConf(nestedDepthLimit: 3)) == val
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, Tag1, conf = CborReaderConf(nestedDepthLimit: 2))

  test "Array arrayElementsLimit":
    let val = @["a", "b", "c"]
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, seq[string]) == val
      Cbor.decode(cbor, seq[string], conf = CborReaderConf(arrayElementsLimit: 3)) == val
    expect UnexpectedValueError:
      discard
        Cbor.decode(cbor, seq[string], conf = CborReaderConf(arrayElementsLimit: 2))

  test "Object objectFieldsLimit":
    type Obj1 = object
      a, b, c: string

    let cbor = Cbor.encode(Obj1())
    check:
      Cbor.decode(cbor, Obj1) == Obj1()
      Cbor.decode(cbor, Obj1, conf = CborReaderConf(objectFieldsLimit: 3)) == Obj1()
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, Obj1, conf = CborReaderConf(objectFieldsLimit: 2))

  test "String stringLengthLimit":
    let val = "abc"
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, string) == val
      Cbor.decode(cbor, string, conf = CborReaderConf(stringLengthLimit: 3)) == val
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, string, conf = CborReaderConf(stringLengthLimit: 2))

  test "ByteString byteStringLengthLimit":
    let val = @[1'u8, 2'u8, 3'u8]
    let cbor = Cbor.encode(val)
    check:
      Cbor.decode(cbor, seq[byte]) == val
      Cbor.decode(cbor, seq[byte], conf = CborReaderConf(byteStringLengthLimit: 3)) ==
        val
    expect UnexpectedValueError:
      discard
        Cbor.decode(cbor, seq[byte], conf = CborReaderConf(byteStringLengthLimit: 2))
