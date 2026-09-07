defmodule Jido.AI.ReasoningCapability do
  @moduledoc false
  alias Jido.AI.Plugins.Reasoning

  @plugins %{
    Reasoning.ChainOfThought => :cot,
    Reasoning.ChainOfDraft => :cod,
    Reasoning.AlgorithmOfThoughts => :aot,
    Reasoning.TreeOfThoughts => :tot,
    Reasoning.GraphOfThoughts => :got,
    Reasoning.TRM => :trm,
    Reasoning.Adaptive => :adaptive
  }

  defmacro __using__(opts) do
    strategy = Keyword.fetch!(opts, :strategy)

    quote do
      use Jido.Plugin
      @strategy unquote(strategy)
      def name, do: unquote(Keyword.fetch!(opts, :name))
      def description, do: unquote(Keyword.fetch!(opts, :description))
      def category, do: "ai"
      def tags, do: ["reasoning", Atom.to_string(@strategy), "strategies"]
      def vsn, do: "2.0.0"
      def actions, do: [Jido.AI.Actions.Reasoning.RunStrategy]
      def state_key, do: unquote(:"reasoning_#{strategy}")
      def signal_patterns, do: [unquote("reasoning.#{strategy}.run")]

      def signal_routes(_config),
        do: [{hd(signal_patterns()), Jido.AI.Actions.Reasoning.RunCapability}]

      def schema, do: Jido.AI.ReasoningCapability.schema(@strategy, [])

      @impl Jido.Plugin
      def state_spec(opts), do: {state_key(), Jido.AI.ReasoningCapability.schema(@strategy, opts)}

      @impl Jido.Plugin
      def prepare(command, _opts), do: Jido.AI.ReasoningCapability.prepare(command)
    end
  end

  def schema(strategy, opts) do
    Jido.AI.PluginConfig.validate!(
      opts,
      [:default_model, :timeout, :options, :into],
      "Reasoning capability"
    )

    into = Keyword.get(opts, :into, :result)

    unless is_atom(into) and not is_nil(into),
      do: raise(ArgumentError, "into must be a field atom")

    schema = state_schema(strategy, %{default_model: :reasoning, timeout: 30_000, options: %{}})

    case Zoi.parse(schema, opts |> Keyword.delete(:into) |> Map.new()) do
      {:ok, defaults} ->
        state_schema(strategy, defaults) |> Zoi.default(defaults)

      {:error, errors} ->
        raise ArgumentError, "Invalid reasoning capability defaults: #{inspect(errors)}"
    end
  end

  defp state_schema(strategy, defaults) do
    Zoi.object(%{
      strategy: Zoi.enum([strategy]) |> Zoi.default(strategy),
      default_model: Zoi.any() |> Zoi.default(defaults.default_model),
      timeout: Zoi.integer() |> Zoi.min(1) |> Zoi.default(defaults.timeout),
      options: Zoi.map() |> Zoi.default(defaults.options)
    })
  end

  def prepare(command) do
    # Rebuild the binding from all declarations on each call. This also clears
    # caller-supplied bindings on unrelated Signals, in either Plugin order.
    selected =
      Enum.find_value(command.agent.plugins, fn {module, opts} ->
        strategy = @plugins[module]

        if strategy && command.signal.type == "reasoning.#{strategy}.run" do
          key = module.state_key()

          %{
            strategy: strategy,
            into: Keyword.get(opts, :into, :result),
            key: key,
            defaults: Map.fetch!(command.agent.state, key)
          }
        end
      end)

    Jido.AI.Capability.bind(command, :jido_ai_reasoning_capability, selected)
  end
end
