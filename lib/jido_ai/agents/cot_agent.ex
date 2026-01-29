defmodule Jido.AI.CoTAgent do
  @moduledoc """
  Base macro for Chain-of-Thought-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.ChainOfThought` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.Reasoner do
        use Jido.AI.CoTAgent,
          name: "reasoner",
          description: "Solves problems using step-by-step reasoning",
          model: "anthropic:claude-sonnet-4-20250514"
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "CoT agent \#{name}")
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:system_prompt` - Custom system prompt for CoT reasoning
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `think/2` - Convenience function to start a CoT reasoning session
  - `strategy_opts/0` - Returns the strategy options (for CLI access)
  - `on_before_cmd/2` - Captures last_prompt before processing
  - `on_after_cmd/3` - Updates last_result and completed when done

  ## State Fields

  The agent state includes:

  - `:model` - The LLM model being used
  - `:last_prompt` - The most recent prompt sent to the agent
  - `:last_result` - The final result from the last completed reasoning
  - `:completed` - Boolean indicating if the last reasoning is complete

  ## Task Supervisor

  Each agent instance gets its own Task.Supervisor automatically started via the
  `Jido.AI.Skills.TaskSupervisorSkill`. This supervisor is used for:
  - LLM streaming operations
  - Other async operations within the agent's lifecycle

  ## Example

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.Reasoner)
      :ok = MyApp.Reasoner.think(pid, "What is 15% of 340?")

      # Wait for completion, then check result
      agent = Jido.AgentServer.get(pid)
      agent.state.completed   # => true
      agent.state.last_result # => "Step 1: 15% means 15/100..."
  """

  @default_model "anthropic:claude-haiku-4-5"

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "CoT agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    system_prompt = Keyword.get(opts, :system_prompt)
    skills = Keyword.get(opts, :skills, [])

    ai_skills = [Jido.AI.Skills.TaskSupervisorSkill]

    strategy_opts =
      [model: model]
      |> then(fn o ->
        if system_prompt, do: Keyword.put(o, :system_prompt, system_prompt), else: o
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
        strategy: {Jido.AI.Strategies.ChainOfThought, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      @doc """
      Returns the strategy options configured for this agent.
      """
      def strategy_opts do
        unquote(Macro.escape(strategy_opts))
      end

      @doc """
      Start a Chain-of-Thought reasoning session with the given prompt.

      Returns `:ok` immediately; the result arrives asynchronously via the CoT loop.
      Check `agent.state.completed` and `agent.state.last_result` for the result.
      """
      def think(pid, prompt) when is_binary(prompt) do
        signal = Jido.Signal.new!("cot.query", %{prompt: prompt}, source: "/cot/agent")
        Jido.AgentServer.cast(pid, signal)
      end

      @impl true
      def on_before_cmd(agent, {:cot_start, %{prompt: prompt}} = action) do
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
