# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2, ../cbor_serialization/cddl/parser

const testSpecCases = [
  """
person = {
  age: int,
  name: tstr,
  employer: tstr,
}
  """
]

suite "Test CDDL parser (deprecated)":
  dualTest "parse valid test cases":
    for t in testSpecCases:
      try:
        discard parseCddl(t)
      except CborCddlError:
        checkpoint("FAILED: " & t)
        fail()
