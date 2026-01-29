defmodule Jido.AI.AdaptiveAgent do
  @moduledoc """
  Base macro for Adaptive strategy-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.Adaptive` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.SmartAssistant do
        use Jido.AI.AdaptiveAgent,
          name: "smart_assistant",
          description: "Automatically selects the best reasoning approach",
          default_strategy: :react,
          available_strategies: [:cot, :react, :tot, :got, :trm]
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "Adaptive agent \#{name}")
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:default_strategy` - Default strategy if analysis is inconclusive (default: `:react`)
  - `:available_strategies` - List of available strategies (default: `[:cot, :react, :tot, :got, :trm]`)
  - `:complexity_thresholds` - Map of thresholds for strategy selection
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `ask/2` - Convenience function to send an adaptive query
  - `on_before_cmd/2` - Captures last_prompt before processing
  - `on_after_cmd/3` - Updates last_result and completed when done

  ## State Fields

  The agent state includes:

  - `:model` - The LLM model being used
  - `:last_prompt` - The most recent prompt sent to the agent
  - `:last_result` - The final result from the last completed reasoning
  - `:completed` - Boolean indicating if the last reasoning is complete
  - `:selected_strategy` - The strategy type selected for the current task

  ## Task Supervisor

  Each agent instance gets its own Task.Supervisor automatically started via the
  `Jido.AI.Skills.TaskSupervisorSkill`. This supervisor is used for:
  - LLM streaming operations
  - Other async operations within the agent's lifecycle

  ## Example

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.SmartAssistant)
      :ok = MyApp.SmartAssistant.ask(pid, "Solve this puzzle: ...")

      # Wait for completion, then check result
      agent = Jido.AgentServer.get(pid)
      agent.state.completed        # => true
      agent.state.last_result      # => "The solution is..."
      agent.state.selected_strategy # => :trm

  ## Strategy Selection

  The Adaptive strategy automatically selects the best approach based on task analysis:

  - **Iterative Reasoning** → TRM (puzzles, step-by-step, recursive)
  - **Synthesis** → Graph-of-Thoughts (combine, merge, perspectives)
  - **Tool use** → ReAct (search, calculate, execute)
  - **Exploration** → Tree-of-Thoughts (analyze, compare, alternatives)
  - **Simple tasks** → Chain-of-Thought (direct questions, factual queries)
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_strategy :react
  @default_available_strategies [:cot, :react, :tot, :got, :trm]

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "Adaptive agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    default_strategy = Keyword.get(opts, :default_strategy, @default_strategy)
    available_strategies = Keyword.get(opts, :available_strategies, @default_available_strategies)
    complexity_thresholds = Keyword.get(opts, :complexity_thresholds)
    skills = Keyword.get(opts, :skills, [])

    ai_skills = [Jido.AI.Skills.TaskSupervisorSkill]

    strategy_opts =
      [
        model: model,
        default_strategy: default_strategy,
        available_strategies: available_strategies
      ]
      |> then(fn o ->
        if complexity_thresholds,
          do: Keyword.put(o, :complexity_thresholds, complexity_thresholds),
          else: o
      end)

    base_schema_ast =
      quote do
        Zoi.object(%{
          __strategy__: Zoi.map() |> Zoi.default(%{}),
          model: Zoi.string() |> Zoi.default(unquote(model)),
          last_prompt: Zoi.string() |> Zoi.default(""),
          last_result: Zoi.string() |> Zoi.default(""),
          completed: Zoi.boolean() |> Zoi.default(false),
          selected_strategy: Zoi.atom() |> Zoi.default(nil) |> Zoi.nullable()
        })
      end

    quote location: :keep do
      use Jido.Agent,
        name: unquote(name),
        description: unquote(description),
        skills: unquote(ai_skills) ++ unquote(skills),
        strategy: {Jido.AI.Strategies.Adaptive, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      @doc """
      Returns the strategy options configured for this agent.
      """
      def strategy_opts do
        unquote(Macro.escape(strategy_opts))
      end

      @doc """
      Send an adaptive query to the agent.

      Returns `:ok` immediately; the result arrives asynchronously via the adaptive loop.
      Check `agent.state.completed` and `agent.state.last_result` for the result.
      """
      def ask(pid, prompt) when is_binary(prompt) do
        signal = Jido.Signal.new!("adaptive.query", %{prompt: prompt}, source: "/adaptive/agent")
        Jido.AgentServer.cast(pid, signal)
      end

      @impl true
      def on_before_cmd(agent, {:adaptive_start, %{prompt: prompt}} = action) do
        agent = %{
          agent
          | state:
              agent.state
              |> Map.put(:last_prompt, prompt)
              |> Map.put(:completed, false)
              |> Map.put(:last_result, "")
              |> Map.put(:selected_strategy, nil)
        }

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, _action, directives) do
        snap = strategy_snapshot(agent)

        # Extract selected strategy from strategy state
        strategy_state = Map.get(agent.state, :__strategy__, %{})
        selected_strategy = Map.get(strategy_state, :strategy_type)

        agent =
          if snap.done? do
            %{
              agent
              | state:
                  Map.merge(agent.state, %{
                    last_result: snap.result || "",
                    completed: true,
                    selected_strategy: selected_strategy
                  })
            }
          else
            %{
              agent
              | state: Map.put(agent.state, :selected_strategy, selected_strategy)
            }
          end

        {:ok, agent, directives}
      end

      defoverridable on_before_cmd: 2, on_after_cmd: 3
    end
  end
end
