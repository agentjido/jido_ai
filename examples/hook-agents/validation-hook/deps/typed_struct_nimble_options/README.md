# TypedStructNimbleOptions

[![CI](https://github.com/kzemek/typed_struct_nimble_options/actions/workflows/elixir.yml/badge.svg)](https://github.com/kzemek/typed_struct_nimble_options/actions/workflows/elixir.yml)
[![Module Version](https://img.shields.io/hexpm/v/typed_struct_nimble_options.svg)](https://hex.pm/packages/typed_struct_nimble_options)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/typed_struct_nimble_options/)
[![License](https://img.shields.io/hexpm/l/typed_struct_nimble_options.svg)](https://github.com/kzemek/typed_struct_nimble_options/blob/master/LICENSE)

**TypedStructNimbleOptions** is a plugin for [TypedStruct](https://hex.pm/packages/typed_struct) that allows to easily type, validate & document Elixir structs, all in one place and with little boilerplate.

It leverages [NimbleOptions](https://hex.pm/packages/nimble_options) for validation & documentation.
Each `field` of TypedStruct is a key in the generated NimbleOptions schema.
Many options on `field` are passed directly to NimbleOptions, but in most cases they're automatically derived from the type (and other TypedStruct options).

For example

```elixir
field :attrs, %{optional(atom()) => String.t()}, enforce: true, doc: "User attributes."
```

will generate and validate with the following NimbleOptions schema:

```elixir
attrs: [
  type: {:map, :atom, :string}, # automatically derived from type
  required: true, # due to enforce: true
  doc: "User attributes.",
  type_spec: quote(do: %{optional(atom()) => String.t()})
]
```

## Example

```elixir
defmodule Person do
  @moduledoc "A struct representing a person."
  @moduledoc since: "0.1.0"

  use TypedStruct

  typedstruct do
    plugin TypedStructNimbleOptions

    field :name, String.t(), enforce: true, doc: "The name."
    field :age, non_neg_integer(), doc: "The age."
    field :happy?, boolean(), default: true
    field :attrs, %{optional(atom()) => String.t()}
  end
end

# `new/1` returns {:ok, value} | {:error, reason}
iex> Person.new(name: "George", age: 31)
{:ok, %Person{name: "George", age: 31, happy?: true, attrs: nil}}

# `new!/1` raises on error
iex> Person.new!(name: "George", age: 31, attrs: %{phone: 123})
** (NimbleOptions.ValidationError) invalid map in :attrs option: invalid value for map key :phone: expected string, got: 123

# `field_docs/0-1` returns the fields' documentation
iex> Person.field_docs()
"""
* `:name` (`t:String.t/0`) - Required. The name.\n
* `:age` (`t:non_neg_integer/0`) - The age.\n
* `:happy?` (`t:boolean/0`) - The default value is `true`.\n
* `:attrs` (map of `t:atom/0` keys and `t:String.t/0` values)\n
"""
```

### Generated `@moduledoc`s

The available options will append themselves to the `@moduledoc`.
You can modify this behavior with `append_moduledoc_header` option.

For example, the ExDoc page for the `Person` module above would start with:

```markdown
# Person

A struct representing a person.

## Fields

- `:phone` (`String.t/0`)

- `:happy?` (`boolean/0`) - The default value is `true`.

- `:age` (`non_neg_integer/0`) - The age.

- `:name` (`String.t/0`) - Required. The name.
```

## Installation

The package can be installed by adding `typed_struct_nimble_options` to your list of dependencies in `mix.exs`:

```elixir
# mix.exs

def deps do
  [
    {:typed_struct_nimble_options, "~> 0.1.0"}
  ]
end
```

## Global settings

Settings can be specified in application config to apply to all of application's
TypedStructNimbleOptions structs by default.

For example, to disable defining the documentation function by default, you can add the following setting:

```elixir
# config/config.exs
config :my_otp_app, TypedStructNimbleOptions, docs: nil
```

Individually, the same settings can be set directly on `plugin TypedStructNimbleOptions` and they will override the default settings if given.

For example, the below docs setting will override the `config.exs` setting above:

```elixir
typedstruct do
  plugin TypedStructNimbleOptions, docs: :field_docs
end
```

### Supported settings

- `:ctor` - Name of the non-bang constructor function. `nil` disables constructor generation. The default value is `:new`.
- `:ctor!` - Name of the bang constructor function. `nil` disables bang constructor generation. The default value is `:new!`.
- `:docs` - Name of the functions that return the NimbleOptions docs for the struct. `nil` disables docs functions generation. The default value is `:field_docs`.
- `:otp_app` (atom/0) - Name of the OTP application using TypedStructNimbleOptions. This is used to fetch global options for the TypedStructNimbleOptions. Defaults to `Application.get_application(__CALLER__.module)`.
- `:append_moduledoc_header` - Whether to append the generated docs to the `@moduledoc`. The docs are appended with the header specified in this option. Docs are appended only if the header is not nil. The default value is `"\n## Fields"`.
- `:warn_unknown_types?` (boolean/0) - Whether to warn when an unknown type is encountered. The default value is `true`.

## Field options

All of the following options are passed to NimbleOptions as-is, with the exception of `validation_type` which is renamed to `type` as it's being passed down.

See https://hexdocs.pm/nimble_options/NimbleOptions.html#module-schema-options for more information on the supported options.

### Automatically derived

These options are derived from information given to TypedStruct.
Users can override the settings by specifying them manually.

- `:required` - set to true if the field is `enforced` and has no `default`.
- `:type_spec` - set to the field's type
- `:validation_type` (`type`) - many basic types supported by NimbleOptions are automatically derived from the field's type, for example `atom()` type will set `type: :atom` and `String.t()` will set `type: :string`.
  Some more complex types like maps or lists are also supported.

  If TypedStructNimbleOptions encounters a type it cannot derive, it will fall back to `:any` and generate a compilation warning.
  The warnings can be disabled on a struct or global level with `warn_unknown_types?: false`.

### Passed as-is if they're given

- `:default`
- `:keys`
- `:deprecated`
- `:doc`
- `:type_doc`
- `subsection`

## Nested structs

Nested structs in particular are not automagically validated.
You should either specify `validation_type: {:struct, MyNestedStruct}` manually for the struct field, or run a custom validator with `validation_type: {:custom, M, :f, []}`.

If the nested struct also uses TypedStructNimbleOptions, you can use a special `validation_type: {:nested_struct, MyNestedStruct, :new}` that will internally run `MyNestedStruct.new/1` with proper error handling:

```elixir
defmodule Profile do
  use TypedStruct

  typedstruct enforce: true do
    plugin TypedStructNimbleOptions
    field :name, String.t()
  end
end

defmodule User do
  use TypedStruct

  typedstruct enforce: true do
    plugin TypedStructNimbleOptions
    field :id, pos_integer()
    field :profile, Profile.t(), validation_type: {:nested_struct, Profile, :new}
  end
end

iex> User.new!(id: 1, profile: [name: "UserName"])
%User{id: 1, profile: %Profile{name: "UserName"}}

iex> User.new!(id: 2, profile: %Profile{name: "UserName"})
%User{id: 2, profile: %Profile{name: "UserName"}}

iex> User.new(id: 3, profile: [name: 404])
{:error,
  %NimbleOptions.ValidationError{
    key: :profile, value: [name: 404], keys_path: [],
    message: "invalid value for :profile option: invalid value for :name option: expected string, got: 404"}}
```

## Limitations

### Compilation-time schema

The NimbleOptions schema is prepared at the compilation time, so it cannot contain runtime elements such as `fn` definitions.

## Automatically derived types

Non-parametrized types can be given with or without parentheses, e.g. `map()` is equivalent to `map`.

| Elixir type                                    | NimbleOption type                    |
| ---------------------------------------------- | ------------------------------------ |
| `map()`, `%{}`                                 | `{:map, :any, :any}`                 |
| `%{optional(key) => value}`, `%{key => value}` | `{:map, derive(key), derive(value)}` |
| `list()`                                       | `{:list, :any}`                      |
| `list(subtype)`, `[subtype]`                   | `{:list, derive(subtype)}`           |
| `{typea, ...}`                                 | `{:tuple, [derive(typea), ...]}`     |
| `atom()`                                       | `:atom`                              |
| `String.t()`                                   | `:string`                            |
| `boolean()`                                    | `:boolean`                           |
| `integer()`                                    | `:integer`                           |
| `non_neg_integer()`                            | `:non_neg_integer`                   |
| `pos_integer()`                                | `:pos_integer`                       |
| `float()`                                      | `:float`                             |
| `timeout()`                                    | `:timeout`                           |
| `pid()`                                        | `:pid`                               |
| `reference()`                                  | `:reference`                         |
| `nil`                                          | `nil`                                |
| `mfa()`                                        | `:mfa`                               |
| `any()`, `term()`                              | `:any`                               |
