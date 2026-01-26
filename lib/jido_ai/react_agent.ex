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
  - `:tool_context` - Context map passed to all tool executions (e.g., `%{actor: user, domain: MyDomain}`)
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `ask/2` or `ask/3` - Convenience function to send a query to the agent (with optional per-request tool_context)
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

  ## Per-Request Tool Context

  You can pass per-request context that will be merged with the agent's base tool_context:

      # Pass actor/tenant for this specific request
      :ok = MyApp.WeatherAgent.ask(pid, "Get my preferences", 
        tool_context: %{actor: current_user, tenant_id: "acme"})
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 10

  @doc false
  def expand_aliases_in_ast(ast, caller_env) do
    Macro.prewalk(ast, fn
      {:__aliases__, _, _} = alias_node ->
        Macro.expand(alias_node, caller_env)

      # Allow literals
      literal when is_atom(literal) or is_binary(literal) or is_number(literal) ->
        literal

      # Allow list syntax
      list when is_list(list) ->
        list

      # Allow map struct syntax: %{...}
      {:%{}, meta, pairs} ->
        {:%{}, meta, pairs}

      # Allow struct syntax: %Module{...}
      {:%, meta, args} ->
        {:%, meta, args}

      # Allow 2-tuples (key-value pairs in maps)
      {key, value} when not is_atom(key) or key not in [:__aliases__, :%, :%{}] ->
        {key, value}

      # Reject function calls and other unsafe constructs
      {func, meta, args} = node when is_atom(func) and is_list(args) ->
        if func in [:__aliases__, :%, :%{}] do
          node
        else
          raise CompileError,
            description:
              "Unsafe construct in tool_context or tools: function call #{inspect(func)} is not allowed. " <>
                "Only module aliases, atoms, strings, numbers, lists, and maps are permitted.",
            line: Keyword.get(meta, :line, 0)
        end

      other ->
        other
    end)
  end

  defmacro __using__(opts) do
    # Extract all values at compile time (in the calling module's context)
    name = Keyword.fetch!(opts, :name)
    tools_ast = Keyword.fetch!(opts, :tools)

    # Expand module aliases in the tools list to actual module atoms
    # This handles {:__aliases__, _, [...]} tuples from macro expansion
    tools =
      Enum.map(tools_ast, fn
        {:__aliases__, _, _} = alias_ast -> Macro.expand(alias_ast, __CALLER__)
        mod when is_atom(mod) -> mod
      end)

    description = Keyword.get(opts, :description, "ReAct agent #{name}")
    system_prompt = Keyword.get(opts, :system_prompt)
    model = Keyword.get(opts, :model, @default_model)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    # Don't extract tool_context here - it contains AST with module aliases
    # that need to be evaluated in the calling module's context
    skills = Keyword.get(opts, :skills, [])

    # TaskSupervisorSkill is always included for per-instance task supervision
    ai_skills = [Jido.AI.Skills.TaskSupervisorSkill]

    # Extract tool_context at macro expansion time
    # Use safe alias-only expansion instead of Code.eval_quoted
    tool_context =
      case Keyword.get(opts, :tool_context) do
        nil ->
          %{}

        {:%, _, _} = map_ast ->
          # It's a struct/map AST - expand aliases safely and evaluate
          expanded_ast = Jido.AI.ReActAgent.expand_aliases_in_ast(map_ast, __CALLER__)
          {evaluated, _} = Code.eval_quoted(expanded_ast, [], __CALLER__)
          evaluated

        {:%{}, _, _} = map_ast ->
          # Plain map AST - expand aliases safely and evaluate
          expanded_ast = Jido.AI.ReActAgent.expand_aliases_in_ast(map_ast, __CALLER__)
          {evaluated, _} = Code.eval_quoted(expanded_ast, [], __CALLER__)
          evaluated

        other when is_map(other) ->
          other
      end

    strategy_opts =
      [tools: tools, model: model, max_iterations: max_iterations, tool_context: tool_context]
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

    quote location: :keep do
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

      ## Options

      - `:tool_context` - Additional context map merged with agent's tool_context for this request
      """
      def ask(pid, query, opts \\ []) when is_binary(query) do
        tool_context = Keyword.get(opts, :tool_context, %{})

        payload =
          if map_size(tool_context) > 0 do
            %{query: query, tool_context: tool_context}
          else
            %{query: query}
          end

        signal = Jido.Signal.new!("react.user_query", payload, source: "/react/agent")
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
