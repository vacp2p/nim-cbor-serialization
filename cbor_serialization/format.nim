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

template isRef[T](x: typedesc[ref T]): bool =
  true

template isRef(x: typedesc): bool =
  false

template isPtr[T](x: typedesc[ptr T]): bool =
  true

template isPtr(x: typedesc): bool =
  false

template derefType[T](x: typedesc[ref T]): untyped =
  T

template derefType[T](x: typedesc[ptr T]): untyped =
  T

# XXX move to nim-serialization
template defaultReaderImpl(Flavor: type, T: untyped) =
  mixin Reader

  template readValue*[U: Reader(Flavor), W: T](r: var U, value: var W) =
    mixin read
    read(r, value)

template defaultReader*(Flavor: type, T: untyped) =
  defaultReaderImpl(Flavor, T)
  when isRef(T) or isPtr(T):
    type TT = derefType(T)
    defaultReaderImpl(Flavor, TT)

# XXX move to nim-serialization
template defaultWriterImpl(Flavor: type, T: untyped) =
  mixin Writer

  template writeValue*[U: Writer(Flavor), W: T](w: var U, value: W) =
    mixin write
    write(w, value)

template defaultWriter*(Flavor: type, T: untyped) =
  defaultWriterImpl(Flavor, T)
  when isRef(T) or isPtr(T):
    type TT = derefType(T)
    defaultWriterImpl(Flavor, TT)

template defaultSerialization*(Flavor: type, T: untyped) =
  defaultReader(Flavor, T)
  defaultWriter(Flavor, T)

template defaultBuiltinReader*(Flavor: type) =
  Flavor.defaultReader(CborNumber)
  Flavor.defaultReader(CborTag)
  Flavor.defaultReader(CborVoid)
  Flavor.defaultReader(CborValueRef)
  Flavor.defaultReader(CborSimpleValue)
  Flavor.defaultReader(CborBytes)

template defaultBuiltinWriter*(Flavor: type) =
  Flavor.defaultWriter(CborNumber)
  Flavor.defaultWriter(CborTag)
  Flavor.defaultWriter(CborVoid)
  Flavor.defaultWriter(CborValueRef)
  Flavor.defaultWriter(CborSimpleValue)
  Flavor.defaultWriter(CborBytes)

template defaultBuiltinSerialization*(Flavor: type) =
  defaultBuiltinReader(Flavor)
  defaultBuiltinWriter(Flavor)

template defaultPrimitiveWriter*(Flavor: type) =
  Flavor.defaultWriter(string)
  Flavor.defaultWriter(bool)
  Flavor.defaultWriter(ref)
  Flavor.defaultWriter(ptr)
  Flavor.defaultWriter(enum)
  Flavor.defaultWriter(SomeInteger)
  Flavor.defaultWriter(SomeFloat)
  Flavor.defaultWriter(seq)
  Flavor.defaultWriter(array)
  Flavor.defaultWriter(cstring)
  Flavor.defaultWriter(openArray)
  Flavor.defaultWriter(range)
  Flavor.defaultWriter(distinct)

template defaultPrimitiveReader*(Flavor: type) =
  Flavor.defaultReader(string)
  Flavor.defaultReader(bool)
  Flavor.defaultReader(ref)
  Flavor.defaultReader(ptr)
  Flavor.defaultReader(enum)
  Flavor.defaultReader(SomeInteger)
  Flavor.defaultReader(SomeFloat)
  Flavor.defaultReader(seq)
  Flavor.defaultReader(array)
  #Flavor.defaultReader(cstring)
  Flavor.defaultReader(openArray)
  Flavor.defaultReader(range)
  #Flavor.defaultReader(distinct)

template defaultPrimitiveSerialization*(Flavor: type) =
  defaultPrimitiveReader(Flavor)
  defaultPrimitiveWriter(Flavor)

template defaultObjectWriter*(Flavor: type) =
  Flavor.defaultWriter(object)
  Flavor.defaultWriter(tuple)

template defaultObjectReader*(Flavor: type) =
  Flavor.defaultReader(object)
  Flavor.defaultReader(tuple)

template defaultObjectSerialization*(Flavor: type) =
  defaultObjectReader(Flavor)
  defaultObjectWriter(Flavor)

template defaultReaders*(Flavor: type) =
  defaultPrimitiveReader(Flavor)
  defaultBuiltinReader(Flavor)
  defaultObjectReader(Flavor)

template defaultWriters*(Flavor: type) =
  defaultPrimitiveWriter(Flavor)
  defaultBuiltinWriter(Flavor)
  defaultObjectWriter(Flavor)

template defaultSerialization*(Flavor: type) =
  defaultReaders(Flavor)
  defaultWriters(Flavor)

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

template createCborFlavor*(
    FlavorName: untyped,
    mimeTypeValue = "application/cbor",
    automaticObjectSerialization = false,
    automaticPrimitivesSerialization = true,
    requireAllFields = true,
    omitOptionalFields = true,
    allowUnknownFields = true,
    skipNullFields = false,
) {.dirty.} =
  bind EnumRepresentation

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

  var `FlavorName EnumRep` {.compileTime.} = EnumRepresentation.EnumAsString
  template flavorEnumRep*(T: type FlavorName): EnumRepresentation =
    `FlavorName EnumRep`

  template flavorEnumRep*(T: type FlavorName, rep: static[EnumRepresentation]) =
    static:
      `FlavorName EnumRep` = rep

  when automaticPrimitivesSerialization:
    defaultPrimitiveSerialization(FlavorName)
  defaultBuiltinSerialization(FlavorName)
  when automaticObjectSerialization:
    defaultObjectSerialization(FlavorName)

{.pop.}
