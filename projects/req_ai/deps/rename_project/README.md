## Rename Project

Rename your Elixir Project

## Install

Add to your mix dependencies in `mix.exs`

```elixir
# mix.exs
defp deps do
  [
    {:rename_project, "~> 0.1.0", only: :dev}
  ]
end
```

## Usage

Commit your files before running the rename task in case it goes wrong.

```bash
mix rename OldName NewName
```
