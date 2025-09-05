# Streaming

`CborWriter` can be used to incrementally write CBOR data items.

Incremental processing is ideal for large data items or when you want to avoid building the entire CBOR structure in memory.

<!-- toc -->

## Writing

You can use `CborWriter` to write CBOR objects, arrays, and values step by step, directly to a file or any output stream.

The process is similar to when you override `writeValue` to provide custom serialization.

### Example: Writing a CBOR Array of Objects

Suppose you want to write a large array of objects to a file, one at a time:

```nim
{{#include ../examples/streamwrite0.nim}}
```

This produces the following output when the resulting CBOR blob is decoded:

```nim
@[(id: 0, name: "item0"), (id: 1, name: "item1")]
```

### Example: Writing Nested Structures

Objects and arrays can be nested arbitrarily.

Here is the same array of CBOR objects, nested in an envelope containing an additional `status` field.

Instead of manually placing `begin`/`end` pairs, we're using the convenience helpers `writeObject` and `writeArrayMember`:

```ni
{{#include ../examples/streamwrite1.nim:Nesting}}
```

This produces the following output when the resulting CBOR blob is decoded:

```nim
(status: "ok", data: @[(id: 0, name: "item0"), (id: 1, name: "item1")])
```
