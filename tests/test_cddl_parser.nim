# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.push raises: [], gcsafe.}

import
  std/[os, strutils],
  unittest2,
  ../cbor_serialization,
  ../cbor_serialization/cddl/parser2

const testSpecCases = [
  """
person = {
  age: int,
  name: tstr,
  employer: tstr,
}
  """,
  """
pii = (
  age: int,
  name: tstr,
  employer: tstr,
)
  """,
  """
person = {
  pii
}
  """,
  """
person = {(
  age: int,
  name: tstr,
  employer: tstr,
)}
  """,
  """
person = {
  age: int,
  name: tstr,
  employer: tstr,
}

dog = {
  age: int,
  name: tstr,
  leash-length: float,
}
  """,
  """
person = {
  identity,
  employer: tstr,
}

dog = {
  identity,
  leash-length: float,
}

identity = (
  age: int,
  name: tstr,
)
  """,
  """
attire = "bow tie" / "necktie" / "Internet attire"
protocol = 6 / 17
  """,
  """
address = { delivery }

delivery = (
street: tstr, ? number: uint, city //
po-box: uint, city //
per-pickup: true )

city = (
name: tstr, zip-code: uint
)
  """,
  """
attire /= "swimwear"

delivery //= (
lat: float, long: float, drone-type: tstr
)
  """,
  """
device-address = byte
max-byte = 255
byte = 0..max-byte ; inclusive range
first-non-byte = 256
byte1 = 0...first-non-byte ; byte1 is equivalent to byte
  """,
  """
int-range = 0..10 ; only integers match
float-range = 0.0..10.0 ; only floats match
BAD-range1 = 0..10.0 ; NOT DEFINED
BAD-range2 = 0.0..10 ; NOT DEFINED
numeric-range = int-range / float-range
  """,
  """
terminal-color = &basecolors
basecolors = (
  black: 0,  red: 1,  green: 2,  yellow: 3,
  blue: 4,  magenta: 5,  cyan: 6,  white: 7,
)
extended-color = &(
  basecolors,
  orange: 8,  pink: 9,  purple: 10,  brown: 11,
)
  """,
  """
my_breakfast = #6.55799(breakfast)   ; cbor-any is too general!
breakfast = cereal / porridge
cereal = #6.998(tstr)
porridge = #6.999([liquid, solid])
liquid = milk / water
milk = 0
water = 1
solid = tstr
  """,
  """
; This is a comment
person = { g }

g = (
  "name": tstr,
  age: int,  ; "age" is a bareword
)
  """,
  """
apartment = {
  kitchen: size,
  * bedroom: size,
}
size = float ; in m2
  """,
  """
unlimited-people = [* person]
one-or-two-people = [1*2 person]
at-least-two-people = [2* person]
person = (
    name: tstr,
    age: uint,
)
  """,
  """
Geography = [
  city           : tstr,
  gpsCoordinates : GpsCoordinates,
]

GpsCoordinates = {
  longitude      : uint,            ; degrees, scaled by 10^7
  latitude       : uint,            ; degrees, scaled by 10^7
}
  """,
  """
located-samples = {
  sample-point: int,
  samples: [+ float],
}
  """,
  """
located-samples = {
  "sample-point" => int,
  "samples" => [+ float],
}
  """,
  """
located-samples = {
  sample-point: int,
  samples: [+ float],
  * equipment-type => equipment-tolerances,
}
equipment-type = [name: tstr, manufacturer: tstr]
equipment-tolerances = [+ [float, float]]
  """,
  """
PersonalData = {
  ? displayName: tstr,
  NameComponents,
  ? age: uint,
}

NameComponents = (
  ? firstName: tstr,
  ? familyName: tstr,
)
  """,
  """
PersonalData = {
  ? displayName: tstr,
  NameComponents,
  ? age: uint,
  * tstr => any
}

NameComponents = (
  ? firstName: tstr,
  ? familyName: tstr,
)
  """,
  """
square-roots = {* x => y}
x = int
y = float
  """,
  """
tostring = {* mynumber => tstr}
mynumber = int / float
  """,
  """
labeled-values = {
  ? fritz: number,
  * label => value
}
label = text
value = number
  """,
  """
do-not-do-this = {
  int => int,
  int => 6,
}
  """,
  """
extensible-map-example = {
  ? "optional-key" => int,
  * tstr => any
}
  """,
  """
extensible-map-example = {
  ? "optional-key" ^ => int,
  * tstr => any
}
  """,
  """
extensible-map-example = {
  ? "optional-key": int,
  * tstr => any
}
  """,
  """
extensible-map-example = {
  ? optional-key: int,
  * tstr => any
}
  """,
  """
buuid = #6.37(bstr)
my_uri = #6.32(tstr) / tstr
  """,
  """
basic-header-group = (
  field1: int,
  field2: text,
)

basic-header = [ basic-header-group ]

advanced-header = [
  basic-header-group,
  field3: bytes,
  field4: number, ; as in the tagged type "time"
]
  """,
  """
basic-header = [
  field1: int,
  field2: text,
]

advanced-header = [
  ~basic-header,
  field3: bytes,
  field4: ~time,
]
  """,
  """
full-address = [[+ label], ip4, ip6]
ip4 = bstr .size 4
ip6 = bstr .size 16
label = bstr .size (1..63)
audio_sample = uint .size 3 ; 24-bit, equivalent to 0...16777216
  """,
  """
tcpflagbytes = bstr .bits flags
flags = &(
  fin: 8,
  syn: 9,
  rst: 10,
  psh: 11,
  ack: 12,
  urg: 13,
  ece: 14,
  cwr: 15,
  ns: 0,
) / (4..7) ; data offset bits

rwxbits = uint .bits rwx
rwx = &(r: 2, w: 1, x: 0)
  """,
  """
nai = tstr .regexp "[A-Za-z0-9]+@[A-Za-z0-9]+(\\.[A-Za-z0-9]+)+"
  """,
  """
message = $message .within message-structure
message-structure = [message_type, *message_option]
message_type = 0..255
message_option = any

$message /= [3, dough: text, topping: [* text]]
$message /= [4, noodles: text, sauce: text, parmesan: bool]
  """,
  """
speed = number .ge 0  ; unit: m/s
  """,
  """
timer = {
  time: uint,
  ? displayed-step: (number .gt 0) .default 1
}
  """,
  """
tcp-header = {seq: uint, ack: uint, * $$tcp-option}

; later, in a different file

$$tcp-option //= (
sack: [+(left: uint, right: uint)]
)

; and, maybe in another file

$$tcp-option //= (
sack-permitted: true
)
  """,
  """
PersonalData = {
  ? displayName: tstr,
  NameComponents,
  ? age: uint,
  * $$personaldata-extensions
}

NameComponents = (
  ? firstName: tstr,
  ? familyName: tstr,
)

; The above already works as is.
; But then, we can add later:

$$personaldata-extensions //= (
  favorite-salsa: tstr,
)

; and again, somewhere else:

$$personaldata-extensions //= (
  shoesize: uint,
)
  """,
  """
messages = message<"reboot", "now"> / message<"sleep", 1..100>
message<t, v> = {type: t, value: v}
  """,
  """
t = [group1]
group1 = (a / b // c / d)
a = 1 b = 2 c = 3 d = 4
  """,
  """
t = {group2}
group2 = (? ab: a / b // cd: c / d)
a = 1 b = 2 c = 3 d = 4
  """,
  """
t = [group3]
group3 = (+ a / b / c)
a = 1 b = 2 c = 3
  """,
  """
t = [group4]
group4 = (+ a // b / c)
a = 1 b = 2 c = 3
  """,
  """
t = [group4a]
group4a = ((+ a) // (b / c))
a = 1 b = 2 c = 3
  """,
]

