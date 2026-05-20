# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/[os, strutils], unittest2, ./utils, ../cbor_serialization/tools/cddl

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
  staticTest "parse spec test cases":
    for t in testSpecCases:
      let (ok, _) = parseCddl(t)
      if not ok:
        checkpoint("FAILED (spec): " & t)
        fail()

  staticTest "parse valid test cases":
    for t in testCases:
      let (ok, _) = parseCddl(t)
      if not ok:
        checkpoint("FAILED (valid): " & t)
        fail()

  staticTest "parse invalid test cases":
    for t in invalidTestCases:
      let (ok, _) = parseCddl(t)
      if ok:
        checkpoint("FAILED (invalid): " & t)
        fail()

  staticTest "parse cbor book test cases":
    for t in testBookCases:
      let (ok, _) = parseCddl(t)
      if not ok:
        checkpoint("FAILED (book): " & t)
        fail()

  staticTest "schema dump":
    var schemas = default(seq[CddlSchema])
    var passed = true
    for t in testCases:
      let (ok, schema) = parseCddl(t)
      schemas.add schema
      if not ok:
        checkpoint("failed: " & t)
        fail()
        passed = false
        break
    if passed:
      var dump = ""
      for schema in schemas:
        for r in schema:
          dump.add "Rule: " & r.name & "  [" & $r.kind & "]\n"
          if r.genericParams.len > 0:
            dump.add "  genericParams: " & $r.genericParams & "\n"
          if r.typeExpr.kind != fkUnset:
            dump.add showType(r.typeExpr, 1) & "\n"
          elif r.groupEntries.len > 0:
            dump.add "  groupEntries: " & $r.groupEntries.len & " field(s)\n"
      const dumpFile = currentSourcePath.parentDir() / "test_cddl_dump.txt"
      const dumpContent = staticRead(dumpFile)
      if dump.normalizeText() != dumpContent.normalizeText():
        checkpoint(dump)
        fail()
