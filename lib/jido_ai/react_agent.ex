defmodule Jido.AI.ReActAgent do
  @moduledoc """
  Base macro for ReAct-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.ReAct` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.WeatherAgent do
        use Jido.AI.ReActAgent,
          name: "weather_agent",
          description: "Weather Q&A agent",
          tools: [MyApp.Actions.Weather, MyApp.Actions.Forecast],
          system_prompt: "You are a weather expert..."
      end

  ## Options

  - `:name` (required) - Agent name
  - `:tools` (required) - List of `Jido.Action` modules to use as tools
  - `:description` - Agent description (default: "ReAct agent \#{name}")
  - `:system_prompt` - Custom system prompt for the LLM
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:max_iterations` - Maximum reasoning iterations (default: 10)
<<<<<<< HEAD
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)
=======
  - `:tool_context` - Context map passed to all tool executions (e.g., `%{actor: user, domain: MyDomain}`)
  - `:skills` - Additional skills to attach to the agent
>>>>>>> 98e69e0d8033c3fcba2db64262c09a9f6061f1cc

  ## Generated Functions

  - `ask/2` - Convenience function to send a query to the agent
  - `on_before_cmd/2` - Captures last_query before processing
  - `on_after_cmd/3` - Updates last_answer and completed when done

  ## State Fields

  The agent state includes:

  - `:model` - The LLM model being used
  - `:last_query` - The most recent query sent to the agent
  - `:last_answer` - The final answer from the last completed query
  - `:completed` - Boolean indicating if the last query is complete

  ## Task Supervisor

  Each agent instance gets its own Task.Supervisor automatically started via the
  `Jido.AI.Skills.TaskSupervisorSkill`. This supervisor is used for:
  - LLM streaming operations
  - Tool execution
  - Other async operations within the agent's lifecycle

  The supervisor is stored in the skill's internal state (`agent.state.__task_supervisor_skill__`)
  and is accessible via `Jido.AI.Directive.Helper.get_task_supervisor/1`. It is automatically
  cleaned up when the agent terminates.

  ## Example

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.WeatherAgent)
      :ok = MyApp.WeatherAgent.ask(pid, "What's the weather in Tokyo?")

      # Wait for completion, then check result
      agent = Jido.AgentServer.get(pid)
      agent.state.completed   # => true
      agent.state.last_answer # => "The weather in Tokyo is..."
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 10

  defmacro __using__(opts) do
    # Extract all values at compile time (in the calling module's context)
    name = Keyword.fetch!(opts, :name)
    tools = Keyword.fetch!(opts, :tools)
    description = Keyword.get(opts, :description, "ReAct agent #{name}")
    system_prompt = Keyword.get(opts, :system_prompt)
    model = Keyword.get(opts, :model, @default_model)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    # Don't extract tool_context here - it contains AST with module aliases
    # that need to be evaluated in the calling module's context
    skills = Keyword.get(opts, :skills, [])

    # TaskSupervisorSkill is always included for per-instance task supervision
    ai_skills = [Jido.AI.Skills.TaskSupervisorSkill]

    strategy_opts =
      [tools: tools, model: model, max_iterations: max_iterations]
      |> then(fn o -> if system_prompt, do: Keyword.put(o, :system_prompt, system_prompt), else: o end)

    # Build base_schema AST at macro expansion time
    base_schema_ast =
      quote do
        Zoi.object(%{
          __strategy__: Zoi.map() |> Zoi.default(%{}),
          model: Zoi.string() |> Zoi.default(unquote(model)),
          last_query: Zoi.string() |> Zoi.default(""),
          last_answer: Zoi.string() |> Zoi.default(""),
          completed: Zoi.boolean() |> Zoi.default(false)
        })
      end

    # Build strategy_opts inside quote to properly evaluate module references
    quote location: :keep do
      # Build strategy opts at compile time in the calling module's context
      # Access tool_context from opts directly so module aliases are resolved
      # in the calling module's context
      tool_context_value = Keyword.get(unquote(opts), :tool_context, %{})

      strategy_opts =
        [
          tools: unquote(tools),
          model: unquote(model),
          max_iterations: unquote(max_iterations),
          tool_context: tool_context_value
        ]
        |> then(fn o ->
          case unquote(system_prompt) do
            nil -> o
            prompt -> Keyword.put(o, :system_prompt, prompt)
          end
        end)

      use Jido.Agent,
        name: unquote(name),
        description: unquote(description),
        skills: unquote(ai_skills) ++ unquote(skills),
        strategy: {Jido.AI.Strategies.ReAct, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      import Jido.AI.ReActAgent, only: [tools_from_skills: 1]

      @doc """
      Send a query to the agent.

      Returns `:ok` immediately; the result arrives asynchronously via the ReAct loop.
      Check `agent.state.completed` and `agent.state.last_answer` for the result.
      """
      def ask(pid, query) when is_binary(query) do
        signal = Jido.Signal.new!("react.user_query", %{query: query}, source: "/react/agent")
        Jido.AgentServer.cast(pid, signal)
      end

      @impl true
      def on_before_cmd(agent, {:react_start, %{query: query}} = action) do
        agent = %{
          agent
          | state:
              agent.state
              |> Map.put(:last_query, query)
              |> Map.put(:completed, false)
              |> Map.put(:last_answer, "")
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
                    last_answer: snap.result || "",
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

  @doc """
  Extract tool action modules from skills.

  Useful when you want to use skill actions as ReAct tools.

  ## Example

      @skills [MyApp.WeatherSkill, MyApp.LocationSkill]

      use Jido.AI.ReActAgent,
        name: "weather_agent",
        tools: Jido.AI.ReActAgent.tools_from_skills(@skills),
        skills: Enum.map(@skills, & &1.skill_spec(%{}))
  """
  @spec tools_from_skills([module()]) :: [module()]
  def tools_from_skills(skill_modules) when is_list(skill_modules) do
    skill_modules
    |> Enum.flat_map(& &1.actions())
    |> Enum.uniq()
  end
end
