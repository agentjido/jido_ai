# JSV

<!-- rdmx :badges
    hexpm         : "jsv?color=4e2a8e"
    github_action : "lud/jsv/elixir.yaml?label=CI&branch=main"
    license       : jsv
    -->
[![hex.pm Version](https://img.shields.io/hexpm/v/jsv?color=4e2a8e)](https://hex.pm/packages/jsv)
[![Build Status](https://img.shields.io/github/actions/workflow/status/lud/jsv/elixir.yaml?label=CI&branch=main)](https://github.com/lud/jsv/actions/workflows/elixir.yaml?query=branch%3Amain)
[![License](https://img.shields.io/hexpm/l/jsv.svg)](https://hex.pm/packages/jsv)
<!-- rdmx /:badges -->

JSV is a JSON Schema Validation library for Elixir with full support for the latest JSON Schema specification.



## Documentation

[API documentation is available on hexdocs.pm](https://hexdocs.pm/jsv/).


## Supported Dialects


JSV's goal is to support 100% of the latest specification, which is currently 2020-12. Additional support for Draft 7 is also included.

* [![Draft 2020-12](https://img.shields.io/endpoint?url=https%3A%2F%2Fbowtie.report%2Fbadges%2Felixir-jsv%2Fcompliance%2Fdraft2020-12.json)](https://bowtie.report/#/implementations/elixir-jsv)
* [![Draft 7](https://img.shields.io/endpoint?url=https%3A%2F%2Fbowtie.report%2Fbadges%2Felixir-jsv%2Fcompliance%2Fdraft7.json)](https://bowtie.report/#/implementations/elixir-jsv)

## Installation

<!-- rdmx :app_dep vsn:$app_vsn -->
```elixir
def deps do
  [
    {:jsv, "~> 0.13"},
  ]
end
```
<!-- rdmx /:app_dep -->

**Optional** dependencies can be added to support more features:

```elixir
def deps do
  [
    # JSV Supports Decimal and will validate Decimal structs as numbers.
    {:decimal, "~> 2.0"},

    # Decoding schemas resolved via HTTP requires JSON support for Elixir
    # versions prior to 1.18
    {:jason, "~> 1.0"},
    # OR
    {:poison, "~> 6.0 or ~> 5.0"},
  ]
end
```


## Basic Usage

Here is an example of how to use the library:

```elixir
schema = %{
  type: :object,
  properties: %{
    name: %{type: :string}
  },
  required: [:name]
}

root = JSV.build!(schema)

case JSV.validate(%{"name" => "Alice"}, root) do
  {:ok, data} ->
    {:ok, data}

  # Errors can be converted into JSON-compatible structures for API responses
  # or logging.
  {:error, validation_error} ->
    {:error, JSON.encode!(JSV.normalize_error(validation_error))}
end
```

JSV offers many additional features! Check the documentation for more details.


## Contributing

Pull requests are welcome, provided they include appropriate tests and documentation.
