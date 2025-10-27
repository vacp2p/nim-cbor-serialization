# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2, strutils, ./utils, ../cbor_serialization

proc roundtrip*[T](flavor: type, val: T): T =
  flavor.decode(flavor.encode(val), T)

var registry: seq[string]

template register(s: string, body: untyped) =
  {.cast(gcsafe).}:
    registry.add s
  body

type FlatObj = object
  s: string

proc readValue(reader: var Cbor.Reader, value: var FlatObj) =
  register "c_rv_FlatObj":
    reader.read value

proc writeValue(writer: var Cbor.Writer, value: FlatObj) =
  register "c_wv_FlatObj":
    writer.write value

type NestedObj = object
  s: seq[FlatObj]

suite "Test Cbor":
  setup:
    registry.setLen 0

  test "roundtrip FlatObj":
    check Cbor.roundtrip(FlatObj(s: "foo")) == FlatObj(s: "foo")
    check registry == @["c_wv_FlatObj", "c_rv_FlatObj"]

  test "roundtrip NestedObj":
    let val = NestedObj(s: @[FlatObj(s: "foo")])
    check Cbor.roundtrip(val) == val
    check registry == @["c_wv_FlatObj", "c_rv_FlatObj"]

createCborFlavor GenericCbor,
  automaticObjectSerialization = false, automaticPrimitivesSerialization = false

proc readValue[T](reader: var GenericCbor.Reader, value: var T) =
  register "gc_rv_" & $T:
    reader.read value

proc writeValue[T](writer: var GenericCbor.Writer, value: T) =
  register "gc_wv_" & $T:
    writer.write value

suite "Test GenericCbor":
  setup:
    registry.setLen 0

  test "roundtrip FlatObj":
    check GenericCbor.roundtrip(FlatObj(s: "foo")) == FlatObj(s: "foo")
    check registry == @[
      "gc_wv_FlatObj", "gc_wv_string", "gc_rv_FlatObj", "gc_rv_string"
    ]

  test "roundtrip NestedObj":
    let val = NestedObj(s: @[FlatObj(s: "foo")])
    check GenericCbor.roundtrip(val) == val
    check registry ==
      @[
        "gc_wv_NestedObj", "gc_wv_seq[FlatObj]", "gc_wv_FlatObj", "gc_wv_string",
        "gc_rv_NestedObj", "gc_rv_seq[FlatObj]", "gc_rv_FlatObj", "gc_rv_string",
      ]

createCborFlavor AutoCbor,
  automaticObjectSerialization = true, automaticPrimitivesSerialization = true

suite "Test AutoCbor":
  test "roundtrip int":
    check AutoCbor.roundtrip(123) == 123

  test "roundtrip FlatObj":
    check AutoCbor.roundtrip(FlatObj(s: "foo")) == FlatObj(s: "foo")

createCborFlavor DisSeqCbor,
  automaticObjectSerialization = true, automaticPrimitivesSerialization = true

type DisSeqInt = distinct seq[int]
proc `==`(a, b: DisSeqInt): bool {.borrow.}

proc readValue(reader: var DisSeqCbor.Reader, value: var DisSeqInt) =
  register "ac_rv_DisSeqInt":
    reader.read(seq[int](value))

proc writeValue(writer: var DisSeqCbor.Writer, value: DisSeqInt) =
  register "ac_wv_DisSeqInt":
    writer.write(seq[int](value))

suite "Test DisSeqCbor":
  setup:
    registry.setLen 0

  test "roundtrip DisSeq":
    check DisSeqCbor.roundtrip(@[1, 2, 3].DisSeqInt) == @[1, 2, 3].DisSeqInt
    check registry == @["ac_wv_DisSeqInt", "ac_rv_DisSeqInt"]

createCborFlavor StringOnlyCbor,
  automaticObjectSerialization = false, automaticPrimitivesSerialization = false

StringOnlyCbor.defaultSerialization string

suite "Test StringOnlyCbor":
  test "roundtrip string":
    check StringOnlyCbor.roundtrip("foo") == "foo"

  test "other types":
    type OutType = StringOnlyCbor.PreferredOutputType()
    check(compiles(StringOnlyCbor.encode("foo")))
    check(compiles(StringOnlyCbor.decode(default(OutType), string)))
    check(compiles(StringOnlyCbor.encode(CborBytes(default(OutType)))))
    check(compiles(StringOnlyCbor.decode(default(OutType), CborBytes)))
    check(not compiles(StringOnlyCbor.encode(123)))
    check(not compiles(StringOnlyCbor.decode(default(OutType), int)))
    check(not compiles(StringOnlyCbor.encode(FlatObj())))
    check(not compiles(StringOnlyCbor.decode(default(OutType), FlatObj)))
    check(not compiles(StringOnlyCbor.encode(@[1, 2, 3].DisSeqInt)))
    check(not compiles(StringOnlyCbor.decode(default(OutType), DisSeqInt)))

