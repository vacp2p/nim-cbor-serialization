# Reference

<!-- toc -->

This page provides an overview of the `cbor_serialization` API - for details, see the
[API reference](./api/cbor_serialization.html).

## Parsing

### Common API

CBOR parsing uses the [common serialization API](https://github.com/status-im/nim-serialization?tab=readme-ov-file#common-api), supporting both object-based and dynamic CBOR data item:

```nim
{{#include ../examples/reference0.nim:Decode}}
```

### Standalone Reader

A reader can be created from any [faststreams](https://github.com/status-im/nim-faststreams)-compatible stream:

```nim
{{#include ../examples/reference0.nim:Reader}}
```

### Parser options

Parser options allow you to control the strictness and limits of the parser. Set them by passing to `Cbor.decode` or when initializing the reader:

```nim
let flags = defaultCborReaderFlags + {allowUnknownFields}

var conf = defaultCborReaderConf
conf.nestedDepthLimit = 0

let native = Cbor.decode(
  rawCbor, NimServer, flags = flags, conf = conf)
```

[Flavors](#flavors) can be used to override the defaults for some these options.

#### Flags

Flags control aspects of the parser that are not all part of the CBOR standard, but commonly found in the wild:

  - **allowUnknownFields [=off]**: Skip unknown fields instead of raising an error.
  - **requireAllFields [=off]**: Raise an error if any required field is missing.

#### Limits

Parser limits are passed to `decode`, similar to flags:

You can adjust these defaults to suit your needs:

  - **nestedDepthLimit [=512]**: Maximum nesting depth for objects and arrays (0 = unlimited).
  - **arrayElementsLimit [=0]**: Maximum number of array elements (0 = unlimited).
  - **objectMembersLimit [=0]**: Maximum number of key-value pairs in an object (0 = unlimited).
  - **stringLengthLimit [=0]**: Maximum string length in bytes (0 = unlimited).
  - **byteStringLengthLimit [=0]**: Maximum byte string length in bytes (0 = unlimited).
  - **bigNumBytesLimit [=64]**: Maximum number of BigNum bytes (0 = unlimited).

### Special types

  - **CborBytes**: Holds a CBOR value as a distinct `seq[byte]`.
  - **CborVoid**: Skips a valid CBOR value.
  - **CborNumber**: Holds a CBOR number.
    - Use `toInt(n: CborNumber, T: SomeInteger): Opt[T]` to convert it to an integer.
    - The `integer` field for negative numbers is set to `abs(value)-1` as per the CBOR spec. This allows to hold a negative `uint64.high` value.
  - **CborValueRef**: Holds any valid CBOR value, it uses `CborNumber` instead of `int`.

## Writing

### Common API

Similar to parsing, the [common serialization API](https://github.com/status-im/nim-serialization?tab=readme-ov-file#common-api) is used to produce CBOR data items.

```nim
{{#include ../examples/reference0.nim:Encode}}
```

### Standalone Writer

```nim
{{#include ../examples/reference0.nim:Writer}}
```

## Flavors

Flags and limits are runtime configurations, while a flavor is a compile-time mechanism to prevent conflicts between custom serializers for the same type. For example, a CBOR-RPC-based API might require that numbers are formatted as hex strings while the same type exposed through REST should use a number.

Flavors ensure the compiler selects the correct serializer for each subsystem. Use `useDefaultSerializationIn` to assign serializers of a flavor to a specific type.

```nim
# Parameters for `createCborFlavor`:

  FlavorName: untyped
  mimeTypeValue = "application/cbor"
  automaticObjectSerialization = false
  requireAllFields = true
  omitOptionalFields = true
  allowUnknownFields = true
  skipNullFields = false
```

```nim
type
  OptionalFields = object
    one: Opt[string]
    two: Option[int]

createCborFlavor OptCbor
OptionalFields.useDefaultSerializationIn OptCbor
```

- `automaticObjectSerialization`: By default, all object types are accepted by `cbor_serialization` - disable automatic object serialization to only serialize explicitly allowed types
- `omitOptionalFields`: Writer ignores fields with null values.
- `skipNullFields`: Reader ignores fields with null values.

## Custom parsers and writers

Parsing and writing can be customized by providing overloads for the `readValue` and `writeValue` functions. Overrides are commonly used with a [flavor](#flavors) that prevents automatic object serialization, to avoid that some objects use the default serialization, should an import be forgotten.

```nim
# Custom serializers for MyType should match the following signatures
proc readValue*(r: var CborReader, v: var MyType) {.raises: [IOError, SerializationError].}
proc writeValue*(w: var CborWriter, v: MyType) {.raises: [IOError].}

# When flavors are used, add the flavor as well
proc readValue*(r: var CborReader[MyFlavor], v: var MyType) {.raises: [IOError, SerializationError].}
proc writeValue*(w: var CborWriter[MyFlavor], v: MyType) {.raises: [IOError].}
```

### Objects

Decode objects using the `parseObject` template. To parse values, use helper functions or `readValue`. The `readObject` and `readObjectFields` iterators are also useful for custom object parsers.

```nim
proc readValue*(r: var CborReader, table: var Table[string, int]) =
  parseObject(r, key):
    table[key] = r.parseInt(int)
```

### Sets and List-like Types

Sets and list/array-like structures can be parsed using the `parseArray` template, which supports both indexed and non-indexed forms.

Built-in `readValue` implementations exist for regular `seq` and `array`. For `set` or set-like types, you must provide your own implementation.

```nim
type
  HoldArray = object
    data: array[3, int]

  HoldSeq = object
    data: seq[int]

  WelderFlag = enum
    TIG
    MIG
    MMA

  Welder = object
    flags: set[WelderFlag]

proc readValue*(r: var CborReader, value: var HoldArray) =
  # parseArray with index, `i` can be any valid identifier
  r.parseArray(i):
    value.data[i] = r.parseInt(int)

proc readValue*(r: var CborReader, value: var HoldSeq) =
  # parseArray without index
  r.parseArray:
    let lastPos = value.data.len
    value.data.setLen(lastPos + 1)
    readValue(r, value.data[lastPos])

proc readValue*(r: var CborReader, value: var Welder) =
  # populating set also okay
  r.parseArray:
    value.flags.incl r.parseInt(int).WelderFlag
```

## Custom Iterators

Custom iterators provide access to sub-token elements:

```nim
customIntValueIt(r: var CborReader; body: untyped)
customNumberValueIt(r: var CborReader; body: untyped)
customStringValueIt(r: var CborReader; limit: untyped; body: untyped)
customStringValueIt(r: var CborReader; body: untyped)
```

## Convenience Iterators

```nim
readArray(r: var CborReader, ElemType: typedesc): ElemType
readObjectFields(r: var CborReader, KeyType: type): KeyType
readObjectFields(r: var CborReader): string
readObject(r: var CborReader, KeyType: type, ValueType: type): (KeyType, ValueType)
```

## CborReader Helper Procedures

See the [API reference](./api/cbor_serialization/parser.html)

## CborWriter Helper Procedures

See the [API reference](./api/cbor_serialization/writer.html)

## Enums

```nim
type
  Fruit = enum
    Apple = "Apple"
    Banana = "Banana"

  Drawer = enum
    One
    Two

  Number = enum
    Three = 3
    Four = 4

  Mixed = enum
    Six = 6
    Seven = "Seven"
```

`cbor_serialization` automatically detects the expected representation for each enum based on its declaration.
- `Fruit` expects string literals.
- `Drawer` and `Number` expect numeric literals.
- `Mixed` (with both string and numeric values) is disallowed by default.
If the CBOR value does not match the expected style, an exception is raised.
You can configure individual enum types:

```nim
configureCborDeserialization(
    T: type[enum], allowNumericRepr: static[bool] = false,
    stringNormalizer: static[proc(s: string): string] = strictNormalize)

# Example:
Mixed.configureCborDeserialization(allowNumericRepr = true) # Only at top level
```

You can also configure enum encoding at the flavor or type level:

```nim
type
  EnumRepresentation* = enum
    EnumAsString
    EnumAsNumber
    EnumAsStringifiedNumber

# Examples:

# Flavor level
Cbor.flavorEnumRep(EnumAsString)   # Default flavor, can be called from non-top level
Flavor.flavorEnumRep(EnumAsNumber) # Custom flavor, can be called from non-top level

# Individual enum type, regardless of flavor
Fruit.configureCborSerialization(EnumAsNumber) # Only at top level

# Individual enum type for a specific flavor
MyCbor.flavorEnumRep(Drawer, EnumAsString) # Only at top level
```
