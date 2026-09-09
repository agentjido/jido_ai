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
    package = __CALLER__.module
    facet = Module.concat(package, Agent)
    state_key = :"reasoning_#{strategy}"

    quote do
      use Jido.Plugin, agent: unquote(facet)
      @strategy unquote(strategy)
      def name, do: unquote(Keyword.fetch!(opts, :name))
      def description, do: unquote(Keyword.fetch!(opts, :description))
      def category, do: "ai"
      def tags, do: ["reasoning", Atom.to_string(@strategy), "strategies"]
      def vsn, do: "2.0.0"
      def actions, do: [Jido.AI.Actions.Reasoning.RunStrategy]
      def state_key, do: unquote(state_key)
      def signal_patterns, do: [unquote("reasoning.#{strategy}.run")]

      def signal_routes(_config),
        do: [{hd(signal_patterns()), Jido.AI.Actions.Reasoning.RunCapability}]

      def schema, do: Jido.AI.ReasoningCapability.schema(@strategy, [])

      defmodule unquote(facet) do
        @moduledoc false
        use Jido.Agent.Plugin

        @impl Jido.Agent.Plugin
        def state_spec(opts),
          do: {unquote(state_key), Jido.AI.ReasoningCapability.schema(unquote(strategy), opts)}

        @impl Jido.Agent.Plugin
        def observes(opts), do: [Keyword.get(opts, :into, :result)]

        @impl Jido.Agent.Plugin
        def prepare(preparation, opts),
          do:
            Jido.AI.ReasoningCapability.prepare(
              preparation,
              unquote(package),
              unquote(strategy),
              unquote(state_key),
              opts
            )
      end
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

  def prepare(preparation, package, strategy, state_key, opts) do
    signal = preparation.effective_signal
    current = Map.get(preparation.context, :jido_ai_reasoning_capability)

    selected =
      cond do
        signal.type == "reasoning.#{strategy}.run" ->
          %{
            owner: package,
            strategy: strategy,
            into: Keyword.get(opts, :into, :result),
            key: state_key,
            defaults: preparation.plugin_state
          }

        owned_binding?(current, signal) ->
          current

        true ->
          nil
      end

    Jido.AI.Capability.bind(preparation, :jido_ai_reasoning_capability, selected)
  end

  defp owned_binding?(%{owner: owner, strategy: strategy}, signal) do
    @plugins[owner] == strategy and signal.type == "reasoning.#{strategy}.run"
  end

  defp owned_binding?(_, _), do: false
end
