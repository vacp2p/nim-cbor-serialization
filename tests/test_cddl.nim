# cbor-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2, ./utils, ../cbor_serialization/tools/cddl

when isMainModule:
  let cases = [
    # basic
    ("foo = bar\n", true),
    ("foo = uint / tstr / bstr\n", true),
    ("small = 0..100\n", true),
    ("name = tstr .size (1..64)\n", true),
    ("my-type = nil\n", true),
    ("tagged = #6.1(tstr)\n", true),
    ("any-cbor = #\n", true),
    ("; comment\nfoo = bar\n", true),
    ("g<T> = [* T]\n", true),
    ("foo = 1*3 tstr\n", true),
    # flat maps
    ("address = { street: tstr, zip: uint }\n", true),
    ("response = { ? \"err\" => tstr, + \"item\" => uint }\n", true),
    # flat arrays
    ("coord = [float, float]\n", true),
    ("things = [* tstr]\n", true),
    # nested maps inside maps
    ("person = { name: tstr, address: { street: tstr, city: tstr } }\n", true),
    (
      "config = { db: { host: tstr, port: uint }, ? tls: { cert: bstr, key: bstr } }\n",
      true,
    ),
    ("deep = { a: { b: { c: uint } } }\n", true),
    # nested arrays inside arrays
    ("matrix = [[float]]\n", true),
    ("nested = [* [uint, uint]]\n", true),
    ("triple = [[* tstr], [* uint], [* bstr]]\n", true),
    # maps inside arrays and arrays inside maps
    ("table = [* { key: tstr, value: uint }]\n", true),
    ("envelope = { headers: [* tstr], payload: [uint, bstr] }\n", true),
    ("mixed = [{ x: float, y: float }, * { label: tstr }]\n", true),
    # group choices inside nested structures
    (
      "result = { ? \"ok\" => { code: uint, body: tstr } // \"err\" => { msg: tstr } }\n",
      true,
    ),
    ("tree = [uint, * [uint, [* uint]]]\n", true),
    # optional fields
    ("profile = { name: tstr, ? email: tstr, ? age: uint }\n", true),
    # default-documented map (comment after field)
    ("settings = { retries: uint, timeout-ms: uint, mode: tstr }\n", true),
    # choice of string literals (status enum)
    ("status = \"pending\" / \"running\" / \"done\" / \"failed\"\n", true),
    # choice of numeric literals
    ("port = 80 / 443 / 8080\n", true),
    # complex choice mixing uint, tstr, and a constrained bstr
    ("bytes-id = bstr .size 16\nidentifier = uint / tstr / bytes-id\n", true),
    # text size constraint
    ("short-name = tstr .size (1..32)\n", true),
    # sha256 fixed-size bstr
    ("sha256 = bstr .size 32\n", true),
    # tagged URI
    ("resource-url = #6.32(tstr)\n", true),
    # tagged base64
    ("base64-data = #6.21(bstr)\n", true),
    # generics: single-param box
    ("box<T> = { value: T }\n", true),
    # generics: list
    ("list<T> = [* T]\n", true),
    # generics: two-param dictionary
    ("dictionary<K, V> = { * K => V }\n", true),
    # nested generic usage
    (
      "response<T> = { status: uint, payload: T }\npaged<T> = { items: [* T], next-page: uint }\n",
      true,
    ),
    # bounded list generic
    ("bounded-list<T> = [1*100 T]\n", true),
    # result<T> union generic
    (
      "success<T> = { ok: true, value: T }\nfailure = { ok: false, error: tstr }\nresult<T> = success<T> / failure\n",
      true,
    ),
    # .cbor byte string
    ("user = { id: uint, name: tstr }\nencoded-user = bstr .cbor user\n", true),
    # recursive tree
    ("node = { value: int, children: [* node] }\n", true),
    # recursive linked list
    ("linked-node = { value: any, ? next: linked-node }\n", true),
    # opcode group enum
    ("opcode = &( login: 1, logout: 2, ping: 3, pong: 4 )\n", true),
    # group reuse via inline group
    #("common-fields = ( id: uint, created-at: uint )\narticle = { common-fields, title: tstr, body: tstr }\n", true),
    # open map with wildcard
    ("open-metadata = { version: uint, * tstr => any }\n", true),
    # integer-keyed map (sensor values)
    ("sensor-values = { 1 => float, 2 => float, 3 => float }\n", true),
    # deep generic composition: api-envelope<page<user>>
    (
      "user = { id: uint, name: tstr }\npage<T> = { items: [* T], total: uint, page: uint, page-size: uint }\napi-envelope<T> = { trace-id: tstr, timestamp: uint, payload: T }\nuser-page-envelope = api-envelope<page<user>>\n",
      true,
    ),
    # api-response generic with optional error sub-map
    (
      "api-response<T> = { code: uint, success: bool, ? data: T, ? error: { message: tstr, details: tstr } }\n",
      true,
    ),
    # full socket/protocol example
    (
      "message-type = 1 / 2 / 3\nheader = { version: 1, msg-type: message-type, request-id: uint }\nlogin-payload = { username: tstr, password: tstr }\nping-payload = { timestamp: uint }\npayload = login-payload / ping-payload\npacket = { header: header, body: payload }\n",
      true,
    ),
    # extension / any field
    ("plugin-config = { name: tstr, config: any }\n", true),
    # invalid
    ("bad =\n", false),
    ("", false),
    ("{ broken\n", false),
  ]

  block:
    var passed = 0
    for (input, expected) in cases:
      let (ok, _) = parseCddl(input)
      if ok == expected:
        inc passed
        echo "PASS: ", input.repr
      else:
        doAssert false,
          "FAIL: " & input.repr & " (got ok=" & $ok & ", expected=" & $expected & ")"
    echo passed, "/", cases.len, " passed"
    echo ""

  block:
    let rich = """
foo = bar
foo-union = uint / tstr / bstr
small = 0..100
name = tstr .size (1..64)
my-type = nil
tagged = #6.1(tstr)
any-cbor = #
g<T> = [* T]
foo-occur = 1*3 tstr
address = { street: tstr, zip: uint }
response = { ? "err" => tstr, + "item" => uint }
coord = [float, float]
things = [* tstr]
person = { name: tstr, address: { street: tstr, city: tstr } }
config = { db: { host: tstr, port: uint }, ? tls: { cert: bstr, key: bstr } }
deep = { a: { b: { c: uint } } }
matrix = [[float]]
nested = [* [uint, uint]]
triple = [[* tstr], [* uint], [* bstr]]
table = [* { key: tstr, value: uint }]
envelope = { headers: [* tstr], payload: [uint, bstr] }
mixed = [{ x: float, y: float }, * { label: tstr }]
result = { ? "ok" => { code: uint, body: tstr } // "err" => { msg: tstr } }
tree = [uint, * [uint, [* uint]]]
any-type = #
union-ex = uint / tstr / bstr
ranged = 0..100
status = "pending" / "running" / "done" / "failed"
port = 80 / 443 / 8080
profile = { name: tstr, ? email: tstr, ? age: uint }
settings = { retries: uint, timeout-ms: uint, mode: tstr }
bytes-id = bstr .size 16
identifier = uint / tstr / bytes-id
short-name = tstr .size (1..32)
sha256 = bstr .size 32
resource-url = #6.32(tstr)
base64-data = #6.21(bstr)
box<T> = { value: T }
list<T> = [* T]
dictionary<K, V> = { * K => V }
response<T> = { status: uint, payload: T }
paged<T> = { items: [* T], next-page: uint }
bounded-list<T> = [1*100 T]
success<T> = { ok: true, value: T }
failure = { ok: false, error: tstr }
result-t<T> = success<T> / failure
user = { id: uint, name: tstr }
encoded-user = bstr .cbor user
node = { value: int, children: [* node] }
linked-node = { value: any, ? next: linked-node }
opcode = &( login: 1, logout: 2, ping: 3, pong: 4 )
open-metadata = { version: uint, * tstr => any }
sensor-values = { 1 => float, 2 => float, 3 => float }
page<T> = { items: [* T], total: uint, page: uint, page-size: uint }
api-envelope<T> = { trace-id: tstr, timestamp: uint, payload: T }
user-page-envelope = api-envelope<page<user>>
api-response<T> = { code: uint, success: bool, ? data: T, ? error: { message: tstr, details: tstr } }
message-type = 1 / 2 / 3
header = { version: 1, msg-type: message-type, request-id: uint }
login-payload = { username: tstr, password: tstr }
ping-payload = { timestamp: uint }
packet-payload = login-payload / ping-payload
packet = { header: header, body: packet-payload }
plugin-config = { name: tstr, config: any }
"""
    let expected = """
Rule: foo  [rkGroup]
  SimpleType(bar)
Rule: foo-union  [rkGroup]
  Union[
    SimpleType(uint)
    SimpleType(tstr)
    SimpleType(bstr)
  ]
Rule: small  [rkGroup]
  Generic(..<0,100>)
Rule: name  [rkGroup]
  Generic(..<1,..<1,64>>)
Rule: my-type  [rkGroup]
  SimpleType(nil)
Rule: tagged  [rkGroup]
  Tagged(6.1)
    SimpleType(tstr)
Rule: any-cbor  [rkGroup]
  Any
Rule: g  [rkGroup]
  genericParams: @["T"]
  Array[
    [ocZeroOrMore]
      SimpleType(T)
  ]
Rule: foo-occur  [rkGroup]
  SimpleType(tstr)
Rule: address  [rkGroup]
  Map{
    [ocOne] key=street(kkName)
      SimpleType(tstr)
    [ocOne] key=zip(kkName)
      SimpleType(uint)
  }
Rule: response  [rkGroup]
  Map{
    [ocOptional] key="err"(kkType)
      SimpleType(tstr)
    [ocOneOrMore] key="item"(kkType)
      SimpleType(uint)
  }
Rule: coord  [rkGroup]
  Array[
    [ocOne]
      SimpleType(float)
    [ocOne]
      SimpleType(float)
  ]
Rule: things  [rkGroup]
  Array[
    [ocZeroOrMore]
      SimpleType(tstr)
  ]
Rule: person  [rkGroup]
  Map{
    [ocOne] key=name(kkName)
      SimpleType(tstr)
    [ocOne] key=address(kkName)
      Map{
        [ocOne] key=street(kkName)
          SimpleType(tstr)
        [ocOne] key=city(kkName)
          SimpleType(tstr)
      }
  }
Rule: config  [rkGroup]
  Map{
    [ocOne] key=db(kkName)
      Map{
        [ocOne] key=host(kkName)
          SimpleType(tstr)
        [ocOne] key=port(kkName)
          SimpleType(uint)
      }
    [ocOptional] key=tls(kkName)
      Map{
        [ocOne] key=cert(kkName)
          SimpleType(bstr)
        [ocOne] key=key(kkName)
          SimpleType(bstr)
      }
  }
Rule: deep  [rkGroup]
  Map{
    [ocOne] key=a(kkName)
      Map{
        [ocOne] key=b(kkName)
          Map{
            [ocOne] key=c(kkName)
              SimpleType(uint)
          }
      }
  }
Rule: matrix  [rkGroup]
  Array[
    [ocOne]
      Array[
        [ocOne]
          SimpleType(float)
      ]
  ]
Rule: nested  [rkGroup]
  Array[
    [ocZeroOrMore]
      Array[
        [ocOne]
          SimpleType(uint)
        [ocOne]
          SimpleType(uint)
      ]
  ]
Rule: triple  [rkGroup]
  Array[
    [ocOne]
      Array[
        [ocZeroOrMore]
          SimpleType(tstr)
      ]
    [ocOne]
      Array[
        [ocZeroOrMore]
          SimpleType(uint)
      ]
    [ocOne]
      Array[
        [ocZeroOrMore]
          SimpleType(bstr)
      ]
  ]
Rule: table  [rkGroup]
  Array[
    [ocZeroOrMore]
      Map{
        [ocOne] key=key(kkName)
          SimpleType(tstr)
        [ocOne] key=value(kkName)
          SimpleType(uint)
      }
  ]
Rule: envelope  [rkGroup]
  Map{
    [ocOne] key=headers(kkName)
      Array[
        [ocZeroOrMore]
          SimpleType(tstr)
      ]
    [ocOne] key=payload(kkName)
      Array[
        [ocOne]
          SimpleType(uint)
        [ocOne]
          SimpleType(bstr)
      ]
  }
Rule: mixed  [rkGroup]
  Array[
    [ocOne]
      Map{
        [ocOne] key=x(kkName)
          SimpleType(float)
        [ocOne] key=y(kkName)
          SimpleType(float)
      }
    [ocZeroOrMore]
      Map{
        [ocOne] key=label(kkName)
          SimpleType(tstr)
      }
  ]
Rule: result  [rkGroup]
  Map{
    [ocOptional] key="ok"(kkType)
      Map{
        [ocOne] key=code(kkName)
          SimpleType(uint)
        [ocOne] key=body(kkName)
          SimpleType(tstr)
      }
    [ocOne] key="err"(kkType)
      Map{
        [ocOne] key=msg(kkName)
          SimpleType(tstr)
      }
  }
Rule: tree  [rkGroup]
  Array[
    [ocOne]
      SimpleType(uint)
    [ocZeroOrMore]
      Array[
        [ocOne]
          SimpleType(uint)
        [ocOne]
          Array[
            [ocZeroOrMore]
              SimpleType(uint)
          ]
      ]
  ]
Rule: any-type  [rkGroup]
  Any
Rule: union-ex  [rkGroup]
  Union[
    SimpleType(uint)
    SimpleType(tstr)
    SimpleType(bstr)
  ]
Rule: ranged  [rkGroup]
  Generic(..<0,100>)
Rule: status  [rkGroup]
  Union[
    Value("pending")
    Value("running")
    Value("done")
    Value("failed")
  ]
Rule: port  [rkGroup]
  Union[
    Value(80)
    Value(443)
    Value(8080)
  ]
Rule: profile  [rkGroup]
  Map{
    [ocOne] key=name(kkName)
      SimpleType(tstr)
    [ocOptional] key=email(kkName)
      SimpleType(tstr)
    [ocOptional] key=age(kkName)
      SimpleType(uint)
  }
Rule: settings  [rkGroup]
  Map{
    [ocOne] key=retries(kkName)
      SimpleType(uint)
    [ocOne] key=timeout-ms(kkName)
      SimpleType(uint)
    [ocOne] key=mode(kkName)
      SimpleType(tstr)
  }
Rule: bytes-id  [rkGroup]
  Generic(.size<bstr,16>)
Rule: identifier  [rkGroup]
  Union[
    SimpleType(uint)
    SimpleType(tstr)
    SimpleType(bytes-id)
  ]
Rule: short-name  [rkGroup]
  Generic(..<1,..<1,32>>)
Rule: sha256  [rkGroup]
  Generic(.size<bstr,32>)
Rule: resource-url  [rkGroup]
  Tagged(6.32)
    SimpleType(tstr)
Rule: base64-data  [rkGroup]
  Tagged(6.21)
    SimpleType(bstr)
Rule: box  [rkGroup]
  genericParams: @["T"]
  Map{
    [ocOne] key=value(kkName)
      SimpleType(T)
  }
Rule: list  [rkGroup]
  genericParams: @["T"]
  Array[
    [ocZeroOrMore]
      SimpleType(T)
  ]
Rule: dictionary  [rkGroup]
  genericParams: @["K", "V"]
  Map{
    [ocZeroOrMore] key=K(kkType)
      SimpleType(V)
  }
Rule: response  [rkGroup]
  genericParams: @["T"]
  Map{
    [ocOne] key=status(kkName)
      SimpleType(uint)
    [ocOne] key=payload(kkName)
      SimpleType(T)
  }
Rule: paged  [rkGroup]
  genericParams: @["T"]
  Map{
    [ocOne] key=items(kkName)
      Array[
        [ocZeroOrMore]
          SimpleType(T)
      ]
    [ocOne] key=next-page(kkName)
      SimpleType(uint)
  }
Rule: bounded-list  [rkGroup]
  genericParams: @["T"]
  Array[
    [ocRange]
      SimpleType(T)
  ]
Rule: success  [rkGroup]
  genericParams: @["T"]
  Map{
    [ocOne] key=ok(kkName)
      SimpleType(true)
    [ocOne] key=value(kkName)
      SimpleType(T)
  }
Rule: failure  [rkGroup]
  Map{
    [ocOne] key=ok(kkName)
      SimpleType(false)
    [ocOne] key=error(kkName)
      SimpleType(tstr)
  }
Rule: result-t  [rkGroup]
  genericParams: @["T"]
  Union[
    Generic(success<T>)
    SimpleType(failure)
  ]
Rule: user  [rkGroup]
  Map{
    [ocOne] key=id(kkName)
      SimpleType(uint)
    [ocOne] key=name(kkName)
      SimpleType(tstr)
  }
Rule: encoded-user  [rkGroup]
  Generic(.cbor<bstr,user>)
Rule: node  [rkGroup]
  Map{
    [ocOne] key=value(kkName)
      SimpleType(int)
    [ocOne] key=children(kkName)
      Array[
        [ocZeroOrMore]
          SimpleType(node)
      ]
  }
Rule: linked-node  [rkGroup]
  Map{
    [ocOne] key=value(kkName)
      SimpleType(any)
    [ocOptional] key=next(kkName)
      SimpleType(linked-node)
  }
Rule: opcode  [rkGroup]
  Group(
    [ocOne] key=login
      Value(1)
    [ocOne] key=logout
      Value(2)
    [ocOne] key=ping
      Value(3)
    [ocOne] key=pong
      Value(4)
  )
Rule: open-metadata  [rkGroup]
  Map{
    [ocOne] key=version(kkName)
      SimpleType(uint)
    [ocZeroOrMore] key=tstr(kkType)
      SimpleType(any)
  }
Rule: sensor-values  [rkGroup]
  Map{
    [ocOne] key=1(kkType)
      SimpleType(float)
    [ocOne] key=2(kkType)
      SimpleType(float)
    [ocOne] key=3(kkType)
      SimpleType(float)
  }
Rule: page  [rkGroup]
  genericParams: @["T"]
  Map{
    [ocOne] key=items(kkName)
      Array[
        [ocZeroOrMore]
          SimpleType(T)
      ]
    [ocOne] key=total(kkName)
      SimpleType(uint)
    [ocOne] key=page(kkName)
      SimpleType(uint)
    [ocOne] key=page-size(kkName)
      SimpleType(uint)
  }
Rule: api-envelope  [rkGroup]
  genericParams: @["T"]
  Map{
    [ocOne] key=trace-id(kkName)
      SimpleType(tstr)
    [ocOne] key=timestamp(kkName)
      SimpleType(uint)
    [ocOne] key=payload(kkName)
      SimpleType(T)
  }
Rule: user-page-envelope  [rkGroup]
  Generic(api-envelope<page<user>>)
Rule: api-response  [rkGroup]
  genericParams: @["T"]
  Map{
    [ocOne] key=code(kkName)
      SimpleType(uint)
    [ocOne] key=success(kkName)
      SimpleType(bool)
    [ocOptional] key=data(kkName)
      SimpleType(T)
    [ocOptional] key=error(kkName)
      Map{
        [ocOne] key=message(kkName)
          SimpleType(tstr)
        [ocOne] key=details(kkName)
          SimpleType(tstr)
      }
  }
Rule: message-type  [rkGroup]
  Union[
    Value(1)
    Value(2)
    Value(3)
  ]
Rule: header  [rkGroup]
  Map{
    [ocOne] key=version(kkName)
      Value(1)
    [ocOne] key=msg-type(kkName)
      SimpleType(message-type)
    [ocOne] key=request-id(kkName)
      SimpleType(uint)
  }
Rule: login-payload  [rkGroup]
  Map{
    [ocOne] key=username(kkName)
      SimpleType(tstr)
    [ocOne] key=password(kkName)
      SimpleType(tstr)
  }
Rule: ping-payload  [rkGroup]
  Map{
    [ocOne] key=timestamp(kkName)
      SimpleType(uint)
  }
Rule: packet-payload  [rkGroup]
  Union[
    SimpleType(login-payload)
    SimpleType(ping-payload)
  ]
Rule: packet  [rkGroup]
  Map{
    [ocOne] key=header(kkName)
      SimpleType(header)
    [ocOne] key=body(kkName)
      SimpleType(packet-payload)
  }
Rule: plugin-config  [rkGroup]
  Map{
    [ocOne] key=name(kkName)
      SimpleType(tstr)
    [ocOne] key=config(kkName)
      SimpleType(any)
  }
"""
    var schemaOut = ""
    let (ok2, schema) = parseCddl(rich)
    if ok2:
      for r in schema:
        schemaOut.add "Rule: " & r.name & "  [" & $r.kind & "]\n"
        if r.genericParams.len > 0:
          schemaOut.add "  genericParams: " & $r.genericParams & "\n"
        if r.typeExpr.kind != fkUnset:
          schemaOut.add showType(r.typeExpr, 1) & "\n"
        elif r.groupEntries.len > 0:
          schemaOut.add "  groupEntries: " & $r.groupEntries.len & " field(s)\n"
      if schemaOut != expected:
        doAssert false, "FAIL: got schema: " & schemaOut
      else:
        echo "PASS: schema validation"
    else:
      doAssert false, "ERROR: rich example failed to parse"