createCborFlavor OverloadCbor,
  automaticObjectSerialization = true, automaticPrimitivesSerialization = true

proc readValue(reader: var OverloadCbor.Reader, value: var string) =
  register "oc_rv_string":
    reader.read(value)

proc writeValue(writer: var OverloadCbor.Writer, value: string) =
  register "oc_wv_string":
    writer.write(value)

proc readValue(reader: var OverloadCbor.Reader, value: var int) =
  register "oc_rv_int":
    reader.read(value)

proc writeValue(writer: var OverloadCbor.Writer, value: int) =
  register "oc_wv_int":
    writer.write(value)

proc readValue(reader: var OverloadCbor.Reader, value: var seq) =
  register "oc_rv_seq":
    reader.read(value)

proc writeValue(writer: var OverloadCbor.Writer, value: seq) =
  register "oc_wv_seq":
    writer.write(value)

suite "Test OverloadCbor":
  setup:
    registry.setLen 0

  test "roundtrip string":
    check OverloadCbor.roundtrip("foo") == "foo"
    check registry == @["oc_wv_string", "oc_rv_string"]

  test "roundtrip int":
    check OverloadCbor.roundtrip(123) == 123
    check registry == @["oc_wv_int", "oc_rv_int"]

  test "roundtrip seq[int]":
    check OverloadCbor.roundtrip(@[1]) == @[1]
    check registry == @["oc_wv_seq", "oc_wv_int", "oc_rv_seq", "oc_rv_int"]

createCborFlavor AllTypesCbor,
  automaticObjectSerialization = true, automaticPrimitivesSerialization = true

proc readValue(reader: var AllTypesCbor.Reader, value: var DisSeqInt) =
  reader.read(seq[int](value))

proc `==`(a, b: ref string): bool =
  if a.isNil or b.isNil:
    a.isNil == b.isNil
  else:
    a[] == b[]

