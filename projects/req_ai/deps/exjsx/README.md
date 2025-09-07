# exjsx (v4.0.0) #

[json][json] for [elixir][elixir]
 
based on [jsx][jsx]

testing provided by [travis-ci][travis]

[![Build Status](https://secure.travis-ci.org/talentdeficit/exjsx.png)](http://travis-ci.org/talentdeficit/exjsx)

exjsx is released under the terms of the [MIT][MIT] license

copyright 2013, 2014, 2015, 2016, 2017 alisdair sullivan


## index ##

* [quickstart](#quickstart)
  - [building and running tests](#build-the-library-and-run-tests)
  - [decoding json](#convert-a-json-string-into-an-elixir-dict)
  - [encoding json](#convert-an-elixir-dict-into-a-json-string)
  - [checking validity](#check-if-a-binary-or-a-term-is-valid-json)
  - [minify](#minify-some-json)
  - [prettify](#prettify-some-json)
* [description](#description)
  - [json <-> elixir mapping summary](#json---elixir-mapping)
  - [numbers](#numbers)
  - [strings](#strings)
  - [true, false and null/nil](#true-false-and-nullnil)
  - [arrays](#arrays)
  - [objects](#objects)
* [fma](#frequently-made-accusations)
  - [your lib sucks and encodes my structs wrong](#your-lib-sucks-and-encodes-my-structs-wrong)
  - [you forgot to document incompletes](#you-forgot-to-document-incompletes)
* [options](#options)
  - [escaped forward slashes](#escaped_forward_slashes)
  - [escaped strings](#escaped_strings)
  - [uescape](#uescape)
  - [unescaped jsonp](#unescaped_jsonp)
  - [dirty strings](#dirty_strings)
  - [strict](#strict)
* [exports](#exports)
  - [decode and decode!](#decodejson-opts)
  - [encode and encode!](#encodeterm-opts)
  - [format and format!](#formatjson-opts)
  - [minify and minify!](#minifyjson)
  - [prettify and prettify!](#prettifyjson)
  - [is_json?](#is_jsonjson-opts)
  - [is_term?](#is_termterm-opts)
* [acknowledgements](#acknowledgements)


## quickstart ##

#### build the library and run tests ####

```bash
$ mix compile
$ mix test
```

#### convert a json string into an elixir term ####

```iex
iex> JSX.decode "{\"library\": \"jsx\", \"awesome\": true}"
{:ok, %{"awesome" => true, "library" => "jsx"}}
iex> JSX.decode "[\"a\",\"list\",\"of\",\"words\"]"
{:ok, ["a", "list", "of", "words"]}
```

#### convert an elixir term into a json string ####

```iex
iex> JSX.encode %{"library" => "jsx", "awesome" => true}
{:ok, "{\"awesome\":true,\"library\":\"jsx\"}"}
iex> JSX.encode [library: "jsx", awesome: true]
{:ok, "{\"library\":\"jsx\",\"awesome\":true}"}
iex> JSX.encode ["a","list","of","words"]
{:ok, "[\"a\",\"list\",\"of\",\"words\"]"}
```

#### check if a binary or a term is valid json ####

```iex
iex> JSX.is_json? "[\"this is json\"]"
true
iex> JSX.is_json? ["this is not"]
false
iex> JSX.is_term? ["this is a term"]
true
iex> JSX.is_term? self()
false
```

#### minify some json ####

```iex
iex> JSX.minify "{
...>   \"a list\": [
...>     1,
...>     2,
...>     3
...>   ]
...> }"
{:ok,"{\"a list\":[1,2,3]}"}
```

#### prettify some json ####

```iex
iex> JSX.prettify "{\"a list\":[1,2,3]}"
{:ok, "{
  \"a list\": [
    1,
    2,
    3
  ]
}"}
```


## description ##

exjsx is an [elixir][elixir] application for consuming, producing and manipulating 
[json][json]

json has a [spec][rfc4627] but common usage deviates in a number of cases. exjsx
attempts to address common usage while following the spirit of the spec

all json produced and consumed by exjsx should be `utf8` encoded text or a 
reasonable approximation thereof. ascii works too, but anything beyond that 
i'm not going to make any promises. **especially** not latin1


#### json &lt;-> elixir mapping ####

**json**                        | **elixir**
--------------------------------|--------------------------------
`number`                        | `Float` and `Integer`
`string`                        | `String`
`true` and `false`              | `true` and `false`
`null`                          | `nil`
`array`                         | `List` and `Enumerable`
`object`                        | `Map`

#### numbers ####

javascript and thus json represent all numeric values with floats. as 
this is woefully insufficient for many uses, **exjsx**, just like elixir, 
supports bigints. whenever possible, this library will interpret json 
numbers that look like integers as integers. other numbers will be converted 
to elixir's floating point type, which is nearly but not quite iee754. 
negative zero is not representable in elixir (zero is unsigned in elixir and 
`0` is equivalent to `-0`) and will be interpreted as regular zero. numbers 
not representable are beyond the concern of this implementation, and will 
result in parsing errors

when converting from elixir to json, numbers are represented with their 
shortest representation that will round trip without loss of precision. this 
means that some floats may be superficially dissimilar (although 
functionally equivalent). for example, `1.0000000000000001` will be 
represented by `1.0`

#### strings ####

the json [spec][rfc4627] is frustratingly vague on the exact details of json 
strings. json must be unicode, but no encoding is specified. javascript 
explicitly allows strings containing codepoints explicitly disallowed by 
unicode. json allows implementations to set limits on the content of 
strings. other implementations attempt to resolve this in various ways. this 
implementation, in default operation, only accepts strings that meet the 
constraints set out in the json spec (strings are sequences of unicode 
codepoints deliminated by `"` (`u+0022`) that may not contain control codes 
unless properly escaped with `\` (`u+005c`)) and that are encoded in `utf8`

the utf8 restriction means improperly paired surrogates are explicitly 
disallowed. `u+d800` to `u+dfff` are allowed, but only when they form valid 
surrogate pairs. surrogates encountered otherwise result in errors

json string escapes of the form `\uXXXX` will be converted to their 
equivalent codepoints during parsing. this means control characters and 
other codepoints disallowed by the json spec may be encountered in resulting 
strings, but codepoints disallowed by the unicode spec will not be. in the 
interest of pragmatism there is an [option](#options) for looser parsing

all elixir strings are represented by BitStrings. the encoder will check
strings for conformance. noncharacters (like `u+ffff`)  are allowed in elixir 
utf8 encoded binaries, but not in strings passed to the encoder (although,
again, see [options](#options))

when encoding, atoms are first converted to BitStrings

this implementation performs no normalization on strings beyond that 
detailed here. be careful when comparing strings as equivalent strings 
may have different `utf8` encodings

#### true, false and null/nil ####

the json primitives `true`, `false` and `null` are represented by the 
elixir atoms `true`, `false` and `nil`

#### arrays ####

json arrays are represented with elixir lists of json values as described 
in this section. elixir enumerables like `Stream`, `Range` and `MapSet` are
serialized to json arrays

#### objects ####

json objects are represented by elixir maps. keys are atoms, bitstrings or integers
and values are valid json values. structs, keylists and dicts are serialized to objects
automagically but there is currently no way to perform the reverse. stay tuned tho


## frequently made accusations ##

#### your lib sucks and encodes my structs wrong ####

so you have this struct:

```elixir
defmodule Character do
  defstruct name: nil, rank: nil
end
```

```iex
iex> JSX.encode %Character{name: "Walder Frey", rank: "Lord"}
{:ok, "{\"name\":\"Walder Frey\",\"rank\":\"Lord\"}"}
```

but you don't like that encoding. ok. do this:

```elixir
defimpl JSX.Encoder, for: Character do
  def json(record) do
    [:start_object, "name", record.rank <> " " <> record.name, :end_object]
  end
end
```

```iex
iex> JSX.encode Character.new(name: "Walder Frey", rank: "Lord")
{:ok, "{\"name\":\"Lord Walder Frey\"}"}
```

apart from the [jsx][jsx] internal format you can also generate you own json
and pass it to the encoder with `[{:raw, "{\"name\": \"Lord Walder Frey\"}"}]`

someone should write a macro that does this and make a pull request

#### you forgot to document incompletes ####

no i didn't. they are [jsx][jsx] only for now. stay tuned tho


## options ##

**exjsx** functions all take a common set of options. not all flags have meaning 
in all contexts, but they are always valid options. functions may have 
additional options beyond these. see 
[individual function documentation](#exports) for details

#### `escaped_forward_slashes` ####

json strings are escaped according to the json spec. this means forward 
slashes (solidus) are only escaped when this flag is present. otherwise they 
are left unescaped. you may want to use this if you are embedding json 
directly into a html or xml document

#### `escaped_strings` ####

by default both the encoder and decoder return strings as utf8 binaries 
appropriate for use in elixir. escape sequences that were present in decoded 
terms are converted into the appropriate codepoint while encoded terms are 
unaltered. this flag escapes strings as if for output in json, removing 
control codes and problematic codepoints and replacing them with the 
appropriate escapes

#### `uescape` ####

escape all codepoints outside the ascii range for 7 bit clean output. note this 
escaping takes place even if no other string escaping is requested (via 
`escaped_strings`)

#### `unescaped_jsonp` ####

javascript interpreters treat the codepoints `u+2028` and `u+2029` as 
significant whitespace. json strings that contain either of these codepoints 
will be parsed incorrectly by some javascript interpreters. by default, 
these codepoints are escaped (to `\u2028` and `\u2029`, respectively) to 
retain compatibility. this option simply removes that escaping

#### `dirty_strings` ####

json escaping is lossy; it mutates the json string and repeated application 
can result in unwanted behaviour. if your strings are already escaped (or 
you'd like to force invalid strings into "json" you monster) use this flag 
to bypass escaping. this can also be used to read in **really** invalid json 
strings. everything between unescaped quotes are passed as is to the resulting 
string term. note that this takes precedence over any other options

#### `strict` ####

as mentioned [earlier](#description), **exjsx** is pragmatic. if you're more of a
json purist or you're really into bdsm stricter adherence to the spec is
possible. the following restrictions are available

* `:comments`

    comments are disabled and result in `ArgumentError` or `{:error, :badarg}`

* `:utf8`

    invalid codepoints and malformed unicode result in `ArgumentError`  or
    `{:error, :badarg}`

* `:single_quotes`

    only keys and strings delimited by double quotes (`u+0022`) are allowed. the
    single quote (`u+0027`) results in `ArgumentError`  or `{:error, :badarg}`

* `trailing_commas`

    trailing commas in an object or list result in `badarg` errors

* `:escapes`

    escape sequences not adhering to the json spec result in `ArgumentError`  or
    `{:error, :badarg}`

any combination of these can be passed to **exjsx** by using `{:strict, [strict_option()]}`.
`:strict` is equivalent to `{:strict, [:comments, :bad_utf8, :single_quotes, :escapes]}` 


## exports ##

#### `decode(json, opts)` ####

`decode` parses a json text (a `BitString`) and produces `{:ok, result}` or
`{:error, reason}`

`opts` has the default value `[]` and can be a list containing any of the
standard exjsx [options](#options) plus the following

* `{:labels, :binary}`
    json object's keys will be decoded to `BitStrings`. the default

* `{:labels, :atom}`
    json object's keys will be decoded to `Atoms`

* `{:labels, :existing_atom}`
    json object's keys will be decoded to `Atoms` if they are already
    known to the runtime, otherwise the decoder will return an error

##### examples #####

```iex
iex> JSX.decode "[true, false, null]"
{:ok,[true,false,nil]}
iex> JSX.decode("{\"key\": true}", [{:labels, :binary}])
{:ok, %{"key" => true}}
iex> JSX.decode("{\"key\": true}", [{:labels, :atom}])
{:ok, %{key: true}}
iex> JSX.decode [:a, :b, :c]
{:error, :badarg}
```

#### `decode!(json, opts)` ####

`decode!` parses a json text (a `BitString`) and produces `result` or
an `ArgumentError` exception

see [decode](#decodejson-opts) for opts

##### examples #####

```iex
iex> JSX.decode! "[true, false, null]"
[true, false, nil]
iex> JSX.decode! [:a, :b, :c]
** (ArgumentError) argument error
```

#### `encode(term, opts)` ####

`encode` produces takes an elixir term and produces `{:ok, json}` or
`{:error, :badarg}`

`opts` has the default value `[]` and can be a list containing any of the
standard exjsx [options](#options) plus the following

* `{:space, n}`
    inserts `n` spaces after every comma and colon in your  json output.
    `:space` is an alias for `{:space, 1}`. the default is `{:space, 0}`

* `{:indent, n}`
    inserts a newline and `n` spaces for each level of indentation in your
    json output after each comma. note that this overrides spaces inserted
    after a comma. `:indent` is an alias for `{:indent, 1}`. the default
    is `{:indent, 0}`

##### examples #####

```iex
iex> JSX.encode [true, false, nil]
{:ok, "[true,false,null]"}
iex> JSX.encode(%{:a => 1, :b => 2, :c => 3}, [{:space, 2}, :indent])
{:ok,"{
 \"a\":  1,
 \"b\":  2,
 \"c\":  3
}"}
iex> JSX.encode(%{:a => 1, :b => 2, :c => 3}, [:space, {:indent, 4}])
{:ok,"{
    \"a\": 1,
    \"b\": 2,
    \"c\": 3
}"}
```

#### `encode!(json, opts)` ####

`encode!` produces takes an elixir term and produces `json` or
an `ArgumentError` exception

see [encode](#encodejson-opts) for opts

##### examples #####

```iex
iex> JSX.encode! [true, false, null]
[true, false, nil]
iex> JSX.encode! [self()]
** (ArgumentError) argument error
```

#### `format(json, opts)` ####

`format` parses a json text and produces formatted `{:ok, json}` or
`{:error, :badarg}`

see [encode](#encodejson-opts) for opts

##### examples #####

```iex
iex> JSX.format "[true, false, null]"
{:ok, "[true,false,null]"}
iex> JSX.format("[true, false, null]", [space: 2])
{:ok, "[true,  false,  null]"}
iex> JSX.format("[true, false, null]", [space: 4])
{:ok, "[true,    false,    null]"}
iex> JSX.format "{\"foo\":true,\"bar\":false}"
{:ok, "{\"foo\":true,\"bar\":false}"}
iex> JSX.format("{\"foo\":true,\"bar\":false}", [:space])
{:ok, "{\"foo\": true,\"bar\": false}"}
iex> JSX.format("{\"foo\":true,\"bar\":false}", [space: 2, indent: 4])
{:ok, "{
    \"foo\":  true,
    \"bar\":  false
}"}
iex> JSX.format [self()]
{:error,:badarg}
```

#### `format!(json, opts)` ####

`format!` parses a json text and produces formatted `json` or
an `ArgumentError` exception

see [encode](#encodejson-opts) for opts

##### examples #####

```iex
iex> JSX.format! "[true, false, null]"
"[true,false,null]"
iex> JSX.format!("{\"foo\":true,\"bar\":false}", [space: 2, indent: 4])
"{
    \"foo\":  true,
    \"bar\":  false
}"
iex> JSX.format! [self()]
** (ArgumentError) argument error
```

#### `minify(json)` ####

`minify` is an alias for `format(json, [space: 0, indent: 0])`

##### examples #####

```iex
iex> JSX.minify "[true, false, null]"
{:ok,"[true,false,null]"}
iex> JSX.minify [self()]
{:error,:badarg}
```

#### `minify!(json)` ####

`minify!` is an alias for `format!(json, [space: 0, indent: 0])`

##### examples #####

```iex
iex> JSX.minify! "[true, false, null]"
"[true,false,null]"
iex> JSX.minify [self()]
** (ArgumentError) argument error
```

#### `prettify(json)` ####

`prettify` is an alias for `format(json, [space: 1, indent: 2])`

##### examples #####

```iex
iex> JSX.prettify "[true, false, null]"
{:ok,"[
  true,
  false,
  null
]"}
iex> JSX.prettify [self()]
{:error,:badarg}
```

#### `prettify!(json)` ####

`prettify!` is an alias for `format!(json, [space: 1, indent: 2])`

##### examples #####

```iex
iex> JSX.prettify! "[true, false, null]"
"[
  true,
  false,
  null
]"
iex> JSX.prettify! [self()]
** (ArgumentError) argument error
```

#### `is_json?(json, opts)` ####

returns `true` if input is a valid json text, `false` if not

`opts` has the default value `[]` and can be a list containing any of the
standard exjsx [options](#options)

what exactly constitutes valid json may be [altered](#options)

##### examples #####

```iex
iex> JSX.is_json? "[true, false, null]"
true
iex> JSX.is_json? [self()]
false
```

#### `is_term?(term, opts)` ####

returns `true` if input is an elixir term that can be safely converted to json,
`false` if not

`opts` has the default value `[]` and can be a list containing any of the
standard exjsx [options](#options)

what exactly constitutes valid json may be [altered](#options)

##### examples #####

```iex
iex> JSX.is_term? [true, false, nil]
true
iex> JSX.is_term? [self()]
false
```


## acknowledgements ##

exjsx wouldn't be what it is without the guidance and code review of 
[yurii rashkovskii](https://github.com/yrashk), [eduardo gurgel](https://github.com/edgurgel) and [devin torres](https://github.com/devinus)

[json]: http://json.org
[elixir]: https://github.com/elixir-lang/elixir
[jsx]: https://github.com/talentdeficit/jsx
[MIT]: http://www.opensource.org/licenses/mit-license.html
[rfc4627]: http://tools.ietf.org/html/rfc4627
[travis]: https://travis-ci.org/
