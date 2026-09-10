defmodule Jido.AI.ReasoningCapability do
  @moduledoc false
  defmacro __using__(opts) do
    strategy = Keyword.fetch!(opts, :strategy)
    package = __CALLER__.module
    facet = Module.concat(package, Agent)
    server_facet = Module.concat(package, AgentServer)
    state_key = :"reasoning_#{strategy}"

    quote do
      use Jido.Plugin, agent: unquote(facet), agent_server: unquote(server_facet)
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
      end

      defmodule unquote(server_facet) do
        @moduledoc false
        use Jido.AgentServer.Plugin

        @impl Jido.AgentServer.Plugin
        def admit(_runtime, command, opts),
          do:
            Jido.AI.ReasoningCapability.prepare_command(
              command,
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

  def prepare_command(command, package, strategy, state_key, opts) do
    signal = command.signal
    current = Map.get(command.context, :jido_ai_reasoning_capability)

    selected =
      if signal.type == "reasoning.#{strategy}.run" do
        %{
          owner: package,
          strategy: strategy,
          into: Keyword.get(opts, :into, :result),
          key: state_key,
          defaults: Map.fetch!(command.agent.state, state_key)
        }
      else
        current
      end

    Jido.AI.Capability.bind(command, :jido_ai_reasoning_capability, selected)
  end
end
