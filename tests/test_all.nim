# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.warning[UnusedImport]: off.}

import
  test_spec, test_serialization, test_simple_value, test_cbor_flavor, test_parser,
  test_reader, test_writer, test_valueref, test_cbor_raw, test_std, test_overloads

template importBigints() =
  import bigints

when compiles(importBigints):
  import test_bigints
