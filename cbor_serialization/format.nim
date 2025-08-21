# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import serialization/[formats, object_serialization], ./types

export formats

template generateCborAutoSerializationAddon*(FLAVOR: typed) {.dirty.} =
  generateAutoSerializationAddon(FLAVOR)

  template automaticPrimitivesSerialization*(F: type FLAVOR, enable: static[bool]) =
    ## Set all supported primitives automatic serialization flag.
    static:
      F.setAutoSerialize(string, enable)
      F.setAutoSerialize(seq[char], enable)
      F.setAutoSerialize(seq[byte], enable)
      F.setAutoSerialize(bool, enable)
      F.setAutoSerialize(ref, enable)
      F.setAutoSerialize(ptr, enable)
      F.setAutoSerialize(enum, enable)
      F.setAutoSerialize(SomeInteger, enable)
      F.setAutoSerialize(SomeFloat, enable)
      F.setAutoSerialize(seq, enable)
      F.setAutoSerialize(array, enable)
      F.setAutoSerialize(cstring, enable)
      F.setAutoSerialize(openArray[char], enable)
      F.setAutoSerialize(openArray, enable)
      F.setAutoSerialize(range, enable)
      F.setAutoSerialize(distinct, enable)

  template automaticBuiltinSerialization*(F: type FLAVOR, enable: static[bool]) =
    ## Enable or disable all builtin serialization.
    automaticPrimitivesSerialization(F, enable)
    static:
      F.setAutoSerialize(CborNumber, enable)
      F.setAutoSerialize(CborTag, enable)
      F.setAutoSerialize(CborVoid, enable)
      F.setAutoSerialize(CborValueRef, enable)
      F.setAutoSerialize(CborSimpleValue, enable)
      F.setAutoSerialize(CborRaw, enable)
      F.setAutoSerialize(object, enable)
      F.setAutoSerialize(tuple, enable)

serializationFormat Cbor, mimeType = "application/cbor"

template supports*(_: type Cbor, T: type): bool =
  # The Cbor format should support every type
  true

type EnumRepresentation* = enum
  EnumAsString
  EnumAsNumber
  EnumAsStringifiedNumber

template flavorUsesAutomaticObjectSerialization*(T: type DefaultFlavor): bool =
  true

template flavorOmitsOptionalFields*(T: type DefaultFlavor): bool =
  true

template flavorRequiresAllFields*(T: type DefaultFlavor): bool =
  false

template flavorAllowsUnknownFields*(T: type DefaultFlavor): bool =
  false

template flavorSkipNullFields*(T: type DefaultFlavor): bool =
  false

var DefaultFlavorEnumRep {.compileTime.} = EnumAsString
template flavorEnumRep*(T: type DefaultFlavor): EnumRepresentation =
  DefaultFlavorEnumRep

template flavorEnumRep*(T: type DefaultFlavor, rep: static[EnumRepresentation]) =
  static:
    DefaultFlavorEnumRep = rep

# If user choose to use `Cbor` instead of `DefaultFlavor`, it still goes to `DefaultFlavor`
template flavorEnumRep*(T: type Cbor, rep: static[EnumRepresentation]) =
  static:
    DefaultFlavorEnumRep = rep

when declared(macrocache.hasKey): # Nim 1.6 have no macrocache.hasKey
  # Keep backward compatibility behavior, DefaultFlavor always enable all built in serialization.
  generateCborAutoSerializationAddon(DefaultFlavor)
  DefaultFlavor.automaticBuiltinSerialization(true)

# We create overloads of these traits to force the mixin treatment of the symbols
type DummyFlavor* = object
template flavorUsesAutomaticObjectSerialization*(T: type DummyFlavor): bool =
  true

template flavorOmitsOptionalFields*(T: type DummyFlavor): bool =
  false

template flavorRequiresAllFields*(T: type DummyFlavor): bool =
  false

template flavorAllowsUnknownFields*(T: type DummyFlavor): bool =
  false

template flavorSkipNullFields*(T: type DummyFlavor): bool =
  false

when declared(macrocache.hasKey): # Nim 1.6 have no macrocache.hasKey
  generateCborAutoSerializationAddon(DummyFlavor)
  DummyFlavor.automaticBuiltinSerialization(false)

template createCborFlavor*(
    FlavorName: untyped,
    mimeTypeValue = "application/cbor",
    automaticObjectSerialization = false,
    requireAllFields = true,
    omitOptionalFields = true,
    allowUnknownFields = true,
    skipNullFields = false,
    automaticPrimitivesSerialization = true,
) {.dirty.} =
  when declared(SerializationFormat): # Earlier versions lack mimeTypeValue
    createFlavor(Cbor, FlavorName, mimeTypeValue)
  else:
    type FlavorName* = object

    template Reader*(T: type FlavorName): type =
      Reader(Cbor, FlavorName)

    template Writer*(T: type FlavorName): type =
      Writer(Cbor, FlavorName)

    template PreferredOutputType*(T: type FlavorName): type =
      string

    template mimeType*(T: type FlavorName): string =
      mimeTypeValue

  template flavorUsesAutomaticObjectSerialization*(T: type FlavorName): bool =
    automaticObjectSerialization

  template flavorOmitsOptionalFields*(T: type FlavorName): bool =
    omitOptionalFields

  template flavorRequiresAllFields*(T: type FlavorName): bool =
    requireAllFields

  template flavorAllowsUnknownFields*(T: type FlavorName): bool =
    allowUnknownFields

  template flavorSkipNullFields*(T: type FlavorName): bool =
    skipNullFields

  var `FlavorName EnumRep` {.compileTime.} = EnumAsString
  template flavorEnumRep*(T: type FlavorName): EnumRepresentation =
    `FlavorName EnumRep`

  template flavorEnumRep*(T: type FlavorName, rep: static[EnumRepresentation]) =
    static:
      `FlavorName EnumRep` = rep

  when declared(macrocache.hasKey): # Nim 1.6 have no macrocache.hasKey
    generateCborAutoSerializationAddon(FlavorName)

    # Set default to true for backward compatibility
    # but user can call it again later with different value.
    # Or fine tuning use `Flavor.automaticSerialization(type, true/false)`
    FlavorName.automaticBuiltinSerialization(automaticPrimitivesSerialization)

{.pop.}
