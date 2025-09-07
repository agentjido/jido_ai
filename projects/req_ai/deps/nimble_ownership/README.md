# NimbleOwnership

[![hex.pm badge](https://img.shields.io/badge/Package%20on%20hex.pm-informational)](https://hex.pm/packages/nimble_ownership)
[![Documentation badge](https://img.shields.io/badge/Documentation-ff69b4)][docs]
[![CI](https://github.com/dashbitco/nimble_ownership/actions/workflows/ci.yml/badge.svg)](https://github.com/dashbitco/nimble_ownership/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/dashbitco/nimble_ownership/badge.svg?branch=main)](https://coveralls.io/github/dashbitco/nimble_ownership?branch=main)

> Library that allows you to manage ownership of resources across processes.

A typical use case for this library is tracking resource ownership across processes in order to isolate access to resources in **test suites**. For example, the [Mox][mox] library uses this module to track ownership of mocks across processes (in shared mode).

## Installation

Add this to your `mix.exs`:

```elixir
def deps do
  [
    {:nimble_ownership, "~> 0.1.0"}
  ]
end
```

## Nimble*

All nimble libraries by Dashbit:

  * [NimbleCSV](https://github.com/dashbitco/nimble_csv) - simple and fast CSV parsing
  * [NimbleOptions](https://github.com/dashbitco/nimble_options) - tiny library for validating and documenting high-level options
  * [NimbleOwnership](https://github.com/dashbitco/nimble_ownership) - resource ownership tracking
  * [NimbleParsec](https://github.com/dashbitco/nimble_parsec) - simple and fast parser combinators
  * [NimblePool](https://github.com/dashbitco/nimble_pool) - tiny resource-pool implementation
  * [NimblePublisher](https://github.com/dashbitco/nimble_publisher) - a minimal filesystem-based publishing engine with Markdown support and code highlighting
  * [NimbleTOTP](https://github.com/dashbitco/nimble_totp) - tiny library for generating time-based one time passwords (TOTP)

## License

Copyright 2023 Dashbit

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

[docs]: https://hexdocs.pm/nimble_ownership
[mox]: https://github.com/dashbitco/mox
