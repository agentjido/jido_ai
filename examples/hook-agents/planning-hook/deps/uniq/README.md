# Uniq

[![Master](https://github.com/bitwalker/uniq/workflows/elixir/badge.svg?branch=main)](https://github.com/bitwalker/uniq/actions?query=workflow%3A%22elixir%22+branch%3Amain)
[![Hex.pm Version](http://img.shields.io/hexpm/v/uniq.svg?style=flat)](https://hex.pm/packages/uniq)

Uniq provides generation, formatting, parsing, and analysis of RFC 4122 UUIDs, with
support for the draft UUIDv6 extension. It is a package for Elixir projects, and can
be found on Hex as `:uniq`.

## Features

* Follows the RFC 4122 specification, i.e. supports UUID versions 1, 3, 4, and 5 as described in the RFC
* Supports UUIDv6 and UUIDv7, which are described in a proposed extension for RFC 4122, and improve upon desirable traits 
of both UUIDv1 and UUIDv4 to provide the best of both, while removing their downsides.  See 
[here](https://datatracker.ietf.org/doc/html/draft-peabody-dispatch-new-uuid-format) for more information on how it does so.
* Supports formatting UUIDs as canonical strings (e.g. `6ba7b810-9dad-11d1-80b4-00c04fd430c8`, with or without the dashes),
as URNs, e.g. `urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8`, as well as a compact, 22-character, base64-encoded format using
a URI-safe alphabet (e.g. `a6e4EJ2tEdGAtADAT9QwyA`). 
* Case-insensitive, i.e. `6ba7b810-9dad-11d1-80b4-00c04fd430c8` and `6BA7B810-9DAD-11D1-80B4-00C04FD430C8` have the same encoding
* Supports Ecto out of the box, just use `Uniq.UUID` as the type of a field where you would use `Ecto.UUID`. See the docs for more info.
* Can be used as a drop-in replacement for `elixir_uuid`, see the docs for details on migrating

## Installation

```elixir
def deps do
  [
    {:uniq, "~> 0.1"}
  ]
end
```

## Usage

The primary API is provided by the `Uniq.UUID` module.

To generate UUIDs, pick the version you want, and call the appropriate generator. For example:

* `uuid1/0`, generates UUIDv1 and formats it as a human-readable string, i.e. `6ba7b810-9dad-11d1-80b4-00c04fd430c8`
* `uuid1/1`, generates UUIDv1 in the specified format
* `uuid3/2`, generates UUIDv3 using the provided namespace and name, and formats it as a human-readable string
* `uuid3/3`, generates UUIDv3 using the provided namespace and name, in the specified format

See the [docs](https://hexdocs.pm/uniq) for the full set of functions available.

You can also convert UUID strings to/from the human-readable and binary formats; parse UUID strings/binaries; and determine their validity.
