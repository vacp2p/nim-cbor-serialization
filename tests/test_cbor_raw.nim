# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/json, unittest2, ./utils, ../cbor_serialization

proc specData(): seq[string] =
  let data = readFile("tests/test-vectors/appendix_a.json")
  let jsonDoc = parseJson(data)
  result = newSeq[string]()
  for record in jsonDoc:
    doAssert record["hex"].getStr().len > 0
    result.add record["hex"].getStr()
  doAssert result.len > 0

const cborFlags = defaultCborReaderFlags

suite "Test CborRaw":
  test "decode spec vectors":
    let cborData = specData()
    check cborData.len > 0
    for val in cborData:
      let cbor = Cbor.decode(val.unhex, CborRaw)
      check cbor.toBytes().toHex() == val

  test "encode spec vectors":
    let cborData = specData()
    check cborData.len > 0
    for val in cborData:
      let raw = val.unhex.CborRaw
      check Cbor.encode(raw).toHex() == val

  test "decode string":
    let val = "0x6161".unhex
    check Cbor.decode(val, CborRaw) == val

  test "encode string":
    let val = "0x6161".unhex
    check Cbor.encode(val.CborRaw) == val

  test "Object nestedDepthLimit":
    let cbor = Cbor.encode((x: (y: (z: "a"))))
    check:
      Cbor.decode(cbor, CborRaw) == cbor
      Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(nestedDepthLimit: 3)
      ) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(nestedDepthLimit: 2)
      )

  test "Array nestedDepthLimit":
    let cbor = Cbor.encode(@[@[@["a", "b"], @["c", "d"]], @[@["e", "f"]]])
    check:
      Cbor.decode(cbor, CborRaw) == cbor
      Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(nestedDepthLimit: 3)
      ) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(nestedDepthLimit: 2)
      )

  test "Tag nestedDepthLimit":
    type
      Tag1 = CborTag[Tag2]
      Tag2 = CborTag[Tag3]
      Tag3 = CborTag[string]

    let cbor =
      Cbor.encode(Tag1(tag: 123, val: Tag2(tag: 456, val: Tag3(tag: 789, val: "foo"))))
    check:
      Cbor.decode(cbor, CborRaw) == cbor
      Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(nestedDepthLimit: 3)
      ) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(
        cbor, Tag1, flags = cborFlags, conf = CborReaderConf(nestedDepthLimit: 2)
      )

  test "Array arrayElementsLimit":
    let cbor = Cbor.encode(@["a", "b", "c"])
    check:
      Cbor.decode(cbor, CborRaw) == cbor
      Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(arrayElementsLimit: 3)
      ) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(arrayElementsLimit: 2)
      )

  test "Object objectMembersLimit":
    let cbor = Cbor.encode((a: "a", b: "b", c: "c"))
    check:
      Cbor.decode(cbor, CborRaw) == cbor
      Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(objectMembersLimit: 3)
      ) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(objectMembersLimit: 2)
      )

  test "String stringLengthLimit":
    let cbor = Cbor.encode("abc")
    check:
      Cbor.decode(cbor, CborRaw) == cbor
      Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(stringLengthLimit: 3)
      ) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(
        cbor, CborRaw, flags = cborFlags, conf = CborReaderConf(stringLengthLimit: 2)
      )

  test "ByteString byteStringLengthLimit":
    let cbor = Cbor.encode(@[1.byte, 2, 3])
    check:
      Cbor.decode(cbor, CborRaw) == cbor
      Cbor.decode(
        cbor,
        CborRaw,
        flags = cborFlags,
        conf = CborReaderConf(byteStringLengthLimit: 3),
      ) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(
        cbor,
        CborRaw,
        flags = cborFlags,
        conf = CborReaderConf(byteStringLengthLimit: 2),
      )
