# Jido Character

Character schema and API for Jido. 

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `jido_character` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_character, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
character = Jido.Character.new()

character = Jido.Character.update(character, %{name: "John Doe"})

character = Jido.Character.update(character, %{identity: %{username: "johndoe"}})
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jido_character>.


