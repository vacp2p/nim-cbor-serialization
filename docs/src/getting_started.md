# Getting started

<!-- toc -->

`cbor_serialization` is used to parse CBOR directly into Nim types and to encode them back as Cbor efficiently.

Let's start with a simple CBOR-RPC example based on [JSON-RPC](https://www.jsonrpc.org/specification#examples):

```text
rpc-message = {
  cborrpc: tstr .eq "2.0",
  method: tstr .eq "subtract",
  params: [ int, int ],
  id: int
}
```

## Imports and exports

Before we can use `cbor_serialization`, we have to import the library.

If you put your custom serialization code in a separate module, make sure to re-export `cbor_serialization`:

```nim
{{#include ../examples/getstarted0.nim:Import}}
```

A common way to organize serialization code is to use a separate module named either after the library (`mylibrary_cbor_serialization`) or the flavor (`myflavor_cbor_serialization`).

For types that mainly exist to interface with CBOR, custom serializers can also be placed together with the type definitions.

```admonish tip "Re-exports"
When importing a module that contains custom serializers, make sure to re-export it or you might end up with cryptic compiler errors or worse, the default serializers being used!
```

## Simple reader

Looking at the example, we'll define a Nim `object` to hold the request data, with matching field names and types:

```nim
{{#include ../examples/getstarted0.nim:Request}}
```

`Cbor.encode` can now turn our `Request` into a CBOR blob:
```nim
{{#include ../examples/getstarted0.nim:Encode}}
```

`Cbor.decode` can now turn our CBOR input back into a `Request`:
```nim
{{#include ../examples/getstarted0.nim:Decode}}
```

```admonish tip ""
Replace `decode`/`encode` with `loadFile`/`saveFile` to read and write a file instead!
```

## Handling errors

Of course, someone might give us some invalid data - `cbor_serialization` will raise an exception when that happens:

```nim
{{#include ../examples/getstarted0.nim:Errors}}
```

## Custom parsing

Happy we averted a crisis by adding the forgotten exception handler, we go back to the [JSON-RPC specification](https://www.jsonrpc.org/specification#request_object) and notice that strings are actually allowed in the `id` field - further, the only thing we have to do with `id` is to pass it back in the response - we don't really care about its contents.

We'll define a helper type to deal with this situation and attach some custom parsing code to it that checks the type. Using `CborRaw` as underlying storage is an easy way to pass around snippets of CBOR whose contents we don't need.

The custom code is added to `readValue`/`writeValue` procedures that take the stream and our custom type as arguments:

```nim
{{#include ../examples/getstarted1.nim:Custom}}
```

Usage example:

```nim
{{#include ../examples/getstarted1.nim:Request}}
```

## Flavors and strictness

While the defaults that `cbor_serialization` offers are sufficient to get started, implementing CBOR-based standards often requires more fine-grained control, such as what to do when a field is missing, unknown or has high-level requirements for parsing and output.

We use `createCborFlavor` to declare the new flavor passing to it the customization options that we're interested in:

```nim
{{#include ../examples/getstarted2.nim:Create}}
```

## Required and optional fields

In the CBOR-RPC example, both the `cborrpc` version tag and `method` are required while parameters and `id` can be omitted. Our flavor required all fields to be present except those explicitly optional - we use `Opt` from [results](https://github.com/arnetheduck/nim-results) to select the optional ones:

```nim
{{#include ../examples/getstarted2.nim:Request}}
```

## Automatic object conversion

The default `Cbor` flavor allows any `object` to be converted to CBOR. If you define a custom serializer and someone forgets to import it, the compiler might end up using the default instead resulting in a nasty runtime surprise.

`automaticObjectSerialization = false` forces a compiler error for any type that has not opted in to be serialized:

```nim
{{#include ../examples/getstarted2.nim:Auto}}
```

With all that work done, we can finally use our custom flavor to encode and decode the `Request`:

```nim
{{#include ../examples/getstarted2.nim:Encode}}
```

## More examples

Further examples of how to use `cbor_serialization` can be found in the `tests` folder.
