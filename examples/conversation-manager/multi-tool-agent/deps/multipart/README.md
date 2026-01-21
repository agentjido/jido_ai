# Multipart

[![Hex pm](http://img.shields.io/hexpm/v/multipart.svg?style=flat)](https://hex.pm/packages/multipart)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/multipart/)

Constructs a multipart message, such an HTTP form data request or multipart email.

# Features

- Follows RFC 2046 and RFC 7578
- Can stream the request body, reducing memory consumption for large request bodies

# Requirements

- Elixir >= 1.10
- Erlang/OTP >= 21

## Installation

Add `multipart` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:multipart, "~> 0.1.0"}
  ]
end
```

## Usage

Typically, you'll use `Multipart` to construct the HTTP body and headers, and use those to build a request in an HTTP client such as [Finch](https://github.com/keathley/finch):

```elixir
multipart =
  Multipart.new()
  |> Multipart.add_part(Part.binary_body("first body"))
  |> Multipart.add_part(Part.binary_body("second body", [{"content-type", "text/plain"}]))
  |> Multipart.add_part(Part.binary_body("<p>third body</p>", [{"content-type", "text/html"}]))

body_stream = Multipart.body_stream(multipart)
content_length = Multipart.content_length(multipart)
content_type = Multipart.content_type(multipart, "multipart/mixed")

headers = [{"Content-Type", content_type}, {"Content-Length", to_string(content_length)}]

Finch.build("POST", "https://example.org/", headers, {:stream, body_stream})
|> Finch.request(MyFinch)
```

You can construct a `multipart/form-data` request using the field helpers in `Path`.

```elixir
multipart =
  Multipart.new()
  |> Multipart.add_part(Part.text_field("field 1 text", :field1))
  |> Multipart.add_part(Part.file_field("/tmp/upload.jpg", :image))

body_stream = Multipart.body_stream(multipart)
content_length = Multipart.content_length(multipart)
content_type = Multipart.content_type(multipart, "multipart/form-data")

headers = [{"Content-Type", content_type}, {"Content-Length", to_string(content_length)}]

Finch.build("POST", "https://example.org/", headers, {:stream, body_stream})
|> Finch.request(MyFinch)
```
