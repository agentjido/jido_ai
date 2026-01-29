defmodule Jido.AI.TRMAgent do
  @moduledoc """
  Base macro for TRM (Tiny-Recursive-Model) agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.TRM` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.ReasoningAgent do
        use Jido.AI.TRMAgent,
          name: "reasoning_agent",
          description: "Agent that improves answers through recursive reasoning",
          max_supervision_steps: 10,
          act_threshold: 0.95
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "TRM agent \#{name}")
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:max_supervision_steps` - Maximum supervision iterations before termination (default: 5)
  - `:act_threshold` - Confidence threshold for early stopping (default: 0.9)
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `reason/2` - Convenience function to start TRM reasoning
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

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.ReasoningAgent)
      :ok = MyApp.ReasoningAgent.reason(pid, "What is the best approach to solve X?")

      # Wait for completion, then check result
      agent = Jido.AgentServer.get(pid)
      agent.state.completed   # => true
      agent.state.last_result # => "The best approach is..."

  ## TRM Workflow

  TRM uses recursive reasoning to iteratively improve answers:
  1. **Reasoning**: Generate insights about the current answer
  2. **Supervision**: Evaluate the answer and provide feedback with a score
  3. **Improvement**: Apply feedback to generate a better answer
  4. Repeat until confidence threshold is met or max steps reached
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_supervision_steps 5
  @default_act_threshold 0.9

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "TRM agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    max_supervision_steps = Keyword.get(opts, :max_supervision_steps, @default_max_supervision_steps)
    act_threshold = Keyword.get(opts, :act_threshold, @default_act_threshold)
    skills = Keyword.get(opts, :skills, [])

    ai_skills = [Jido.AI.Skills.TaskSupervisorSkill]

    strategy_opts = [
      model: model,
      max_supervision_steps: max_supervision_steps,
      act_threshold: act_threshold
    ]

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
        strategy: {Jido.AI.Strategies.TRM, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      @doc """
      Returns the strategy options for this agent.

      Used by CLI adapters to introspect configuration.
      """
      def strategy_opts do
        unquote(Macro.escape(strategy_opts))
      end

      @doc """
      Start TRM recursive reasoning with the given prompt.

      Returns `:ok` immediately; the result arrives asynchronously via the TRM loop.
      Check `agent.state.completed` and `agent.state.last_result` for the result.
      """
      def reason(pid, prompt) when is_binary(prompt) do
        signal = Jido.Signal.new!("trm.query", %{prompt: prompt}, source: "/trm/agent")
        Jido.AgentServer.cast(pid, signal)
      end

      @impl true
      def on_before_cmd(agent, {:trm_start, %{prompt: prompt}} = action) do
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
