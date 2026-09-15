defmodule Jido.AI.ReasoningCapability do
  @moduledoc false
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

      def schema, do: Jido.AI.ReasoningCapability.schema()

      defmodule unquote(facet) do
        @moduledoc false
        use Jido.Agent.Plugin

        @impl Jido.Agent.Plugin
        def state_spec(opts),
          do: {unquote(state_key), Jido.AI.ReasoningCapability.schema(unquote(strategy), opts)}

        @impl Jido.Agent.Plugin
        def prepare(preparation, opts),
          do:
            Jido.AI.ReasoningCapability.prepare_input(
              preparation,
              unquote(package),
              unquote(strategy),
              unquote(state_key),
              opts
            )
      end
    end
  end

  def schema, do: Zoi.object(%{}, unrecognized_keys: :error) |> Zoi.default(%{})

  def schema(strategy, opts) do
    profile!(strategy, opts)
    schema()
  end

  defp profile!(strategy, opts) do
    Jido.AI.PluginConfig.validate!(opts, [:profile], "Reasoning capability")

    profile =
      case Jido.AI.Actions.Reasoning.RunStrategy.validate_profile(Keyword.get(opts, :profile)) do
        {:ok, profile} -> profile
        {:error, error} -> raise error
      end

    unless Jido.AI.Reasoning.label(profile.reasoning.method) == strategy,
      do: raise(ArgumentError, "Reasoning capability requires method #{strategy}")

    profile
  end

  def prepare_input(preparation, package, strategy, state_key, opts) do
    selected =
      if preparation.signal.type == "reasoning.#{strategy}.run" do
        %{owner: package, profile: profile!(strategy, opts), key: state_key}
      end

    {:ok, selected}
  end
end