suite "Test all types":
  test "roundtrip CborBytes":
    check AllTypesCbor.roundtrip(CborBytes("0xF6".unhex)) == CborBytes("0xF6".unhex)

  test "roundtrip string":
    check AllTypesCbor.roundtrip("def") == "def"

  test "roundtrip bool":
    check AllTypesCbor.roundtrip(true) == true

  test "roundtrip int":
    check AllTypesCbor.roundtrip(1) == 1

  test "roundtrip int8":
    check AllTypesCbor.roundtrip(1'i8) == 1

  test "roundtrip float":
    check AllTypesCbor.roundtrip(1.0) == 1.0

  test "roundtrip float32":
    check AllTypesCbor.roundtrip(1'f32) == 1'f32

  test "roundtrip float64":
    check AllTypesCbor.roundtrip(1'f64) == 1'f64

  test "roundtrip tuple":
    check AllTypesCbor.roundtrip(("foo", 123)) == ("foo", 123)

  test "roundtrip ref string":
    var s = new string
    s[] = "abc"
    check AllTypesCbor.roundtrip(s) == s

  test "roundtrip seq[char]":
    check AllTypesCbor.roundtrip(@['f', 'o', 'o']) == @['f', 'o', 'o']

  test "roundtrip array char":
    check AllTypesCbor.roundtrip(['b', 'a', 'r']) == ['b', 'a', 'r']

  test "roundtrip seq[byte]":
    check AllTypesCbor.roundtrip(@[1'u8, 2, 3]) == @[1'u8, 2, 3]

  test "roundtrip seq[int]":
    check AllTypesCbor.roundtrip(@[1, 2, 3]) == @[1, 2, 3]

  test "roundtrip array int":
    check AllTypesCbor.roundtrip([1, 2, 3]) == [1, 2, 3]

  test "roundtrip distinct seq[int]":
    check AllTypesCbor.roundtrip(DisSeqInt(@[10, 11, 12])) == DisSeqInt(@[10, 11, 12])

  test "roundtrip Simple":
    check AllTypesCbor.roundtrip(CborSimpleValue(1)) == CborSimpleValue(1)

  test "roundtrip Tag":
    let val = CborTag[string](tag: 123, val: "abc")
    check AllTypesCbor.roundtrip(val) == val

  test "roundtrip CborValueRef":
    check AllTypesCbor.roundtrip(numNode(1)) == numNode(1)

  test "roundtrip openArray[char]":
    let val = "abc"
    let encoded = AllTypesCbor.encode(toOpenArray(val, 0, val.len - 1))
    check AllTypesCbor.decode(encoded, string) == val

  test "roundtrip openArray[int]":
    let val = @[1, 2, 3]
    let encoded = AllTypesCbor.encode(toOpenArray(val, 0, val.len - 1))
    check AllTypesCbor.decode(encoded, seq[int]) == val

  test "roundtrip cstring":
    let val = "abc"
    let encoded = AllTypesCbor.encode(val.cstring)
    check AllTypesCbor.decode(encoded, string) == val

  test "roundtrip CborVoid":
    let val = "abc"
    let encoded = AllTypesCbor.encode(val)
    check AllTypesCbor.decode(encoded, CborVoid) == CborVoid()

  # XXX test range[0 .. 2]

createCborFlavor FlatObjRefCbor,
  automaticObjectSerialization = false, automaticPrimitivesSerialization = false

type FlatObjRef = ref FlatObj

FlatObjRefCbor.defaultSerialization(string)
FlatObjRefCbor.defaultSerialization(FlatObjRef)
# XXX this causes an ambiguous call error since the ref already generates the non-ref write/read
#FlatObjRefCbor.defaultSerialization(FlatObj)

suite "Test FlatObjRefCbor":
  test "roundtrip FlatObjRef":
    let val = FlatObjRefCbor.roundtrip(FlatObjRef(s: "abc"))
    check val[] == FlatObj(s: "abc")

createCborFlavor StringRefCbor,
  automaticObjectSerialization = false, automaticPrimitivesSerialization = false

StringRefCbor.defaultSerialization(ref string)

suite "Test StringRefCbor":
  test "roundtrip ref string":
    var s = new string
    s[] = "abc"
    let val = StringRefCbor.roundtrip(s)
    check val[] == "abc"

# backward compat tests

type OldObj = object
  s: string

createCborFlavor OldCbor,
  automaticObjectSerialization = true, automaticPrimitivesSerialization = true

proc readValue(reader: var CborReader, value: var OldObj) =
  register "oc_rv_OldObj":
    reader.read value

proc writeValue(writer: var CborWriter, value: OldObj) =
  register "oc_wv_OldObj":
    writer.write value

proc readValue(reader: var CborReader, value: var int) =
  register "oc_rv_int":
    reader.read value

proc writeValue(writer: var CborWriter, value: int) =
  register "oc_wv_int":
    writer.write value

suite "Test OldCbor":
  setup:
    registry.setLen 0

  test "roundtrip OldObj":
    check OldCbor.roundtrip(OldObj(s: "foo")) == OldObj(s: "foo")
    check registry == @["oc_wv_OldObj", "oc_rv_OldObj"]

  test "roundtrip OldObj default flavor":
    check Cbor.roundtrip(OldObj(s: "foo")) == OldObj(s: "foo")
    check registry == @["oc_wv_OldObj", "oc_rv_OldObj"]

  test "roundtrip int":
    check OldCbor.roundtrip(123) == 123
    check registry == @["oc_wv_int", "oc_rv_int"]

  test "roundtrip int default flavor":
    check Cbor.roundtrip(123) == 123
    check registry == @["oc_wv_int", "oc_rv_int"]

type OldObj2 = object
  s: string

createCborFlavor OldCbor2,
  automaticObjectSerialization = false, automaticPrimitivesSerialization = true

OldObj2.useDefaultSerializationIn OldCbor2

suite "Test OldCbor2":
  test "roundtrip OldObj2":
    check OldCbor2.roundtrip(OldObj2(s: "foo")) == OldObj2(s: "foo")

  test "roundtrip OldObj2 default flavor":
    check Cbor.roundtrip(OldObj2(s: "foo")) == OldObj2(s: "foo")

type OldObj3 = object
  s: string

createCborFlavor OldCbor3,
  automaticObjectSerialization = true, automaticPrimitivesSerialization = true

OldCbor3.useCustomSerialization(OldObj3.s):
  read:
    register "oc_rv_OldObj3":
      return reader.readValue(string)
  write:
    register "oc_wv_OldObj3":
      writer.writeValue value

suite "Test OldCbor3":
  setup:
    registry.setLen 0

  test "roundtrip OldObj3":
    check OldCbor3.roundtrip(OldObj3(s: "foo")) == OldObj3(s: "foo")
    check registry == @["oc_wv_OldObj3", "oc_rv_OldObj3"]

  test "roundtrip OldObj3 default flavor":
    check Cbor.roundtrip(OldObj3(s: "foo")) == OldObj3(s: "foo")
    check registry.len == 0
