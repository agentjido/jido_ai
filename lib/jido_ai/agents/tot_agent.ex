defmodule Jido.AI.ToTAgent do
  @moduledoc """
  Base macro for Tree-of-Thoughts-powered agents.

  Wraps `use Jido.Agent` with `Jido.AI.Strategies.TreeOfThoughts` wired in,
  plus standard state fields and helper functions.

  ## Usage

      defmodule MyApp.PuzzleSolver do
        use Jido.AI.ToTAgent,
          name: "puzzle_solver",
          description: "Solves complex puzzles using tree exploration",
          branching_factor: 4,
          max_depth: 5,
          traversal_strategy: :best_first
      end

  ## Options

  - `:name` (required) - Agent name
  - `:description` - Agent description (default: "ToT agent \#{name}")
  - `:model` - Model identifier (default: "anthropic:claude-haiku-4-5")
  - `:branching_factor` - Number of thoughts to generate at each node (default: 3)
  - `:max_depth` - Maximum depth of the tree (default: 3)
  - `:traversal_strategy` - `:bfs`, `:dfs`, or `:best_first` (default: `:best_first`)
  - `:generation_prompt` - Custom prompt for thought generation
  - `:evaluation_prompt` - Custom prompt for thought evaluation
  - `:skills` - Additional skills to attach to the agent (TaskSupervisorSkill is auto-included)

  ## Generated Functions

  - `explore/2` - Convenience function to start a ToT exploration
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

      {:ok, pid} = Jido.AgentServer.start(agent: MyApp.PuzzleSolver)
      :ok = MyApp.PuzzleSolver.explore(pid, "Solve the 8-puzzle: [2,8,3,1,6,4,7,_,5]")

      # Wait for completion, then check result
      agent = Jido.AgentServer.get(pid)
      agent.state.completed   # => true
      agent.state.last_result # => "Move tile 5 up..."

  ## Traversal Strategies

  - `:bfs` - Breadth-first search: explores all nodes at current depth before going deeper
  - `:dfs` - Depth-first search: explores deeply before backtracking
  - `:best_first` - Explores highest-scored nodes first (default)
  """

  @default_model "anthropic:claude-haiku-4-5"
  @default_branching_factor 3
  @default_max_depth 3
  @default_traversal_strategy :best_first

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "ToT agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    branching_factor = Keyword.get(opts, :branching_factor, @default_branching_factor)
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    traversal_strategy = Keyword.get(opts, :traversal_strategy, @default_traversal_strategy)
    generation_prompt = Keyword.get(opts, :generation_prompt)
    evaluation_prompt = Keyword.get(opts, :evaluation_prompt)
    skills = Keyword.get(opts, :skills, [])

    ai_skills = [Jido.AI.Skills.TaskSupervisorSkill]

    strategy_opts =
      [
        model: model,
        branching_factor: branching_factor,
        max_depth: max_depth,
        traversal_strategy: traversal_strategy
      ]
      |> then(fn o ->
        if generation_prompt, do: Keyword.put(o, :generation_prompt, generation_prompt), else: o
      end)
      |> then(fn o ->
        if evaluation_prompt, do: Keyword.put(o, :evaluation_prompt, evaluation_prompt), else: o
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
        strategy: {Jido.AI.Strategies.TreeOfThoughts, unquote(Macro.escape(strategy_opts))},
        schema: unquote(base_schema_ast)

      @doc """
      Start a Tree-of-Thoughts exploration with the given prompt.

      Returns `:ok` immediately; the result arrives asynchronously via the ToT loop.
      Check `agent.state.completed` and `agent.state.last_result` for the result.
      """
      def explore(pid, prompt) when is_binary(prompt) do
        signal = Jido.Signal.new!("tot.query", %{prompt: prompt}, source: "/tot/agent")
        Jido.AgentServer.cast(pid, signal)
      end

      @impl true
      def on_before_cmd(agent, {:tot_start, %{prompt: prompt}} = action) do
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