const testCases = [
  # basic
  "foo = bar",
  "foo = uint / tstr / bstr",
  "small = 0..100",
  "name = tstr .size (1..64)",
  "my-type = nil",
  "tagged = #6.1(tstr)",
  "any-cbor = #",
  "; comment\nfoo = bar",
  "g<T> = [* T]",
  # flat maps
  "address = { street: tstr, zip: uint }",
  "response = { ? \"err\" => tstr, + \"item\" => uint }",
  # flat arrays
  "coord = [float, float]",
  "things = [* tstr]",
  # nested maps inside maps
  "person = { name: tstr, address: { street: tstr, city: tstr } }",
  "config = { db: { host: tstr, port: uint }, ? tls: { cert: bstr, key: bstr } }",
  "deep = { a: { b: { c: uint } } }",
  # nested arrays inside arrays
  "matrix = [[float]]",
  "nested = [* [uint, uint]]",
  "triple = [[* tstr], [* uint], [* bstr]]",
  # maps inside arrays and arrays inside maps
  "table = [* { key: tstr, value: uint }]",
  "envelope = { headers: [* tstr], payload: [uint, bstr] }",
  "mixed = [{ x: float, y: float }, * { label: tstr }]",
  # group choices inside nested structures
  "result = { ? \"ok\" => { code: uint, body: tstr } // \"err\" => { msg: tstr } }",
  "tree = [uint, * [uint, [* uint]]]",
  # optional fields
  "profile = { name: tstr, ? email: tstr, ? age: uint }",
  # default-documented map (comment after field)
  "settings = { retries: uint, timeout-ms: uint, mode: tstr }",
  # choice of string literals (status enum)
  "status = \"pending\" / \"running\" / \"done\" / \"failed\"",
  # choice of numeric literals
  "port = 80 / 443 / 8080",
  # complex choice mixing uint, tstr, and a constrained bstr
  "bytes-id = bstr .size 16\nidentifier = uint / tstr / bytes-id",
  # text size constraint
  "short-name = tstr .size (1..32)",
  # sha256 fixed-size bstr
  "sha256 = bstr .size 32",
  # tagged URI
  "resource-url = #6.32(tstr)",
  # tagged base64
  "base64-data = #6.21(bstr)",
  # generics: single-param box
  "box<T> = { value: T }",
  # generics: list
  "list<T> = [* T]",
  # generics: two-param dictionary
  "dictionary<K, V> = { * K => V }",
  # nested generic usage
  "response<T> = { status: uint, payload: T }\npaged<T> = { items: [* T], next-page: uint }",
  # bounded list generic
  "bounded-list<T> = [1*100 T]",
  # generic group rules: the type branch of the rule is tried and abandoned
  "pair<K, V> = (key: K, value: V)",
  "$$ext<T> //= (payload: T)",
  # result<T> union generic
  "success<T> = { ok: true, value: T }\nfailure = { ok: false, error: tstr }\nresult<T> = success<T> / failure",
  # .cbor byte string
  "user = { id: uint, name: tstr }\nencoded-user = bstr .cbor user",
  # recursive tree
  "node = { value: int, children: [* node] }",
  # recursive linked list
  "linked-node = { value: any, ? next: linked-node }",
  # opcode group enum
  "opcode = &( login: 1, logout: 2, ping: 3, pong: 4 )",
  # group reuse via inline group
  "common-fields = ( id: uint, created-at: uint )\narticle = { common-fields, title: tstr, body: tstr }",
  # open map with wildcard
  "open-metadata = { version: uint, * tstr => any }",
  # integer-keyed map (sensor values)
  "sensor-values = { 1 => float, 2 => float, 3 => float }",
  # deep generic composition: api-envelope<page<user>>
  "user = { id: uint, name: tstr }\npage<T> = { items: [* T], total: uint, page: uint, page-size: uint }\napi-envelope<T> = { trace-id: tstr, timestamp: uint, payload: T }\nuser-page-envelope = api-envelope<page<user>>",
  # api-response generic with optional error sub-map
  "api-response<T> = { code: uint, success: bool, ? data: T, ? error: { message: tstr, details: tstr } }",
  # full socket/protocol example
  "message-type = 1 / 2 / 3\nheader = { version: 1, msg-type: message-type, request-id: uint }\nlogin-payload = { username: tstr, password: tstr }\nping-payload = { timestamp: uint }\npayload = login-payload / ping-payload\npacket = { header: header, body: payload }",
  # extension / any field
  "plugin-config = { name: tstr, config: any }",
]

