# (De)Serialization Extensions

### Cbor specific

- `isFieldExpected*(T: type): bool`. Overload to return whether the type is an optional obj field. Used for deserializing.
- `shouldWriteObjectField[T](field: T): bool`. Overload to return whether the obj field should be written based on the field-value. Used for serializing. If `true` the field will be omited when `omitOptionalFields` is `true` for the created flavor.
- `writeObjectField(...)` serializes an obj field name and value. Note: Only internal usages found.

### nim-serialization specific

- `writeValue`/`readValue` the main way to overload the (de)serialization for a value type of a given flavor(s).

- `useDefaultSerializationIn(T: untyped, Flavor: type)` generates `writeValue`/`readValue` for a specific type `T`. It only supports `object | ref object | ptr object` types. Relies on `writeRecordValue`/`readRecordValue`.
  - `writeRecordValue(w: var FormatWriter, value: object | tuple)`. Overload to write a specific object/tuple.
  - `readRecordValue(r: var FormatReader, value: var (object | tuple))`. Overload to read a specific object/tuple.

- `useCustomSerialization(Format: typed, field: untyped, body: untyped)` generates `readFieldIMPL` and `writeFieldIMPL` overloads for the format (flavor or default), `MyObjType` (or `MyObjType.myField`) and (de)serializer body. The difference with `writeValue`/`readValue` is it can be specific to an object field.
  - `writeFieldIMPL`. Overload serialize a flavor, object field and value. Otherwise `writeValue` is used.
  - `readFieldIMPL`. Overload to deserialize a flavor, object field and value. Otherwise `readValue` is used.
  - Note: this is used in `ssz_serialization`, but the usage can be replaced by overloading writeValue/readValue instead as the "field" provided is a `distinct MyType` and not an `objType.field`.

- `generateAutoSerializationAddon(FLAVOR: typed)`. Generates some functions to enable/disable (de)serialization for a flavor. The serialization library needs to check whether the value type is enabled/disable before (de)serializing it.
  - `setAutoSerialize(F: type FLAVOR, T: distinct type, val: bool)`. Enable/disable the flavor (de)serialization for type `T`.
  - `typeClassOrMemberAutoSerialize(F: type FLAVOR, TC: distinct type, TM: distinct type): bool`. Check whether a type or its parent type class have automatic serialization flag.
  - `typeAutoSerialize(F: type FLAVOR, TM: distinct type): bool`. Check if a type has automatic serialization flag.
