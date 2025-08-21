# cbor-serialization
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

mode = ScriptMode.Verbose

packageName   = "cbor_serialization"
version       = "0.1.0"
author        = "Status Research & Development GmbH"
description   = "Flexible CBOR serialization not relying on run-time type information"
license       = "Apache License 2.0"
skipDirs      = @["tests", "fuzzer"]

requires "nim >= 2.2.0",
         "serialization",
         "stew >= 0.2.0",
         "results",
         "bigints"
