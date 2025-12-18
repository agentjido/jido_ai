# ProperCase

An Elixir library that converts keys in maps between `snake_case` and `camelCase`.

Useful as a plug in Phoenix for converting incoming params from JavaScript's `camelCase` to Elixir's `snake_case`

Converts all keys in  maps to snake case
`ProperCase.to_snake_case/1`

Converts all keys in maps to camel case
`ProperCase.to_camel_case/1`

Converts a string to snake case
`ProperCase.snake_case/1`

Converts a string to camel case
`ProperCase.camel_case/1`


## Documentation

API documentation is available at https://hexdocs.pm/proper_case


## Usage


### Example
`ProperCase.to_snake_case`
```elixir
# Before:
%{"user" => %{
    "firstName" => "Han",
    "lastName" => "Solo",
    "alliesInCombat" => [
      %{"name" => "Luke", "weaponOfChoice" => "lightsaber"},
      %{"name" => "Chewie", "weaponOfChoice" => "bowcaster"},
      %{"name" => "Leia", "weaponOfChoice" => "blaster"}
    ]
  }
}

# After:
%{"user" => %{
    "first_name" => "Han",
    "last_name" => "Solo",
    "allies_in_combat" => [
      %{"name" => "Luke", "weapon_of_choice" => "lightsaber"},
      %{"name" => "Chewie", "weapon_of_choice" => "bowcaster"},
      %{"name" => "Leia", "weapon_of_choice" => "blaster"}
    ]
  }
}
```


### Using as a plug in Phoenix

`ProperCase` is extremely useful as a part of your connection pipeline, converting incoming params from
JavaScript's `camelCase` to Elixir's `snake_case`

Plug it into your `router.ex` connection pipeline like so:

```elixir
  pipeline :api do
    plug :accepts, ["json"]
    plug ProperCase.Plug.SnakeCaseParams
  end
```

### camelCase before encoding json in Phoenix

Set Phoenix's json encoder in `config/config.exs`. This way, ProperCase will camelCase your data before encoding to JSON:

```elixir
config :phoenix, :format_encoders, json: ProperCase.JSONEncoder.CamelCase
```

### Custom data transform before encoding with Phoenix

To ensure that outgoing params are converted to `camelCase`, define a custom JSON encoder that runs a transform before encoding to json.

```elixir
defmodule MyApp.CustomJSONEncoder do
  use ProperCase.JSONEncoder,
  transform: &ProperCase.to_camel_case/1,
  json_encoder: Poison  # optional, to use Posion instead of Jason
end
```

config.exs

```elixir
config :phoenix, :format_encoders, json: MyApp.CustomJSONEncoder
```


## Installation

ProperCase is available on hex.pm, and can be installed as:

  1. Add proper_case to your list of dependencies in `mix.exs`:
```
        def deps do
          [{:proper_case, "~> 1.0.2"}]
        end
```
  2. For Elixir versions < 1.5: ensure proper_case is started before your application:
```
        def application do
          [applications: [:proper_case]]
        end
```



## Contributors

- [Johnny Ji](https://github.com/johnnyji)
- [Shaun Dern](https://github.com/smdern)
