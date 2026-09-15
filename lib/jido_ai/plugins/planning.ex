defmodule Jido.AI.Plugins.Planning do
  @moduledoc """
  Planning defaults for explicit core Agent routes.

  Declare this Plugin with keyword options `default_model`, `default_max_tokens`,
  `default_temperature` and `into` (default `:result`). Declare the three routes
  to `Jido.AI.Actions.Planning.RunCapability`, or use `signal_routes/1` in a source
  map. Direct Actions keep their result maps. The route Action stores that result
  in the declared domain field and returns the complete Agent state.
  """
  use Jido.Plugin, agent: Jido.AI.Plugins.Planning.Agent

  alias Jido.AI.Actions.Planning.{Plan, Decompose, Prioritize}

  @routes %{
    "planning.plan" => Plan,
    "planning.decompose" => Decompose,
    "planning.prioritize" => Prioritize
  }
  @defaults %{default_model: :planning, default_max_tokens: 4096, default_temperature: 0.7}

  def name, do: "planning"
  def description, do: "Provides AI-powered planning, goal decomposition, and task prioritization"
  def category, do: "ai"
  def tags, do: ["planning", "decomposition", "prioritization", "ai"]
  def vsn, do: "1.0.0"
  def state_key, do: :planning
  def actions, do: [Plan, Decompose, Prioritize]
  def signal_patterns, do: ["planning.plan", "planning.decompose", "planning.prioritize"]

  def signal_routes(_config),
    do: Enum.map(signal_patterns(), &{&1, Jido.AI.Actions.Planning.RunCapability})

  def schema, do: state_schema(@defaults) |> Zoi.default(@defaults)

  @doc false
  def agent_state_spec(opts) do
    Jido.AI.PluginConfig.validate!(
      opts,
      [:default_model, :default_max_tokens, :default_temperature, :into],
      "Planning"
    )

    into = Keyword.get(opts, :into, :result)

    unless is_atom(into) and not is_nil(into),
      do: raise(ArgumentError, "into must be a field atom")

    case Zoi.parse(schema(), opts |> Keyword.delete(:into) |> Map.new()) do
      {:ok, defaults} -> {:planning, state_schema(defaults) |> Zoi.default(defaults)}
      {:error, errors} -> raise ArgumentError, "Invalid Planning defaults: #{inspect(errors)}"
    end
  end

  @doc false
  def prepare_input(preparation, opts) do
    binding =
      if action = @routes[preparation.signal.type] do
        %{
          action: action,
          key: :planning,
          into: Keyword.get(opts, :into, :result),
          defaults: preparation.plugin_state
        }
      end

    {:ok, binding}
  end

  defp state_schema(defaults) do
    Zoi.object(%{
      default_model: Zoi.any() |> Zoi.default(defaults.default_model),
      default_max_tokens: Zoi.integer() |> Zoi.min(1) |> Zoi.default(defaults.default_max_tokens),
      default_temperature: Zoi.float() |> Zoi.min(0) |> Zoi.max(2) |> Zoi.default(defaults.default_temperature)
    })
  end
end
