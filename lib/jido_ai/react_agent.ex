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
  - `:skills` - Additional skills to attach to the agent

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
    skills = Keyword.get(opts, :skills, [])

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

    quote location: :keep do
      use Jido.Agent,
        name: unquote(name),
        description: unquote(description),
        skills: unquote(skills),
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
        agent = %{agent | state: Map.put(agent.state, :last_query, query)}
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
