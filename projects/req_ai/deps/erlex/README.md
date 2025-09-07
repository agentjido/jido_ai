# Erlex

Convert Erlang style structs and error messages to equivalent Elixir.

Useful for pretty printing things like Dialyzer errors and Observer
state. NOTE: Because this code calls the Elixir formatter, it requires
Elixir 1.6+.

[![Version][hex-pm-version-badge]][hex-pm-versions]
[![Documentation][docs-badge]][docs]
[![License][hex-pm-license-badge]][apache-2-license]
[![Downloads][hex-pm-downloads-badge]][hex-pm-package]

|         👍         |                  [Test Suite][suite]                  |                   [Test Coverage][coverage]                    |
| :----------------: | :---------------------------------------------------: | :------------------------------------------------------------: |
| [Release][release] | [![Build Status][release-suite-badge]][release-suite] | [![Coverage Status][release-coverage-badge]][release-coverage] |
|  [Latest][latest]  |  [![Build Status][latest-suite-badge]][latest-suite]  |  [![Coverage Status][latest-coverage-badge]][latest-coverage]  |

## Changelog

Check out the [Changelog](https://github.com/christhekeele/erlex/blob/master/CHANGELOG.md).

## Installation

The package can be installed from Hex by adding `erlex` to your list
of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:erlex, "~> 0.2"},
  ]
end
```

## Usage

Invoke `Erlex.pretty_print/1` with the input string.

```elixir
iex> str = ~S"('Elixir.Plug.Conn':t(),binary() | atom(),'Elixir.Keyword':t() | map()) -> 'Elixir.Plug.Conn':t()"
iex> Erlex.pretty_print(str)
(Plug.Conn.t(), binary() | atom(), Keyword.t() | map()) :: Plug.Conn.t()
```

While the lion's share of the work is done via invoking
`Erlex.pretty_print/1`, other higher order functions exist for further
formatting certain messages by running through the Elixir formatter.
Because we know the previous example is a type, we can invoke the
`Erlex.pretty_print_contract/1` function, which would format that
appropriately for very long lines.

```elixir
iex> str = ~S"('Elixir.Plug.Conn':t(),binary() | atom(),'Elixir.Keyword':t() | map(), map() | atom(), non_neg_integer(), binary(), binary(), binary(), binary(), binary()) -> 'Elixir.Plug.Conn':t()"
iex> Erlex.pretty_print_contract(str)
(
  Plug.Conn.t(),
  binary() | atom(),
  Keyword.t() | map(),
  map() | atom(),
  non_neg_integer(),
  binary(),
  binary(),
  binary(),
  binary(),
  binary()
) :: Plug.Conn.t()
```

## Contributing

We welcome contributions of all kinds! To get started, click [here](https://github.com/christhekeele/erlex/blob/master/CONTRIBUTING.md).

## Code of Conduct

Be sure to read and follow the [code of conduct](https://github.com/christhekeele/erlex/blob/master/code-of-conduct.md).

<!-- LINKS & IMAGES -->

<!-- Hex -->

[hex-pm]: https://hex.pm
[hex-pm-package]: https://hex.pm/packages/erlex
[hex-pm-versions]: https://hex.pm/packages/erlex/versions
[hex-pm-version-badge]: https://img.shields.io/hexpm/v/erlex.svg?cacheSeconds=86400&style=flat-square
[hex-pm-downloads-badge]: https://img.shields.io/hexpm/dt/erlex.svg?cacheSeconds=86400&style=flat-square
[hex-pm-license-badge]: https://img.shields.io/hexpm/l/erlex.svg?cacheSeconds=86400&style=flat-square

<!-- Docs -->

[docs]: https://hexdocs.pm/erlex/index.html
[docs-guides]: https://hexdocs.pm/erlex/usage.html#content
[docs-badge]: https://img.shields.io/badge/documentation-online-purple?cacheSeconds=86400&style=flat-square

<!-- Deps -->

[deps]: https://hex.pm/packages/erlex
[deps-badge]: https://img.shields.io/badge/dependencies-0-blue?cacheSeconds=86400&style=flat-square

<!-- Benchmarks -->

[benchmarks]: https://christhekeele.github.io/erlex/bench
[benchmarks-badge]: https://img.shields.io/badge/benchmarks-online-2ab8b5?cacheSeconds=86400&style=flat-square

<!-- Contributors -->

[contributors]: https://hexdocs.pm/erlex/contributors.html
[contributors-badge]: https://img.shields.io/badge/contributors-%F0%9F%92%9C-lightgrey

<!-- Status -->

[suite]: https://github.com/christhekeele/erlex/actions/workflows/test-suite.yml?query=workflow%3A%22Test+Suite%22
[coverage]: https://coveralls.io/github/christhekeele/erlex

<!-- Release Status -->

[release]: https://github.com/christhekeele/erlex/tree/release
[release-suite]: https://github.com/christhekeele/erlex/actions/workflows/test-suite.yml?query=workflow%3A%22Test+Suite%22+branch%3Arelease
[release-suite-badge]: https://img.shields.io/github/actions/workflow/status/christhekeele/erlex/test-suite.yml?branch=release&cacheSeconds=86400&style=flat-square
[release-coverage]: https://coveralls.io/github/christhekeele/erlex?branch=release
[release-coverage-badge]: https://img.shields.io/coverallsCoverage/github/christhekeele/erlex?branch=release&cacheSeconds=86400&style=flat-square

<!-- Latest Status -->

[latest]: https://github.com/christhekeele/erlex/tree/latest
[latest-suite]: https://github.com/christhekeele/erlex/actions/workflows/test-suite.yml?query=workflow%3A%22Test+Suite%22+branch%3Alatest
[latest-suite-badge]: https://img.shields.io/github/actions/workflow/status/christhekeele/erlex/test-suite.yml?branch=latest&cacheSeconds=86400&style=flat-square
[latest-coverage]: https://coveralls.io/github/christhekeele/erlex?branch=latest
[latest-coverage-badge]: https://img.shields.io/coverallsCoverage/github/christhekeele/erlex?branch=latest&cacheSeconds=86400&style=flat-square

<!-- Other -->

[changelog]: https://hexdocs.pm/erlex/changelog.html
[test-matrix]: https://github.com/christhekeele/erlex/actions/workflows/test-matrix.yml
[test-edge]: https://github.com/christhekeele/erlex/actions/workflows/test-edge.yml
[contributing]: https://hexdocs.pm/erlex/contributing.html
[apache-2-license]: https://choosealicense.com/licenses/apache-2.0/
