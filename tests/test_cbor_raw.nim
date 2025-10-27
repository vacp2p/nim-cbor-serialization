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

suite "Test CborBytes":
  dualTest "decode spec vectors":
    let cborData = specData()
    check cborData.len > 0
    for val in cborData:
      let cbor = Cbor.decode(val.unhex, CborBytes)
      check cbor.toBytes().toHex() == val

  dualTest "encode spec vectors":
    let cborData = specData()
    check cborData.len > 0
    for val in cborData:
      let raw = val.unhex.CborBytes
      check Cbor.encode(raw).toHex() == val

  dualTest "decode string":
    let val = "0x6161".unhex
    check Cbor.decode(val, CborBytes) == val

  dualTest "encode string":
    let val = "0x6161".unhex
    check Cbor.encode(val.CborBytes) == val

  dualTest "Object nestedDepthLimit":
    let cbor = Cbor.encode((x: (y: (z: "a"))))
    check:
      Cbor.decode(cbor, CborBytes) == cbor
      Cbor.decode(cbor, CborBytes, conf = CborReaderConf(nestedDepthLimit: 3)) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, CborBytes, conf = CborReaderConf(nestedDepthLimit: 2))

  dualTest "Array nestedDepthLimit":
    let cbor = Cbor.encode(@[@[@["a", "b"], @["c", "d"]], @[@["e", "f"]]])
    check:
      Cbor.decode(cbor, CborBytes) == cbor
      Cbor.decode(cbor, CborBytes, conf = CborReaderConf(nestedDepthLimit: 3)) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, CborBytes, conf = CborReaderConf(nestedDepthLimit: 2))

  dualTest "Tag nestedDepthLimit":
    type
      Tag1 = CborTag[Tag2]
      Tag2 = CborTag[Tag3]
      Tag3 = CborTag[string]

    let cbor =
      Cbor.encode(Tag1(tag: 123, val: Tag2(tag: 456, val: Tag3(tag: 789, val: "foo"))))
    check:
      Cbor.decode(cbor, CborBytes) == cbor
      Cbor.decode(cbor, CborBytes, conf = CborReaderConf(nestedDepthLimit: 3)) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, Tag1, conf = CborReaderConf(nestedDepthLimit: 2))

  dualTest "Array arrayElementsLimit":
    let cbor = Cbor.encode(@["a", "b", "c"])
    check:
      Cbor.decode(cbor, CborBytes) == cbor
      Cbor.decode(cbor, CborBytes, conf = CborReaderConf(arrayElementsLimit: 3)) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, CborBytes, conf = CborReaderConf(arrayElementsLimit: 2))

  dualTest "Object objectFieldsLimit":
    type MyObj = object
      a, b, c: string
    let cbor = Cbor.encode(MyObj(a: "a", b: "b", c: "c"))
    check:
      Cbor.decode(cbor, CborBytes) == cbor
      Cbor.decode(cbor, CborBytes, conf = CborReaderConf(objectFieldsLimit: 3)) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, CborBytes, conf = CborReaderConf(objectFieldsLimit: 2))

  dualTest "String stringLengthLimit":
    let cbor = Cbor.encode("abc")
    check:
      Cbor.decode(cbor, CborBytes) == cbor
      Cbor.decode(cbor, CborBytes, conf = CborReaderConf(stringLengthLimit: 3)) == cbor
    expect UnexpectedValueError:
      discard Cbor.decode(cbor, CborBytes, conf = CborReaderConf(stringLengthLimit: 2))

  dualTest "ByteString byteStringLengthLimit":
    let cbor = Cbor.encode(@[1.byte, 2, 3])
    check:
      Cbor.decode(cbor, CborBytes) == cbor
      Cbor.decode(cbor, CborBytes, conf = CborReaderConf(byteStringLengthLimit: 3)) ==
        cbor
    expect UnexpectedValueError:
      discard
        Cbor.decode(cbor, CborBytes, conf = CborReaderConf(byteStringLengthLimit: 2))
