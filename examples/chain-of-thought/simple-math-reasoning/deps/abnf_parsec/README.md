# AbnfParsec

[![hex.pm](https://img.shields.io/hexpm/v/abnf_parsec.svg)](https://hex.pm/packages/abnf_parsec)
[![hex.pm](https://img.shields.io/hexpm/dt/abnf_parsec.svg)](https://hex.pm/packages/abnf_parsec)
[![hex.pm](https://img.shields.io/hexpm/l/abnf_parsec.svg)](https://hex.pm/packages/abnf_parsec)
[![github.com](https://img.shields.io/github/last-commit/princemaple/abnf_parsec.svg)](https://github.com/princemaple/abnf_parsec)

### ABNF in and parser out.

Parses ABNF with a parser written with `nimble_parsec`, emits parser consists of `nimble_parsec` combinators.

## Features

- Brevity - flattens unnecessary nesting in parsed ABNF
- Easy to config and customize
- Full test coverage

## Installation

The [package](https://hex.pm/packages/abnf_parsec) is available on [Hex](https://hex.pm)
and can be installed by adding `abnf_parsec` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:abnf_parsec, "~> 2.0", runtime: false}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/abnf_parsec](https://hexdocs.pm/abnf_parsec).

## Text / Byte mode

In some RFCs, literals in ABNF could be used to describe the byte representation instead of
the text codepoints. There is no clear distinction between them for us to detect automatically.
Hence a text / byte mode is added for the user to set.

```elixir
defmodule TextParser do
  use AbnfParsec,
    mode: :text, # the default, can be omitted
    abnf: """
    ucschar = %xA0-D7FF / %xF900-FDCF / %xFDF0-FFEF
      / %x10000-1FFFD / %x20000-2FFFD / %x30000-3FFFD
      / %x40000-4FFFD / %x50000-5FFFD / %x60000-6FFFD
      / %x70000-7FFFD / %x80000-8FFFD / %x90000-9FFFD
      / %xA0000-AFFFD / %xB0000-BFFFD / %xC0000-CFFFD
      / %xD0000-DFFFD / %xE1000-EFFFD
    """
end

defmodule ByteParser do
  use AbnfParsec,
    mode: :byte,
    abnf: """
    ; from RFC 5322 + UTF8-non-ascii
    atext = ALPHA / DIGIT / "!" / "#" / "$" / "%" / "&" / "'" / "*" / "+" /
      "-" / "/" / "=" / "?" / "^" / "_" / "`" / "{" / "|" / "}" / "~" / UTF8-non-ascii

    ; from RFC 3629
    UTF8-non-ascii  =   UTF8-2 / UTF8-3 / UTF8-4

    UTF8-2      = %xC2-DF UTF8-tail
    UTF8-3      = %xE0 %xA0-BF UTF8-tail / %xE1-EC 2( UTF8-tail ) /
          %xED %x80-9F UTF8-tail / %xEE-EF 2( UTF8-tail )
    UTF8-4      = %xF0 %x90-BF 2( UTF8-tail ) / %xF1-F3 3( UTF8-tail ) /
          %xF4 %x80-8F 2( UTF8-tail )
    UTF8-tail   = %x80-BF
    """
end
```

## Usage

```elixir
defmodule IPv4Parser do
  use AbnfParsec,
    abnf: """
    ip = first dot second dot third dot fourth
    dot = "."
    dec-octet =
      "25" %x30-35      /   ; 250-255
      "2" %x30-34 DIGIT /   ; 200-249
      "1" 2DIGIT        /   ; 100-199
      %x31-39 DIGIT     /   ; 10-99
      DIGIT                 ; 0-9
    first = dec-octet
    second = dec-octet
    third = dec-octet
    fourth = dec-octet
    """,
    unbox: ["dec-octet"],
    ignore: ["dot"],
    parse: :ip
end

# IPv4Parser.ip("192.168.0.1")
# IPv4Parser.parse("127.0.0.1")
# IPv4Parser.parse!("10.0.0.1")

iex> IPv4Parser.parse! "10.0.0.1"
[ip: [first: '10', second: '0', third: '0', fourth: '1']]
```

```elixir
defmodule JsonParser do
  use AbnfParsec,
    abnf_file: "test/fixture/json.abnf",
    parse: :json_text,
    transform: %{
      "string" => {:reduce, {List, :to_string, []}},
      "int" => [{:reduce, {List, :to_string, []}}, {:map, {String, :to_integer, []}}],
      "frac" => {:reduce, {List, :to_string, []}},
      "null" => {:replace, nil},
      "true" => {:replace, true},
      "false" => {:replace, false}
    },
    untag: ["member"],
    unwrap: ["int", "frac"],
    unbox: [
      "JSON-text",
      "null",
      "true",
      "false",
      "digit1-9",
      "decimal-point",
      "escape",
      "unescaped",
      "char"
    ],
    ignore: [
      "name-separator",
      "value-separator",
      "quotation-mark",
      "begin-object",
      "end-object",
      "begin-array",
      "end-array"
    ]
end

json = """
  {"a": {"b": 1, "c": [true]}, "d": null, "e": "e\\te"}
  """

# JsonParser.json_text(json)
# JsonParser.parse(json)
# JsonParser.parse!(json)

iex> JsonParser.parse! """
...> {"a": {"b": 1, "c": [true]}, "d": null, "e": "e\\te"}
...> """
[
  object: [
    [
      string: ["a"],
      value: [
        object: [
          [string: ["b"], value: [number: [int: 1]]],
          [string: ["c"], value: [array: [value: [true]]]]
        ]
      ]
    ],
    [string: ["d"], value: [nil]],
    [string: ["e"], value: [string: ["e\\te"]]]
  ]
]
```

For more details of options for customization, see [abnf_parsec.ex](https://github.com/princemaple/abnf_parsec/blob/main/lib/abnf_parsec.ex)

## What does it do, really?

For example, ABNF of ABNF 😉 is parsed

```
rulelist       =  1*( rule / (*c-wsp c-nl) )

rule           =  rulename defined-as elements c-nl
                      ; continues if next line starts
                      ;  with white space

rulename       =  ALPHA *(ALPHA / DIGIT / "-")

defined-as     =  *c-wsp ("=" / "=/") *c-wsp
                      ; basic rules definition and
                      ;  incremental alternatives

elements       =  alternation *c-wsp

c-wsp          =  WSP / (c-nl WSP)

c-nl           =  comment / CRLF
                      ; comment or newline

comment        =  ";" *(WSP / VCHAR) CRLF

alternation    =  concatenation
                 *(*c-wsp "/" *c-wsp concatenation)

concatenation  =  repetition *(1*c-wsp repetition)

repetition     =  [repeat] element

repeat         =  1*DIGIT / (*DIGIT "*" *DIGIT)

element        =  rulename / group / option /
                 char-val / num-val / prose-val

group          =  "(" *c-wsp alternation *c-wsp ")"

option         =  "[" *c-wsp alternation *c-wsp "]"

char-val       =  DQUOTE *(%x20-21 / %x23-7E) DQUOTE
                      ; quoted string of SP and VCHAR
                      ;  without DQUOTE

num-val        =  "%" (bin-val / dec-val / hex-val)

bin-val        =  "b" 1*BIT
                 [ 1*("." 1*BIT) / ("-" 1*BIT) ]
                      ; series of concatenated bit values
                      ;  or single ONEOF range

dec-val        =  "d" 1*DIGIT
                 [ 1*("." 1*DIGIT) / ("-" 1*DIGIT) ]

hex-val        =  "x" 1*HEXDIG
                 [ 1*("." 1*HEXDIG) / ("-" 1*HEXDIG) ]

prose-val      =  "<" *(%x20-3D / %x3F-7E) ">"
                      ; bracketed string of SP and VCHAR
                      ;  without angles
                      ; prose description, to be used as
                      ;  last resort
```

into

```elixir
[
  rule: [
    rulename: "rulelist",
    repetition: [
      repeat: [min: 1],
      alternation: [
        rulename: "rule",
        concatenation: [
          repetition: [repeat: [], rulename: "c-wsp"],
          rulename: "c-nl"
        ]
      ]
    ]
  ],
  rule: [
    rulename: "rule",
    concatenation: [
      rulename: "rulename",
      rulename: "defined-as",
      rulename: "elements",
      rulename: "c-nl"
    ],
    comment: "continues if next line starts",
    comment: "with white space"
  ],
  rule: [
    rulename: "rulename",
    concatenation: [
      rulename: "ALPHA",
      repetition: [
        repeat: [],
        alternation: [{:rulename, "ALPHA"}, {:rulename, "DIGIT"}, "-"]
      ]
    ]
  ],
  rule: [
    rulename: "defined-as",
    concatenation: [
      repetition: [repeat: [], rulename: "c-wsp"],
      alternation: ["=", "=/"],
      repetition: [repeat: [], rulename: "c-wsp"]
    ],
    comment: "basic rules definition and",
    comment: "incremental alternatives"
  ],
  rule: [
    rulename: "elements",
    concatenation: [
      rulename: "alternation",
      repetition: [repeat: [], rulename: "c-wsp"]
    ]
  ],
  rule: [
    rulename: "c-wsp",
    alternation: [
      rulename: "WSP",
      concatenation: [rulename: "c-nl", rulename: "WSP"]
    ]
  ],
  rule: [
    rulename: "c-nl",
    alternation: [rulename: "comment", rulename: "CRLF"],
    comment: "comment or newline"
  ],
  rule: [
    rulename: "comment",
    concatenation: [
      ";",
      {:repetition,
       [repeat: [], alternation: [rulename: "WSP", rulename: "VCHAR"]]},
      {:rulename, "CRLF"}
    ]
  ],
  rule: [
    rulename: "alternation",
    concatenation: [
      rulename: "concatenation",
      repetition: [
        repeat: [],
        concatenation: [
          {:repetition, [repeat: [], rulename: "c-wsp"]},
          "/",
          {:repetition, [repeat: [], rulename: "c-wsp"]},
          {:rulename, "concatenation"}
        ]
      ]
    ]
  ],
  rule: [
    rulename: "concatenation",
    concatenation: [
      rulename: "repetition",
      repetition: [
        repeat: [],
        concatenation: [
          repetition: [repeat: [min: 1], rulename: "c-wsp"],
          rulename: "repetition"
        ]
      ]
    ]
  ],
  rule: [
    rulename: "repetition",
    concatenation: [option: [rulename: "repeat"], rulename: "element"]
  ],
  rule: [
    rulename: "repeat",
    alternation: [
      repetition: [repeat: [min: 1], rulename: "DIGIT"],
      concatenation: [
        {:repetition, [repeat: [], rulename: "DIGIT"]},
        "*",
        {:repetition, [repeat: [], rulename: "DIGIT"]}
      ]
    ]
  ],
  rule: [
    rulename: "element",
    alternation: [
      rulename: "rulename",
      rulename: "group",
      rulename: "option",
      rulename: "char-val",
      rulename: "num-val",
      rulename: "prose-val"
    ]
  ],
  rule: [
    rulename: "group",
    concatenation: [
      "(",
      {:repetition, [repeat: [], rulename: "c-wsp"]},
      {:rulename, "alternation"},
      {:repetition, [repeat: [], rulename: "c-wsp"]},
      ")"
    ]
  ],
  rule: [
    rulename: "option",
    concatenation: [
      "[",
      {:repetition, [repeat: [], rulename: "c-wsp"]},
      {:rulename, "alternation"},
      {:repetition, [repeat: [], rulename: "c-wsp"]},
      "]"
    ]
  ],
  rule: [
    rulename: "char-val",
    concatenation: [
      rulename: "DQUOTE",
      repetition: [
        repeat: [],
        alternation: [
          num_range: [{:base, "x"}, "20", "21"],
          num_range: [{:base, "x"}, "23", "7E"]
        ]
      ],
      rulename: "DQUOTE"
    ],
    comment: "quoted string of SP and VCHAR",
    comment: "without DQUOTE"
  ],
  rule: [
    rulename: "num-val",
    concatenation: [
      "%",
      {:alternation,
       [rulename: "bin-val", rulename: "dec-val", rulename: "hex-val"]}
    ]
  ],
  rule: [
    rulename: "bin-val",
    concatenation: [
      "b",
      {:repetition, [repeat: [min: 1], rulename: "BIT"]},
      {:option,
       [
         alternation: [
           repetition: [
             repeat: [min: 1],
             concatenation: [
               ".",
               {:repetition, [repeat: [min: 1], rulename: "BIT"]}
             ]
           ],
           concatenation: [
             "-",
             {:repetition, [repeat: [min: 1], rulename: "BIT"]}
           ]
         ]
       ]}
    ],
    comment: "series of concatenated bit values",
    comment: "or single ONEOF range"
  ],
  rule: [
    rulename: "dec-val",
    concatenation: [
      "d",
      {:repetition, [repeat: [min: 1], rulename: "DIGIT"]},
      {:option,
       [
         alternation: [
           repetition: [
             repeat: [min: 1],
             concatenation: [
               ".",
               {:repetition, [repeat: [min: 1], rulename: "DIGIT"]}
             ]
           ],
           concatenation: [
             "-",
             {:repetition, [repeat: [min: 1], rulename: "DIGIT"]}
           ]
         ]
       ]}
    ]
  ],
  rule: [
    rulename: "hex-val",
    concatenation: [
      "x",
      {:repetition, [repeat: [min: 1], rulename: "HEXDIG"]},
      {:option,
       [
         alternation: [
           repetition: [
             repeat: [min: 1],
             concatenation: [
               ".",
               {:repetition, [repeat: [min: 1], rulename: "HEXDIG"]}
             ]
           ],
           concatenation: [
             "-",
             {:repetition, [repeat: [min: 1], rulename: "HEXDIG"]}
           ]
         ]
       ]}
    ]
  ],
  rule: [
    rulename: "prose-val",
    concatenation: [
      "<",
      {:repetition,
       [
         repeat: [],
         alternation: [
           num_range: [{:base, "x"}, "20", "3D"],
           num_range: [{:base, "x"}, "3F", "7E"]
         ]
       ]},
      ">"
    ],
    comment: "bracketed string of SP and VCHAR",
    comment: "without angles",
    comment: "prose description, to be used as",
    comment: "last resort"
  ]
]
```

And generated parser looks something like (outdated but close enough):

```elixir
[
  defparsec(
    :rulelist,
    tag(
      times(choice([parsec(:rule), repeat(parsec(:c_wsp)) |> parsec(:c_nl)]), min: 1),
      :rulelist
    )
  ),
  defparsec(
    :rule,
    tag(parsec(:rulename) |> parsec(:defined_as) |> parsec(:elements) |> parsec(:c_nl), :rule)
  ),
  defparsec(
    :rulename,
    tag(
      parsec(:core_alpha)
      |> repeat(choice([parsec(:core_alpha), parsec(:core_digit), string("-")])),
      :rulename
    )
  ),
  defparsec(
    :defined_as,
    tag(
      repeat(parsec(:c_wsp)) |> choice([string("="), string("=/")]) |> repeat(parsec(:c_wsp)),
      :defined_as
    )
  ),
  defparsec(:elements, tag(parsec(:alternation) |> repeat(parsec(:c_wsp)), :elements)),
  defparsec(:c_wsp, tag(choice([parsec(:core_wsp), parsec(:c_nl) |> parsec(:core_wsp)]), :c_wsp)),
  defparsec(:c_nl, tag(choice([parsec(:comment), parsec(:core_crlf)]), :c_nl)),
  defparsec(
    :comment,
    tag(
      string(";")
      |> repeat(choice([parsec(:core_wsp), parsec(:core_vchar)]))
      |> parsec(:core_crlf),
      :comment
    )
  ),
  defparsec(
    :alternation,
    tag(
      parsec(:concatenation)
      |> repeat(
        repeat(parsec(:c_wsp))
        |> string("/")
        |> repeat(parsec(:c_wsp))
        |> parsec(:concatenation)
      ),
      :alternation
    )
  ),
  defparsec(
    :concatenation,
    tag(
      parsec(:repetition) |> repeat(times(parsec(:c_wsp), min: 1) |> parsec(:repetition)),
      :concatenation
    )
  ),
  defparsec(:repetition, tag(optional(parsec(:repeat)) |> parsec(:element), :repetition)),
  defparsec(
    :repeat,
    tag(
      choice([
        times(parsec(:core_digit), min: 1),
        repeat(parsec(:core_digit)) |> string("*") |> repeat(parsec(:core_digit))
      ]),
      :repeat
    )
  ),
  defparsec(
    :element,
    tag(
      choice([
        parsec(:rulename),
        parsec(:group),
        parsec(:option),
        parsec(:char_val),
        parsec(:num_val),
        parsec(:prose_val)
      ]),
      :element
    )
  ),
  defparsec(
    :group,
    tag(
      string("(")
      |> repeat(parsec(:c_wsp))
      |> parsec(:alternation)
      |> repeat(parsec(:c_wsp))
      |> string(")"),
      :group
    )
  ),
  defparsec(
    :option,
    tag(
      string("[")
      |> repeat(parsec(:c_wsp))
      |> parsec(:alternation)
      |> repeat(parsec(:c_wsp))
      |> string("]"),
      :option
    )
  ),
  defparsec(
    :char_val,
    tag(
      parsec(:core_dquote)
      |> repeat(choice([ascii_char([32..33]), ascii_char([35..126])]))
      |> parsec(:core_dquote),
      :char_val
    )
  ),
  defparsec(
    :num_val,
    tag(string("%") |> choice([parsec(:bin_val), parsec(:dec_val), parsec(:hex_val)]), :num_val)
  ),
  defparsec(
    :bin_val,
    tag(
      string("b")
      |> times(parsec(:core_bit), min: 1)
      |> optional(
        choice([
          times(string(".") |> times(parsec(:core_bit), min: 1), min: 1),
          string("-") |> times(parsec(:core_bit), min: 1)
        ])
      ),
      :bin_val
    )
  ),
  defparsec(
    :dec_val,
    tag(
      string("d")
      |> times(parsec(:core_digit), min: 1)
      |> optional(
        choice([
          times(string(".") |> times(parsec(:core_digit), min: 1), min: 1),
          string("-") |> times(parsec(:core_digit), min: 1)
        ])
      ),
      :dec_val
    )
  ),
  defparsec(
    :hex_val,
    tag(
      string("x")
      |> times(parsec(:core_hexdig), min: 1)
      |> optional(
        choice([
          times(string(".") |> times(parsec(:core_hexdig), min: 1), min: 1),
          string("-") |> times(parsec(:core_hexdig), min: 1)
        ])
      ),
      :hex_val
    )
  ),
  defparsec(
    :prose_val,
    tag(
      string("<") |> repeat(choice([ascii_char([32..61]), ascii_char([63..126])])) |> string(">"),
      :prose_val
    )
  )
]
```
