defmodule Jido.AI.GoTAgent do
  @moduledoc """
  Base macro for Graph-of-Thoughts-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.GraphOfThoughts` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.ResearchSynthesizer do
        use Jido.AI.GoTAgent,
          name: "research_synthesizer",
          description: "Synthesizes research from multiple perspectives",
          max_nodes: 30,
          max_depth: 6,
          aggregation_strategy: :synthesis
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "GoT agent \#{name}")
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:max_nodes` - Maximum number of nodes in the graph (default: 20)
  - `:max_depth` - Maximum depth of the graph (default: 5)
  - `:aggregation_strategy` - `:voting`, `:weighted`, or `:synthesis` (default: `:synthesis`)
  - `:generation_prompt` - Custom prompt for thought generation
  - `:connection_prompt` - Custom prompt for finding connections
  - `:aggregation_prompt` - Custom prompt for aggregation
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `explore/2` - Convenience function to start a GoT exploration
  - `strategy_opts/0` - Returns the strategy options for CLI access
  - `on_before_cmd/2` - Captures last_prompt before processing
  - `on_after_cmd/3` - Updates last_result and completed when done

  ## State Fields

  The agent state includes:

  - `:model` - The LLM model being used
  - `:last_prompt` - The most recent prompt sent to the agent
  - `:last_result` - The final result from the last completed exploration
  - `:completed` - Boolean indicating if the last exploration is complete

  ## Task Supervisor

  Each agent instance gets its own Task.Supervisor automatically started via the
  `Jido.AI.Skills.TaskSupervisorSkill`. This supervisor is used for:
  - LLM streaming operations
  - Other async operations within the agent's lifecycle

  ## Example

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.ResearchSynthesizer)
      :ok = MyApp.ResearchSynthesizer.explore(pid, "Analyze the impact of AI on healthcare")

      # Wait for completion, then check result
      agent = Jido.AgentServer.get(pid)
      agent.state.completed   # => true
      agent.state.last_result # => "Based on multiple perspectives..."

  ## Aggregation Strategies

  - `:voting` - Selects the most common conclusion among thoughts
  - `:weighted` - Weights thoughts by their scores when aggregating
  - `:synthesis` - Synthesizes all thoughts into a coherent conclusion (default)
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_nodes 20
  @default_max_depth 5
  @default_aggregation_strategy :synthesis

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "GoT agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    max_nodes = Keyword.get(opts, :max_nodes, @default_max_nodes)
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    aggregation_strategy = Keyword.get(opts, :aggregation_strategy, @default_aggregation_strategy)
    generation_prompt = Keyword.get(opts, :generation_prompt)
    connection_prompt = Keyword.get(opts, :connection_prompt)
    aggregation_prompt = Keyword.get(opts, :aggregation_prompt)
    skills = Keyword.get(opts, :skills, [])

    ai_skills = [Jido.AI.Skills.TaskSupervisorSkill]

    strategy_opts =
      [
        model: model,
        max_nodes: max_nodes,
        max_depth: max_depth,
        aggregation_strategy: aggregation_strategy
      ]
      |> then(fn o ->
        if generation_prompt, do: Keyword.put(o, :generation_prompt, generation_prompt), else: o
      end)
      |> then(fn o ->
        if connection_prompt, do: Keyword.put(o, :connection_prompt, connection_prompt), else: o
      end)
      |> then(fn o ->
        if aggregation_prompt, do: Keyword.put(o, :aggregation_prompt, aggregation_prompt), else: o
      end)

    base_schema_ast =
      quote do
        Zoi.object(%{
          __strategy__: Zoi.map() |> Zoi.default(%{}),
          model: Zoi.string() |> Zoi.default(unquote(model)),
          last_prompt: Zoi.string() |> Zoi.default(""),
          last_result: Zoi.string() |> Zoi.default(""),
          completed: Zoi.boolean() |> Zoi.default(false)
        })
      end

    quote location: :keep do
      use Jido.Agent,
        name: unquote(name),
        description: unquote(description),
        skills: unquote(ai_skills) ++ unquote(skills),
        strategy: {Jido.AI.Strategies.GraphOfThoughts, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      @doc """
      Returns the strategy options configured for this agent.
      Used by the CLI adapter to inspect configuration.
      """
      def strategy_opts, do: unquote(Macro.escape(strategy_opts))

      @doc """
      Start a Graph-of-Thoughts exploration with the given prompt.

      Returns `:ok` immediately; the result arrives asynchronously via the GoT loop.
      Check `agent.state.completed` and `agent.state.last_result` for the result.
      """
      def explore(pid, prompt) when is_binary(prompt) do
        signal = Jido.Signal.new!("got.query", %{prompt: prompt}, source: "/got/agent")
        Jido.AgentServer.cast(pid, signal)
      end

      @impl true
      def on_before_cmd(agent, {:got_start, %{prompt: prompt}} = action) do
        agent = %{
          agent
          | state:
              agent.state
              |> Map.put(:last_prompt, prompt)
              |> Map.put(:completed, false)
              |> Map.put(:last_result, "")
        }

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, _action, directives) do
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            %{
              agent
              | state:
                  Map.merge(agent.state, %{
                    last_result: snap.result || "",
                    completed: true
                  })
            }
          else
            agent
          end

        {:ok, agent, directives}
      end

      defoverridable on_before_cmd: 2, on_after_cmd: 3
    end
  end
end
