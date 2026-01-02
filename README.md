# Jido AI

Jido AI is an extension of the Jido framework for building AI Agents and Workflows in Elixir. At present, it provides a single action for interacting with Anthropic's Claude models via the Instructor library.

## Installation

```elixir
def deps do
  [
    {:jido, "~> 1.0.0"},
    {:jido_ai, "~> 1.0.0"}
  ]
end
```

## Configuration

You will need to properly configure the `Instructor` library to use the Anthropic adapter:

```elixir
# config/config.exs
config :instructor,
  adapter: Instructor.Adapters.Anthropic,
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY")
  ]
```

## Example

Here's how to use Jido AI with Jido.Workflow to get structured information about US politicians. See the [examples/politician.ex](examples/politician.ex) for more a full example.

```elixir
# Define a simple workflow
defmodule JidoAi.Examples.Politician do
  defmodule Schema do
    use Ecto.Schema
    use Instructor
    @primary_key false
    embedded_schema do
      field(:first_name, :string)
      field(:last_name, :string)

      embeds_many :offices_held, Office, primary_key: false do
        field(:office, Ecto.Enum,
          values: [:president, :vice_president, :governor, :congress, :senate]
        )

        field(:from_date, :date)
        field(:to_date, :date)
      end
    end
  end

  use Jido.Action,
    name: "politician",
    description: "A description of United States Politicians and the offices that they held",
    schema: [
      query: [type: :string, required: true, doc: "The query to search for"]
    ]

  def run(params, _context) do
    # Run the Anthropic ChatCompletion action
    JidoAi.Actions.Anthropic.ChatCompletion.run(
      %{
        model: "claude-3-5-haiku-latest",
        messages: [
          %{
            role: "user",
            content: params.query
          }
        ],
        response_model: Schema,
        temperature: 0.5,
        max_tokens: 1000
      },
      %{}
    )
    |> case do
      {:ok, %{result: politician}} -> {:ok, %{result: politician}}
      {:error, reason} -> {:error, reason}
    end
  end
end

# Run the workflow
iex> {:ok, result} = Jido.Workflow.run(JidoAi.Examples.Politician, %{query: "Tell me about Barack Obama's political career"})
iex> result.result
%JidoAi.Examples.Politician.Schema{
  first_name: "Barack",
  last_name: "Obama",
  offices_held: [
    %JidoAi.Examples.Politician.Schema.Office{
      office: :senate,
      from_date: ~D[2005-01-03],
      to_date: ~D[2008-11-16]
    },
    %JidoAi.Examples.Politician.Schema.Office{
      office: :president,
      from_date: ~D[2009-01-20],
      to_date: ~D[2017-01-20]
    }
  ]
}
```

The example demonstrates how JidoAi can:

- Write Actions that can wrap other Actions
- Use Jido.Workflow to orchestrate AI operations
- Parse natural language queries about politicians
- Return structured data using Ecto schemas
- Handle complex nested data structures
- Provide type validation through Ecto's type system

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jido_ai>.