const invalidTestCases =
  ["bad =", "", "{ broken", "foo = 1*3 tstr", "name = tstr .size 1.."]

# https://cborbook.com/part_1/cbor_schemas_with_cddl.html
const testBookCases = [
  "my-first-rule = int",
  "my-rule = int / tstr",
  "my-rule = int\nmy-rule /= tstr",
  "message-type = 1",
  """protocol-version = "1.0"""",
  "fixed-header = h'cafef00d'",
  "status-code = 200 / 404 / 500",
  "triplet = [uint, uint, uint]",
  "empty-array = []",
  "mixed-array = [bool, int / null]",
  # Maps
  """
simple-object = {
  "name": tstr,
  "age": uint,
  is-verified: bool
}
  """,
  """
indexed-data = {
  1 => tstr,
  2 => bstr,
 ? 3 => float
}
  """,
  """
lookup-table = {
  * uint => tstr
}
  """,
  "empty-map = {}",
  # Groups
  "record-header = (uint, tstr)",
  "point-2d = (float, float)",
  """
address = (
  street: tstr,
  city: tstr,
  zip: uint
)
  """,
  # Cardinality
  "optional-id = [ ?uint ]",
  "config = ( tstr, ?bool )",
  "int-list = [ *int ]",
  "byte-chunks = ( *bstr )",
  "non-empty-list = [ +tstr ]",
  "data-record = ( uint, +float )",
  "rgb-color = [ 3*3 uint ]",
  "short-ids = [ 1*5 int ]",
  "max-10-items = [ *10 any ]",
  "at-least-2 = [ 2* bstr ]",
  # Union
  "identifier = tstr / uint",
  "config-value = bool / int / tstr / null",
  "measurement = [ tstr, int / float ]",
  """
contact-method = {
    (email: tstr) //
    (phone: tstr) //
    postal-address
}
  """,
  """
response = {
    (status: 200, body: bstr) // (status: 500, error: tstr)
}
  """,
  # Constraints
  "age = uint .le 120",
  "percentage = 0..100",
  "temperature = -40..50",
  "http-status-ok = 200..299",
  "first-byte = 0x00..0xFF",
  "short-string = tstr .size (1..64)",
  "sha256-hash = bstr .size 32",
  "coordinate = [ float ] .size 2",
  "simple-map = { * tstr => any } .size (1..5)",
  """email = tstr .regexp "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"""",
  """iso-date = tstr .regexp "\d{4}-\d{2}-\d{2}"""",
  "payload = bstr .cbor any",
  "message-stream = bstr .cborseq log-entry",
]

proc normalizeText(s: string): string =
  s.replace("\r\n", "\n").strip()

suite "Test CDDL parser":
  dualTest "parse valid test cases":
    for t in @testSpecCases & @testCases & @testBookCases:
      try:
        discard parseCddl(t)
      except CborCddlError:
        checkpoint("FAILED: " & t)
        fail()

  dualTest "parse invalid test cases":
    for t in invalidTestCases:
      try:
        discard parseCddl(t)
        checkpoint("FAILED: " & t)
        fail()
      except CborCddlError:
        discard

  dualTest "schema dump":
    var schemas = default(seq[CddlSchema])
    let allCases = @testSpecCases & @testCases & @testBookCases
    for t in allCases:
      try:
        let schema = parseCddl(t)
        schemas.add schema
      except CborCddlError:
        checkpoint("FAILED (dump): " & t)
        fail()
    if schemas.len == allCases.len:
      var dump = ""
      for schema in schemas:
        for r in schema.children:
          dump.add dumpTree(r) & "\n"
          if r.kind == nkRule:
            dump.add "  ; " & toCddl(r) & "\n"
      const dumpFile = currentSourcePath.parentDir() / "test_cddl_parser_dump.txt"
      const dumpContent = staticRead(dumpFile)
      if dump.normalizeText() != dumpContent.normalizeText():
        checkpoint(dump)
        fail()

  dualTest "roundtrip":
    var schemas = default(seq[CddlSchema])
    let allCases = @testSpecCases & @testCases & @testBookCases
    for t in allCases:
      try:
        let schema = parseCddl(t)
        schemas.add schema
      except CborCddlError:
        checkpoint("FAILED (dump): " & t)
        fail()
    if schemas.len == allCases.len:
      var dump = ""
      for schema in schemas:
        dump.add toCddl(schema, pretty = true)
      const dumpFile =
        currentSourcePath.parentDir() / "test_cddl_parser_dump_pretty.txt"
      const dumpContent = staticRead(dumpFile)
      if dump.normalizeText() != dumpContent.normalizeText():
        checkpoint(dump)
        fail()

  dualTest "roundtrip-ish":
    # Sanity check without any commas, spaces and new-lines
    let rep = [("\n", ""), (" ", ""), (",", "")]
    for t in @testSpecCases & @testCases & @testBookCases:
      let got = parseCddl(t).toCddl(pretty = true) & "\n"
      if multiReplace(got, rep) != multiReplace(t, rep):
        checkpoint("got: " & got & "\n\nexpected: " & t)
        fail()

  dualTest "parse result can be stored in a const":
    const r = parseCddl("my-first-rule = int")
    check r.children[0].val.ruleText == "my-first-rule"

suite "Test CDDL Node":
  dualTest "rangeop":
    block:
      let schema = parseCddl("small = 0..100")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkRange
      check n.val.rangeKind == rngInclusive
      check n.lhs.kind == nkValue
      check n.lhs.val.text == "0"
      check n.rhs.kind == nkValue
      check n.rhs.val.text == "100"
    block:
      let schema = parseCddl("byte1 = 0...256")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkRange
      check n.val.rangeKind == rngExclusive
      check n.lhs.val.text == "0"
      check n.rhs.val.text == "256"
    block:
      let schema = parseCddl("max-byte = 255\nbyte = 0..max-byte")
      template n(): untyped =
        schema.children[1].body

      check n.kind == nkRange
      check n.rhs.kind == nkTypeRef
      check n.rhs.val.text == "max-byte"

  dualTest "ctlop":
    block:
      let schema = parseCddl("ip4 = bstr .size 4")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkControl
      check n.val.text == ".size"
      check n.lhs.kind == nkTypeRef
      check n.lhs.val.text == "bstr"
      check n.rhs.kind == nkValue
      check n.rhs.val.text == "4"
    block:
      let schema = parseCddl("user = uint\nencoded = bstr .cbor user")
      template n(): untyped =
        schema.children[1].body

      check n.kind == nkControl
      check n.val.text == ".cbor"
      check n.rhs.kind == nkTypeRef
      check n.rhs.val.text == "user"
    block:
      # the nested range must not clobber the lhs of the enclosing ctlop
      let schema = parseCddl("label = tstr .size (1..63)")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkControl
      check n.val.text == ".size"
      check n.lhs.val.text == "tstr"
      check n.rhs.kind == nkParen # as written
      template arg(): untyped =
        n.rhs.unparen

      check arg.kind == nkRange
      check arg.lhs.val.text == "1"
      check arg.rhs.val.text == "63"
    block:
      # ... nor of an enclosing ctlop
      let schema = parseCddl("nested = tstr .size (uint .lt 8)")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkControl
      check n.val.text == ".size"
      check n.lhs.val.text == "tstr"
      template arg(): untyped =
        n.rhs.unparen

      check arg.kind == nkControl
      check arg.val.text == ".lt"
      check arg.lhs.val.text == "uint"
      check arg.rhs.val.text == "8"

  dualTest "tags and major types":
    block:
      let schema = parseCddl("a = #6.32(tstr)\nb = #6(tstr)")
      check schema.children[0].body.kind == nkTagged
      check schema.children[0].body.val.major == 6
      check schema.children[0].body.val.minor == Opt.some(32'u64)
      check schema.children[0].body.target.val.text == "tstr"
      # "#6" carries no tag number, which is not the same as carrying zero
      check schema.children[1].body.val.major == 6
      check schema.children[1].body.val.minor.isNone
    block:
      let schema = parseCddl("a = #3.5\nb = #3\nc = #")
      check schema.children[0].body.kind == nkMajor
      check schema.children[0].body.val.major == 3
      check schema.children[0].body.val.minor == Opt.some(5'u64)
      check schema.children[1].body.val.major == 3
      check schema.children[1].body.val.minor.isNone
      check schema.children[2].body.kind == nkAny
      # each is dumped as it was written
      check toCddl(schema.children[0]) == "a = #3.5"
      check toCddl(schema.children[1]) == "b = #3"
    block:
      # the number is 64 bit, so a wider one is reported rather than truncated
      check parseCddl("a = #6.18446744073709551615(tstr)").children[0].body.val.minor ==
        Opt.some(18446744073709551615'u64)
      expect CborCddlError:
        discard parseCddl("a = #6.18446744073709551616(tstr)")

  dualTest "unwrap":
    block:
      let schema = parseCddl("basic = [f1: int]\nadvanced = [~basic]")
      template n(): untyped =
        schema.children[1].body

      check n.kind == nkArray
      check n.children[0].body.kind == nkUnwrap
      check n.children[0].body.target.kind == nkTypeRef
      check n.children[0].body.target.val.text == "basic"
    block:
      let schema = parseCddl("b<t> = [t]\na = ~b<uint>")
      template n(): untyped =
        schema.children[1].body

      check n.kind == nkUnwrap
      check n.target.kind == nkGeneric
      check n.target.val.text == "b"
      check n.target.children.len == 1
      check n.target.children[0].val.text == "uint"

  dualTest "group enumeration":
    block:
      let schema = parseCddl("basecolors = (black: 0)\ncolor = &basecolors")
      template n(): untyped =
        schema.children[1].body

      check n.kind == nkEnum
      check n.target.kind == nkTypeRef
      check n.target.val.text == "basecolors"
    block:
      let schema = parseCddl("extended = &(orange: 8, pink: 9)")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkEnum
      check n.target.kind == nkGroup
      check n.target.children.len == 2
      check n.target.children[0].key.val.text == "orange"
    block:
      let schema = parseCddl("b<t> = (x: t)\na = &b<uint>")
      template n(): untyped =
        schema.children[1].body

      check n.kind == nkEnum
      check n.target.kind == nkGeneric
      check n.target.val.text == "b"

  dualTest "operators are not generics":
    const expected = {
      "small = 0..100": nkRange,
      "ip4 = bstr .size 4": nkControl,
      "advanced = ~basic": nkUnwrap,
      "color = &basecolors": nkEnum,
      "extended = &(orange: 8)": nkEnum,
      "inst = message<uint>": nkGeneric,
    }
    for (t, kind) in expected:
      check parseCddl(t).children[0].body.kind == kind

  dualTest "type choices nest":
    block:
      let schema = parseCddl("a = 1 / (2 / 3) / 4")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkUnion
      check n.children.len == 3
      check n.children[0].val.text == "1"
      check n.children[1].kind == nkParen # as written
      check n.children[1].unparen.kind == nkUnion
      check n.children[1].unparen.children.len == 2
      check n.children[2].val.text == "4"
    block:
      let schema = parseCddl("a = 1 / #6.32(2 / 3)")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkUnion
      check n.children.len == 2
      check n.children[1].kind == nkTagged
      check n.children[1].target.kind == nkUnion

  dualTest "rule kinds":
    let schema =
      parseCddl("attire = \"a\"\nattire /= \"b\"\nfoo = (x: 1)\nfoo //= (y: 2)")
    check schema.children[0].val.ruleKind == rkType
    check schema.children[1].val.ruleKind == rkTypeExt
    check schema.children[2].val.ruleKind == rkGroup
    check schema.children[3].val.ruleKind == rkGroupExt
    # a group rule binds an entry, a type rule binds a type
    check schema.children[0].body.kind == nkValue
    check schema.children[2].body.kind == nkEntry
    check schema.children[2].body.body.kind == nkGroup

  dualTest "occurrence bounds":
    block:
      let schema = parseCddl("a = [2*3 int]\nb = [*3 int]\nc = [2* int]\nd = [* int]")
      template occ(i: int): untyped =
        schema.children[i].body.children[0].val.occur

      # a bound is only set when it was written: "0*3" and "*3" differ
      check occ(0).kind == ocRange
      check occ(0).lo == Opt.some(2'u64)
      check occ(0).hi == Opt.some(3'u64)
      check occ(1).lo.isNone and occ(1).hi == Opt.some(3'u64)
      check occ(2).lo == Opt.some(2'u64) and occ(2).hi.isNone
      check occ(3).kind == ocZeroOrMore
    block:
      # a bound too large to hold is reported, not truncated or wrapped
      check parseCddl("a = [18446744073709551615*2 int]").children[0].body.children[0].val.occur.lo ==
        Opt.some(18446744073709551615'u64)
      for src in [
        "a = [18446744073709551616*2 int]", "a = [2*99999999999999999999 int]"
      ]:
        expect CborCddlError:
          discard parseCddl(src)

  dualTest "generic rule parameters":
    let schema = parseCddl("dict<k, v> = {* k => v}\nplain = int")
    template rule(): untyped =
      schema.children[0]

    # the parameters are children of the rule, the body is the last one
    check rule.genericParams.len == 2
    check rule.genericParams[0].kind == nkParam
    check rule.genericParams[0].val.text == "k"
    check rule.genericParams[1].val.text == "v"
    check rule.body.kind == nkMap
    check toCddl(rule) == "dict<k, v> = {* k => v}"
    # a rule that declares none has the body as its only child
    check schema.children[1].genericParams.len == 0
    check schema.children[1].children.len == 1

  dualTest "a generic group rule reads its parameters once":
    # the type branch of the rule is tried first and abandoned, which reads the
    # parameters a second time unless the rule head drops what it read
    const expected = {"pair<k, v> = (x: k, y: v)": 2, "$$ext<t> //= (payload: t)": 1}
    for (src, params) in expected:
      let schema = parseCddl(src)
      check schema.children[0].val.ruleKind in groupRules
      check schema.children[0].genericParams.len == params
      check toCddl(schema.children[0]) == src

  dualTest "a failed type branch does not leak a container":
    # "(" is tried as a parenthesized type first; when it turns out to start a
    # group instead, the entries must still land in the group, and not in what
    # the abandoned branch left behind
    let schema = parseCddl("$$tcp-option //= ( sack: [+(left: uint, right: uint)] )")
    template rule(): untyped =
      schema.children[0]

    check rule.val.ruleKind == rkGroupExt
    check rule.body.kind == nkEntry
    check rule.body.val.occur.kind == ocOne
    template grp(): untyped =
      rule.body.body

    check grp.kind == nkGroup
    check grp.children.len == 1
    check grp.children[0].key.val.text == "sack"
    check grp.children[0].val.occur.kind == ocOne
    template arr(): untyped =
      grp.children[0].body

    check arr.kind == nkArray
    check arr.children.len == 1
    check arr.children[0].val.occur.kind == ocOneOrMore
    check arr.children[0].body.kind == nkGroup
    check arr.children[0].body.children.len == 2

  dualTest "cut member keys":
    let schema = parseCddl("m = { \"k\" ^ => int, \"j\" => int, n: uint }")
    template m(): untyped =
      schema.children[0].body

    check m.kind == nkMap
    check m.children[0].val.sepKind == skArrowCut
    check m.children[1].val.sepKind == skArrow
    check m.children[2].val.sepKind == skColon
    check m.children[0].hasCut
    check not m.children[1].hasCut
    check m.children[2].hasCut # the colon form cuts too
    check toCddl(schema.children[0]) == "m = {\"k\" ^ => int, \"j\" => int, n: uint}"

  dualTest "parens around a type":
    block:
      let schema = parseCddl("odd = (uint)")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkParen
      check n.target.kind == nkTypeRef
      check n.target.val.text == "uint"
      check n.unparen.val.text == "uint"
    block:
      let schema = parseCddl("plain = uint")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkTypeRef
      check n.unparen.kind == nkTypeRef
    block: # they nest, rather than collapsing into a flag
      let schema = parseCddl("a = 1\nd = ((a))")
      template n(): untyped =
        schema.children[1].body

      check n.kind == nkParen
      check n.target.kind == nkParen
      check n.target.target.kind == nkTypeRef
      check toCddl(schema.children[1]) == "d = ((a))"

  dualTest "group choices":
    block:
      let schema = parseCddl("m = { a: 1 // b: 2 }")
      template n(): untyped =
        schema.children[0].body

      check n.kind == nkMap
      check n.children.len == 1
      template choice(): untyped =
        n.children[0]

      check choice.kind == nkGroupChoice
      check choice.children.len == 2
      check choice.children[0].kind == nkGroup
      check choice.children[0].children.len == 1
      check choice.children[0].children[0].key.val.text == "a"
      check choice.children[1].children[0].key.val.text == "b"
    block:
      # each alternative keeps its own entries, occurrences and all
      let schema = parseCddl(
        "delivery = (street: tstr, ? number: uint // po-box: uint // per-pickup: true)"
      )
      template n(): untyped =
        schema.children[0].body.body

      check n.kind == nkGroup
      check n.children.len == 1
      template choice(): untyped =
        n.children[0]

      check choice.kind == nkGroupChoice
      check choice.children.len == 3
      check choice.children[0].children.len == 2
      check choice.children[0].children[1].val.occur.kind == ocOptional
      check choice.children[1].children.len == 1
      check choice.children[1].children[0].key.val.text == "po-box"
      check choice.children[2].children.len == 1
    block:
      # a single grpchoice stays a flat member list
      let schema = parseCddl("g = (a: 1, b: 2)")
      template n(): untyped =
        schema.children[0].body.body

      check n.kind == nkGroup
      check n.children.len == 2
      check n.children[0].kind == nkEntry
    block:
      # an empty alternative is an empty group
      let schema = parseCddl("g = ( // a: 1)")
      template n(): untyped =
        schema.children[0].body.body

      check n.children[0].kind == nkGroupChoice
      check n.children[0].children.len == 2
      check n.children[0].children[0].children.len == 0
    block:
      # a nested choice does not swallow the entries of the enclosing one
      let schema = parseCddl("outer = ( (a: 1 // b: 2) // c: 3 )")
      template n(): untyped =
        schema.children[0].body.body

      template choice(): untyped =
        n.children[0]

      check choice.kind == nkGroupChoice
      check choice.children.len == 2
      check choice.children[1].children[0].key.val.text == "c"
      template inner(): untyped =
        choice.children[0].children[0].body

      check inner.kind == nkGroup
      check inner.children[0].kind == nkGroupChoice
      check inner.children[0].children.len == 2
    block:
      # arrays and "&( ... )" carry group choices too
      let schema = parseCddl("t = [ a: 1 // b: 2 ]")
      template arr(): untyped =
        schema.children[0].body

      check arr.kind == nkArray
      check arr.children[0].kind == nkGroupChoice
      let enumSchema = parseCddl("e = &(a: 1 // b: 2)")
      template enm(): untyped =
        enumSchema.children[0].body

      check enm.kind == nkEnum
      check enm.target.kind == nkGroup
      check enm.target.children[0].kind == nkGroupChoice

  dualTest "comments are nodes kept where they were written":
    let schema = parseCddl(
      "; about person\n" & "; and more about it\n" & "person = {\n" & "  ; about name\n" &
        "  name: tstr, ; ends the name line\n" & "  age: uint,\n" & "} ; ends the rule\n"
    )
    # the ones written before the rule sit among the rules, not inside one
    check schema.children.len == 4
    check schema.children[0].kind == nkComment
    check schema.children[0].val.text == "; about person"
    check schema.children[1].val.text == "; and more about it"
    check schema.children[2].kind == nkRule
    # it ended the line the rule ended on, so it is the inline kind
    check schema.children[3].kind == nkCommentInline
    check schema.children[3].val.text == "; ends the rule"

    template m(): untyped =
      schema.children[2].body

    # and the ones inside the map sit among its members, in source order
    check m.children.len == 4
    check m.entryCount == 2 # a comment is not a member
    check m.children[0].kind == nkComment
    check m.children[0].val.text == "; about name"
    check m.children[1].kind == nkEntry
    check m.children[2].kind == nkCommentInline
    check m.children[2].val.text == "; ends the name line"
    check m.children[3].kind == nkEntry

  dualTest "a comment after the last member stays inside its container":
    ## The container is closed before the entry that owns it is finished, so a
    ## comment read just before the "}" has to be written into the members
    ## while they are still reachable.
    let schema = parseCddl("outer = {inner: {y: int ; here\n}}\n")

    template inner(): untyped =
      schema.children[0].body.firstEntry.body

    check inner.children.len == 2
    check inner.children[1].kind == nkCommentInline
    check inner.children[1].val.text == "; here"

  dualTest "comments survive a branch the parser abandons":
    ## The head of a rule is read again when its type branch fails, and a
    ## comment the abandoned branch read is read again with it; neither may
    ## leave a second copy behind, nor land in front of the rule.
    let schema = parseCddl("; about g\ng = (a: int) ; trailing\n")
    check schema.children.len == 3
    check schema.children[1].val.ruleKind == rkGroup # ie the type branch was abandoned
    check schema.children[0].val.text == "; about g"
    check schema.children[2].val.text == "; trailing"

  dualTest "the blank lines a schema is laid out with are kept":
    ## What a schema puts between its rules - a heading, a blank line, then the
    ## comment on the rule that follows - is what the nkEmpty nodes are for.
    let source =
      "; a schema\n\n; about a\na = int\nb = int\n\n; about c\nc = int\n\nd = int\n"
    let schema = parseCddl(source)
    check schema.children.len == 10
    let kinds = [
      nkComment, nkEmpty, nkComment, nkRule, nkRule, nkEmpty, nkComment, nkRule,
      nkEmpty, nkRule,
    ]
    for i in 0 ..< kinds.len:
      check schema.children[i].kind == kinds[i]
    # and it is written back the way it was read
    check toCddl(schema, pretty = true) == source

  dualTest "however many blank lines are written in a row stand for one node":
    let schema = parseCddl("\n\n\na = int\n\n\n\nb = int\n\n\n")
    check schema.children.len == 5
    let kinds = [nkEmpty, nkRule, nkEmpty, nkRule, nkEmpty]
    for i in 0 ..< kinds.len:
      check schema.children[i].kind == kinds[i]
    # and what is written back is the one break each run stood for
    check toCddl(schema, pretty = true) == "\na = int\n\nb = int\n\n"

  dualTest "a blank line inside a container is whitespace":
    ## It has no line of its own among members that each get one, so there is
    ## nowhere to write it back to.
    let schema = parseCddl("a = {\n  p: int,\n\n  q: int,\n}\n")
    check schema.children.len == 1
    check schema.children[0].body.children.len == 2

  dualTest "ignoreComments drops the blank lines with the comments":
    let schema = parseCddl("; about a\na = int\n\nb = int\n", ignoreComments = true)
    check schema.children.len == 2
    check schema.children[0].kind == nkRule
    check schema.children[1].kind == nkRule

suite "Test CDDL validator":
  dualTest "every tree the parser builds is valid":
    for t in @testSpecCases & @testCases & @testBookCases:
      for ignore in [false, true]:
        let schema = parseCddl(t, ignoreComments = ignore)
        if not schema.isValid:
          checkpoint("INVALID: " & t & "\n\nTree:\n" & dumpTree(schema))
          fail()

  dualTest "a tree the parser could not have built is invalid":
    template broken(body: untyped) =
      block:
        var n {.inject.} = parseCddl("a = {p: int, q: tstr}\n")
        body
        check not n.isValid

    broken: # an unfilled slot is no part of a finished tree
      n.children[0].children[0].children[0] = CddlNode()
    broken: # a rule without the body its parameters were declared for
      n.children[0].children.setLen 0
    broken: # only rules and comments stand among a schema
      n.children[0] = CddlNode(kind: nkEntry, children: @[CddlNode(kind: nkTypeRef)])
    broken: # a run of blank lines is folded into the one break it stands for
      n.children.add CddlNode(kind: nkEmpty)
      n.children.add CddlNode(kind: nkEmpty)
    broken: # the key an entry says it has
      n.children[0].children[0].children[0].children.setLen 1
    broken: # a leaf carries nothing
      n.children[0].children[0].children[0].children[0].children.add(
        CddlNode(kind: nkAny)
      )
    broken: # an operator has two operands
      n.children[0].children[0] =
        CddlNode(kind: nkRange, children: @[CddlNode(kind: nkAny)])
    broken: # a choice of one would have been unwrapped
      n.children[0].children[0] =
        CddlNode(kind: nkUnion, children: @[CddlNode(kind: nkAny)])
    broken: # the grammar admits no tag but major 6
      n.children[0].children[0] = CddlNode(
        kind: nkTagged, val: CddlNodeVal(major: 3), children: @[CddlNode(kind: nkAny)]
      )
    broken: # a container holds members, not rules
      n.children[0].children[0].children.add(
        CddlNode(kind: nkRule, children: @[CddlNode(kind: nkAny)])
      )
    broken: # a choice stands for all the members, so it cannot sit among them
      n.children[0].children[0].children.add CddlNode(
        kind: nkGroupChoice,
        children: @[CddlNode(kind: nkGroup), CddlNode(kind: nkGroup)],
      )
    broken: # an entry is no type to be parenthesized
      n.children[0].children[0] = CddlNode(
        kind: nkParen,
        children: @[CddlNode(kind: nkEntry, children: @[CddlNode(kind: nkAny)])],
      )

suite "Test CDDL formatter":
  dualTest "pretty breaks a container of more than one member":
    let schema = parseCddl("long = {b: tstr, c: tstr}\n")
    check toCddl(schema.children[0]) == "long = {b: tstr, c: tstr}"
    check toCddl(schema.children[0], pretty = true) ==
      "long = {\n  b: tstr,\n  c: tstr,\n}"

  dualTest "pretty keeps a lone positional member on the line its container opened":
    ## There is nothing for it to line up against, and what it holds still
    ## breaks: the map opens and the array around it is left alone.
    let schema = parseCddl(
      "a = [* foo]\nb = [* {foo: int, bar: int}]\nc = [[(x)]]\n" &
        "d = {\n ; why\n a\n}\n"
    )
    check toCddl(schema.children[0], pretty = true) == "a = [* foo]"
    check toCddl(schema.children[1], pretty = true) ==
      "b = [* {\n  foo: int,\n  bar: int,\n}]"
    check toCddl(schema.children[2], pretty = true) == "c = [[(x)]]"
    # a comment cannot share the line: it would swallow the closing delimiter
    check toCddl(schema.children[3], pretty = true) == "d = {\n  ; why\n  a,\n}"

  dualTest "pretty breaks a container whose lone member has a key":
    ## One field is still a field, and reads as one written on a line of its
    ## own; only a positional member has nothing to line up against.
    let schema = parseCddl("a = {key: value}\nb = {* tstr => any}\nc = [name: tstr]\n")
    check toCddl(schema.children[0], pretty = true) == "a = {\n  key: value,\n}"
    check toCddl(schema.children[1], pretty = true) == "b = {\n  * tstr => any,\n}"
    check toCddl(schema.children[2], pretty = true) == "c = [\n  name: tstr,\n]"

  dualTest "pretty indents a container for each one it sits inside":
    let schema = parseCddl("t = {a: {b: [c: int, d: int], e: int}, f: int}\n")
    check toCddl(schema.children[0], pretty = true) ==
      "t = {\n  a: {\n    b: [\n      c: int,\n      d: int,\n    ],\n" &
      "    e: int,\n  },\n  f: int,\n}"

  dualTest "pretty leaves alone what holds no members":
    # a range and a control operator are written the same either way
    let schema = parseCddl("r = 0..10\nc = bstr .size 4\nv = 1\n")
    for i in 0 ..< schema.children.len:
      check toCddl(schema.children[i], pretty = true) == toCddl(schema.children[i])

  dualTest "pretty gives a long type choice a line per variant":
    ## Unlike a container, a choice only breaks once it would run off the line:
    ## splitting up one of two variants reads worse than leaving it alone.
    let short = parseCddl("k = a / b / c\n")
    check toCddl(short.children[0], pretty = true) == "k = a / b / c"

    var long = "k = aaaaaaaaaa"
    for i in 0 .. 5:
      long &= " / bbbbbbbbbb"
    let schema = parseCddl(long & "\n")
    check toCddl(schema.children[0]).len > prettyWrap
    check toCddl(schema.children[0], pretty = true) ==
      "k = aaaaaaaaaa /\n  bbbbbbbbbb /\n  bbbbbbbbbb /\n  bbbbbbbbbb /\n" &
      "  bbbbbbbbbb /\n  bbbbbbbbbb /\n  bbbbbbbbbb"

  dualTest "pretty counts the indentation a choice sits at":
    ## The same choice fits on its own line but not once it is indented far
    ## enough in, so how deep it sits has to count against the wrap.
    const choice =
      "cccccccccc / dddddddddd / eeeeeeeeee / ffffffffff / gggggggggg / hhhhhhhhhh"
    check choice.len <= prettyWrap
    check toCddl(parseCddl("t = " & choice & "\n").children[0], pretty = true) ==
      "t = " & choice

    # two members apiece, so that every level of them is really indented
    var src = "t = "
    for i in 0 .. 3:
      src &= "{a: "
    src &= choice
    for i in 0 .. 3:
      src &= ", z: int}"
    let schema = parseCddl(src & "\n")
    let pretty = toCddl(schema.children[0], pretty = true)
    check "cccccccccc /\n" in pretty # broken now, though the choice is the same
    check parseCddl(pretty & "\n").children[0].toCddl() == schema.children[0].toCddl()

  dualTest "pretty printing writes comments back where they were":
    let source =
      "; about g\n" & "g = (\n" & "  \"name\": tstr,\n" & "  ; leading comment\n" &
      "  age: int, ; a bareword\n" & ")\n"
    let schema = parseCddl(source)
    check toCddl(schema, pretty = true) == source
    # a comment forces its container open however well it would fit on a line
    check toCddl(schema.children[1]) == "g = (\"name\": tstr, age: int)"

  dualTest "ignoreComments leaves a schema of nothing but its rules":
    const source =
      "; about person\n" & "person = {\n" & "  ; about name\n" &
      "  name: tstr, ; ends the name line\n" & "}\n" & "; after the last rule\n"
    let kept = parseCddl(source)
    let ignored = parseCddl(source, ignoreComments = true)
    check kept.children.len == 3 # the two comments outside the rule, and the rule
    check ignored.children.len == 1
    check ignored.children[0].kind == nkRule
    check ignored.children[0].body.children.len == 1 # no comment among the members
    check ignored.children[0].body.children[0].kind == nkEntry
    # the schema is otherwise the same one, and reads back the same way
    check toCddl(kept.children[1]) == toCddl(ignored.children[0])
    check toCddl(ignored, pretty = true) == "person = {\n  name: tstr,\n}\n"

  dualTest "a comment after the last rule is kept":
    let schema = parseCddl("a = int\n; nothing follows this\n")
    check schema.children.len == 2
    check schema.children[1].kind == nkComment
    check toCddl(schema, pretty = true) == "a = int\n; nothing follows this\n"

const schemaIssue36 = """
; -- metadata --
_module = "rt"
_version = [1, 0]

; -- types --
rt.state = "unloaded" / "loaded" / "ready" / "stopping" / "error"
rt.mode = "direct" / "local-transport" / "remote-transport"
rt.route_state = "establishing" / "ready" / "draining" / "revoked" / "failed" / "closed"

; -- method definitions --

; list_modules
rt.list_modules_request = {}
rt.list_modules_response = {
    modules: [* {
        module: tstr,
        ? provider: {
            ? runtime_instance_id: tstr,
            provider: tstr,
        },
        ? remote: {
            runtime: {
                ? runtime_instance_id: tstr,
                address: {
                    transport: tstr,
                    ? path: tstr,
                    ? host: tstr,
                    ? port: uint,
                    ? server_name: tstr,
                    ? alpn: tstr,
                },
            },
            ? provider: tstr,
            ? module: tstr,
        },
        ? instance: tstr,
        state: rt.state,
        mode: rt.mode,
        ? schema_namespace: tstr,
        ? schema: {
            commitment_model: tstr,
            schema_root: bstr,
            hash_profile: tstr,
            hash_suite: tstr,
        },
        ? reason: tstr,
    }],
}

; list_routes
rt.list_routes_request = {
    ? module: tstr,
    ? provider: {
        ? runtime_instance_id: tstr,
        provider: tstr,
    },
}
rt.list_routes_response = {
    routes: [* {
        route: tstr,
        caller_runtime: tstr,
        target_provider: {
            ? runtime_instance_id: tstr,
            provider: tstr,
        },
        module: tstr,
        ? instance: tstr,
        ? schema_namespace: tstr,
        ? schema: {
            commitment_model: tstr,
            schema_root: bstr,
            hash_profile: tstr,
            hash_suite: tstr,
        },
        state: rt.route_state,
        invocation: {
            kind: rt.mode,
            descriptor_kind: tstr,
            ? descriptor: bstr,
        },
        ? authority: {
            ? authority_provider: {
                ? runtime_instance_id: tstr,
                provider: tstr,
            },
            ? authority_ref: tstr,
            ? expires_at: uint,
            ? audit_ref: tstr,
        },
        ? failure: {
            code: tstr,
            ? message: tstr,
        },
    }],
}

; revoke_route
rt.revoke_route_request = {
    route: tstr,
    ? reason: tstr,
}
rt.revoke_route_response = {
    route: tstr,
    state: rt.route_state,
}

; start_module
rt.start_module_request = {
    module: tstr,
    ? instance: tstr,
}
rt.start_module_response = {
    module: tstr,
    instance: tstr,
    state: rt.state,
}

; stop_module
rt.stop_module_request = {
    module: tstr,
    ? instance: tstr,
}
rt.stop_module_response = {
    module: tstr,
    ? instance: tstr,
    state: rt.state,
}

; get_readiness
rt.get_readiness_request = {
    module: tstr,
    ? instance: tstr,
}
rt.get_readiness_response = {
    module: tstr,
    ? instance: tstr,
    state: rt.state,
    ? reason: tstr,
}
"""

suite "Test CDDL parser issue 36":
  dualTest "parse issue 36":
    let schema = parseCddl(schemaIssue36)
    let dump = toCddl(schema, pretty = true)
    const dumpFile =
      currentSourcePath.parentDir() / "test_cddl_parser_36_dump_pretty.txt"
    const dumpContent = staticRead(dumpFile)
    if dump.normalizeText() != dumpContent.normalizeText():
      checkpoint(dump)
      fail()

proc writeValue(w: var Cbor.Writer, value: Opt[uint64]) {.raises: [IOError].} =
  if value.isSome:
    w.writeValue(value.get())
  else:
    w.writeValue(cborNull)

proc readValue(
    r: var Cbor.Reader, value: var Opt[uint64]
) {.raises: [IOError, SerializationError].} =
  if r.parser.cborKind() == CborValueKind.Null:
    discard r.readValue(CborSimpleValue)
    value = Opt.none(uint64)
  else:
    value = Opt.some(r.readValue(uint64))

suite "Test CDDL CBOR encode/decode":
  dualTest "roundtrip valid test cases":
    for t in @testSpecCases & @testCases & @testBookCases:
      let schema = parseCddl(t)
      let encoded = Cbor.encode(schema)
      let decoded = Cbor.decode(encoded, CddlNode)
      if decoded != schema:
        checkpoint(t)
        fail()
