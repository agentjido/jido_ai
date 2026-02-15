defmodule Jido.AI.Strategies.Adaptive do
  @moduledoc """
  Adaptive execution strategy that automatically selects the best reasoning approach.

  This strategy analyzes task characteristics and selects the most appropriate
  strategy (CoT, ReAct, ToT, GoT) for the given task. The strategy is re-evaluated
  when the previous reasoning completes and a new prompt arrives.

  ## Overview

  The Adaptive strategy:
  - Analyzes prompt complexity and task type
  - Selects the appropriate strategy based on heuristics
  - Delegates all operations to the selected strategy
  - Re-evaluates strategy when previous task completes
  - Supports manual override via configuration

  ## Strategy Selection

  Strategies are selected based on task type keywords and complexity:

  ### Task Type Detection (highest priority)
  - **Iterative Reasoning** → TRM (Tiny-Recursive-Model)
    - Keywords: puzzle, solve, step-by-step, iterate, improve, refine, recursive
  - **Synthesis** → Graph-of-Thoughts (GoT)
    - Keywords: synthesize, combine, merge, integrate, relationships, perspectives
  - **Tool use** → ReAct
    - Keywords: search, find, calculate, execute, fetch
  - **Exploration** → Tree-of-Thoughts (ToT)
    - Keywords: analyze, explore, compare, evaluate, alternatives

  ### Complexity-based Selection (fallback)
  - **Simple tasks** (score < 0.3) → Chain-of-Thought (CoT)
    - Direct questions, simple calculations, factual queries
  - **Moderate tasks** (0.3-0.7) → ReAct
    - Tasks requiring tool use, multi-step operations
  - **Complex tasks** (> 0.7) → Tree-of-Thoughts (ToT)
    - Puzzles, planning, creative writing, complex reasoning

  ## Configuration

  Configure via strategy options when defining your agent:

      use Jido.Agent,
        name: "my_adaptive_agent",
        strategy: {
          Jido.AI.Strategies.Adaptive,
          model: "anthropic:claude-sonnet-4-20250514",
          default_strategy: :react,
          available_strategies: [:cot, :react, :tot, :got, :trm]
        }

  ### Options

  - `:model` (optional) - Model identifier passed to selected strategy
  - `:default_strategy` (optional) - Default strategy if analysis is inconclusive, defaults to `:react`
  - `:strategy` (optional) - Manual override to force a specific strategy
  - `:available_strategies` (optional) - List of available strategies, defaults to [:cot, :react, :tot]
  - `:complexity_thresholds` (optional) - Map of thresholds for strategy selection

  ## Signal Routing

  Signal routes are delegated to the selected strategy. Before a strategy is
  selected, the adaptive strategy handles the initial routing.

  ## State

  State includes the selected strategy module and its state.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Strategies.ChainOfThought
  alias Jido.AI.Strategies.GraphOfThoughts
  alias Jido.AI.Strategies.ReAct
  alias Jido.AI.Strategies.TreeOfThoughts
  alias Jido.AI.Strategies.TRM

  @default_model "anthropic:claude-haiku-4-5"
  @default_strategy :react

  # Strategy module mapping
  @strategy_modules %{
    cot: ChainOfThought,
    react: ReAct,
    tot: TreeOfThoughts,
    got: GraphOfThoughts,
    trm: TRM
  }

  # Default complexity thresholds
  @default_thresholds %{
    simple: 0.3,
    complex: 0.7
  }

  # Keywords that suggest specific strategies
  @tool_keywords ~w(search find lookup fetch get calculate compute call execute run use tool)
  @complex_keywords ~w(analyze explore consider multiple options alternatives compare contrast evaluate)
  @simple_keywords ~w(what is who when where define explain tell me)
  # Keywords that suggest graph-based reasoning (GoT)
  @synthesis_keywords ~w(synthesize combine merge integrate aggregate unify consolidate)
  @graph_keywords ~w(relationships connections network graph linked interdependent perspectives viewpoints)
  # Keywords that suggest iterative reasoning (TRM)
  # Note: multi-word keywords use spaces, and we check for both with and without hyphens
  @puzzle_keywords ~w(puzzle iterate improve refine recursive riddle)

  @type complexity :: :simple | :moderate | :complex
  @type strategy_type :: :cot | :react | :tot | :got | :trm

  @type config :: %{
          optional(:model) => String.t(),
          optional(:default_strategy) => strategy_type(),
          optional(:available_strategies) => [strategy_type()],
          optional(:complexity_thresholds) => map(),
          optional(:strategy_opts) => keyword()
        }

  # Action atoms - we use generic ones that work across strategies
  @start :adaptive_start
  @llm_result :adaptive_llm_result
  @llm_partial :adaptive_llm_partial
  @request_error :adaptive_request_error

  @doc "Returns the action atom for starting an adaptive exploration."
  @spec start_action() :: :adaptive_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :adaptive_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling streaming LLM partial tokens."
  @spec llm_partial_action() :: :adaptive_llm_partial
  def llm_partial_action, do: @llm_partial

  @doc "Returns the action atom for handling request rejection events."
  @spec request_error_action() :: :adaptive_request_error
  def request_error_action, do: @request_error

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string(), request_id: Zoi.string() |> Zoi.optional()}),
      doc: "Start adaptive reasoning with automatic strategy selection",
      name: "adaptive.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response (delegated to selected strategy)",
      name: "adaptive.llm_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token chunk (delegated to selected strategy)",
      name: "adaptive.llm_partial"
    },
    @request_error => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom(),
          message: Zoi.string()
        }),
      doc: "Handle request lifecycle rejection (delegated to selected strategy)",
      name: "adaptive.request_error"
    }
  }

  @impl true
  def action_spec(action) do
    Map.get(@action_specs, action)
  end

  @impl true
  def signal_routes(_ctx) do
    # Base routes for adaptive strategy
    # Once a strategy is selected, its routes will be merged
    [
      {"ai.adaptive.query", {:strategy_cmd, @start}},
      {"ai.llm.response", {:strategy_cmd, @llm_result}},
      {"ai.llm.delta", {:strategy_cmd, @llm_partial}},
      {"ai.request.error", {:strategy_cmd, @request_error}},
      # Usage report is emitted for observability but doesn't need processing
      {"ai.usage", Jido.Actions.Control.Noop}
    ]
  end

  @impl true
  def snapshot(%Agent{} = agent, ctx) do
    state = StratState.get(agent, %{})

    case state[:selected_strategy] do
      nil ->
        %Jido.Agent.Strategy.Snapshot{
          status: :idle,
          done?: false,
          result: nil,
          details: %{
            phase: :awaiting_selection,
            available_strategies: state[:available_strategies] || []
          }
        }

      strategy_module ->
        # Delegate to selected strategy
        strategy_module.snapshot(agent, ctx)
    end
  end

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(ctx)

    state = %{
      config: config,
      selected_strategy: nil,
      strategy_type: nil,
      available_strategies: config.available_strategies,
      complexity_score: nil,
      task_type: nil
    }

    agent = StratState.put(agent, state)
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) do
    state = StratState.get(agent, %{})

    case state[:selected_strategy] do
      nil ->
        # Strategy not yet selected - handle start instruction
        handle_initial_instruction(agent, instructions, ctx, state)

      strategy_module ->
        # Check if we should re-evaluate strategy for a new task
        if should_reevaluate?(agent, instructions, ctx, strategy_module) do
          # Previous reasoning is complete, re-evaluate for new prompt
          handle_initial_instruction(agent, instructions, ctx, state)
        else
          # Delegate to selected strategy
          delegate_cmd(agent, instructions, ctx, strategy_module, state)
        end
    end
  end

  # Check if we should re-evaluate strategy selection
  defp should_reevaluate?(agent, instructions, ctx, strategy_module) do
    # Only re-evaluate if there's a new start instruction
    has_start =
      Enum.any?(instructions, fn
        %{action: @start} -> true
        %{action: action} when action in [:cot_start, :ai_react_start, :tot_start, :got_start, :trm_start] -> true
        _ -> false
      end)

    if has_start do
      # Check if previous reasoning is complete
      snapshot = strategy_module.snapshot(agent, ctx)
      snapshot.done? == true
    else
      false
    end
  end

  # Public API

  @doc """
  Analyzes a prompt and returns the recommended strategy.
  """
  def analyze_prompt(prompt, config \\ %{}) do
    thresholds = Map.get(config, :complexity_thresholds, @default_thresholds)
    available = Map.get(config, :available_strategies, [:cot, :react, :tot, :got, :trm])

    # Calculate complexity score
    complexity_score = calculate_complexity(prompt)

    # Detect task type from keywords
    task_type = detect_task_type(prompt)

    # Select strategy based on analysis
    strategy = select_strategy(complexity_score, task_type, thresholds, available)

    {strategy, complexity_score, task_type}
  end

  @doc """
  Returns the currently selected strategy for an agent.
  """
  @spec get_selected_strategy(Agent.t()) :: strategy_type() | nil
  def get_selected_strategy(agent) do
    state = StratState.get(agent, %{})
    state[:strategy_type]
  end

  @doc """
  Returns the complexity score for the current task.
  """
  @spec get_complexity_score(Agent.t()) :: float() | nil
  def get_complexity_score(agent) do
    state = StratState.get(agent, %{})
    state[:complexity_score]
  end

  # Private Helpers

  defp build_config(ctx) do
    opts = ctx[:strategy_opts] || []

    raw_model = Keyword.get(opts, :model, @default_model)
    resolved_model = resolve_model_spec(raw_model)

    %{
      model: resolved_model,
      default_strategy: Keyword.get(opts, :default_strategy, @default_strategy),
      available_strategies: Keyword.get(opts, :available_strategies, [:cot, :react, :tot, :got, :trm]),
      complexity_thresholds: Keyword.get(opts, :complexity_thresholds, @default_thresholds),
      strategy_override: Keyword.get(opts, :strategy),
      strategy_opts: opts
    }
  end

  defp resolve_model_spec(model) when is_atom(model) do
    Jido.AI.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp handle_initial_instruction(agent, instructions, ctx, state) do
    # Find the start instruction
    start_instr =
      Enum.find(instructions, fn
        %{action: @start} -> true
        %{action: action} when action in [:cot_start, :ai_react_start, :tot_start, :got_start, :trm_start] -> true
        _ -> false
      end)

    case start_instr do
      nil ->
        # No start instruction, return unchanged
        {agent, []}

      %{params: params} ->
        prompt = Map.get(params, :prompt) || Map.get(params, "prompt") || ""

        # Select strategy
        {strategy_type, complexity_score, task_type} =
          select_strategy_for_task(prompt, state[:config])

        strategy_module = Map.get(@strategy_modules, strategy_type)

        # Initialize the selected strategy
        strategy_ctx = Map.put(ctx, :strategy_opts, state[:config].strategy_opts)
        {agent, _init_directives} = strategy_module.init(agent, strategy_ctx)

        # Now delegate the start instruction to the selected strategy
        # Map the adaptive action to the strategy-specific action
        mapped_instructions = map_instructions(instructions, strategy_type)
        {agent, directives} = strategy_module.cmd(agent, mapped_instructions, ctx)

        # After cmd, re-merge our adaptive metadata
        agent = merge_adaptive_state(agent, strategy_module, strategy_type, complexity_score, task_type, state)

        {agent, directives}
    end
  end

  defp delegate_cmd(agent, instructions, ctx, strategy_module, state) do
    # Map adaptive actions to strategy-specific actions
    strategy_type = state[:strategy_type]
    mapped_instructions = map_instructions(instructions, strategy_type)
    {agent, directives} = strategy_module.cmd(agent, mapped_instructions, ctx)

    # Re-merge adaptive state after delegation
    complexity_score = state[:complexity_score]
    task_type = state[:task_type]
    agent = merge_adaptive_state(agent, strategy_module, strategy_type, complexity_score, task_type, state)

    {agent, directives}
  end

  defp merge_adaptive_state(agent, strategy_module, strategy_type, complexity_score, task_type, adaptive_state) do
    # Get the current strategy state
    strategy_state = StratState.get(agent, %{})

    # Merge our adaptive tracking fields into the strategy's state
    merged_state =
      Map.merge(strategy_state, %{
        selected_strategy: strategy_module,
        strategy_type: strategy_type,
        complexity_score: complexity_score,
        task_type: task_type,
        available_strategies: adaptive_state[:available_strategies],
        adaptive_config: adaptive_state[:config]
      })

    StratState.put(agent, merged_state)
  end

  defp map_instructions(instructions, strategy_type) do
    Enum.map(instructions, fn instr ->
      # Normalize instruction to map form
      instr_map = normalize_instruction(instr)

      # Map adaptive actions to strategy-specific actions
      mapped_action =
        case instr_map.action do
          @start -> start_action_for(strategy_type)
          @llm_result -> llm_result_action_for(strategy_type)
          @llm_partial -> llm_partial_action_for(strategy_type)
          @request_error -> request_error_action_for(strategy_type)
          other -> other
        end

      # Map params for strategy-specific requirements
      mapped_params = map_params_for_strategy(instr_map.params || %{}, strategy_type, instr_map.action)

      # Convert to Jido.Instruction struct for delegated strategy
      %Jido.Instruction{
        action: mapped_action,
        params: mapped_params
      }
    end)
  end

  # All strategies now use :prompt consistently
  defp map_params_for_strategy(params, _strategy_type, _action), do: params

  defp normalize_instruction(%Jido.Instruction{} = instr) do
    %{action: instr.action, params: instr.params}
  end

  defp normalize_instruction(%{action: action, params: params}) do
    %{action: action, params: params}
  end

  defp normalize_instruction(%{action: action}) do
    %{action: action, params: %{}}
  end

  defp start_action_for(:cot), do: :cot_start
  defp start_action_for(:react), do: :ai_react_start
  defp start_action_for(:tot), do: :tot_start
  defp start_action_for(:got), do: :got_start
  defp start_action_for(:trm), do: :trm_start

  defp llm_result_action_for(:cot), do: :cot_llm_result
  defp llm_result_action_for(:react), do: :ai_react_llm_result
  defp llm_result_action_for(:tot), do: :tot_llm_result
  defp llm_result_action_for(:got), do: :got_llm_result
  defp llm_result_action_for(:trm), do: :trm_llm_result

  defp llm_partial_action_for(:cot), do: :cot_llm_partial
  defp llm_partial_action_for(:react), do: :ai_react_llm_partial
  defp llm_partial_action_for(:tot), do: :tot_llm_partial
  defp llm_partial_action_for(:got), do: :got_llm_partial
  defp llm_partial_action_for(:trm), do: :trm_llm_partial

  defp request_error_action_for(:cot), do: :cot_request_error
  defp request_error_action_for(:react), do: :ai_react_request_error
  defp request_error_action_for(:tot), do: :tot_request_error
  defp request_error_action_for(:got), do: :got_request_error
  defp request_error_action_for(:trm), do: :trm_request_error

  defp select_strategy_for_task(prompt, config) do
    # Check for manual override
    case config[:strategy_override] do
      nil ->
        analyze_prompt(prompt, config)

      override when is_atom(override) ->
        # Manual override - return with neutral score
        {override, 0.5, :manual_override}
    end
  end

  defp calculate_complexity(prompt) do
    # Normalize prompt
    prompt_lower = String.downcase(prompt)
    words = String.split(prompt_lower, ~r/\s+/)
    word_count = length(words)

    # Base complexity from length
    length_score = min(word_count / 100, 1.0) * 0.3

    # Complexity from sentence structure
    sentence_count = length(String.split(prompt, ~r/[.!?]+/)) - 1
    structure_score = min(sentence_count / 5, 1.0) * 0.2

    # Complexity from keywords
    complex_keyword_count =
      Enum.count(@complex_keywords, fn kw ->
        String.contains?(prompt_lower, kw)
      end)

    keyword_score = min(complex_keyword_count / 3, 1.0) * 0.3

    # Complexity from questions and constraints
    question_count = length(Regex.scan(~r/\?/, prompt))
    constraint_patterns = ~r/(must|should|need to|have to|require)/i
    constraint_count = length(Regex.scan(constraint_patterns, prompt))
    constraint_score = min((question_count + constraint_count) / 5, 1.0) * 0.2

    # Total score
    min(length_score + structure_score + keyword_score + constraint_score, 1.0)
  end

  defp detect_task_type(prompt) do
    prompt_lower = String.downcase(prompt)

    cond do
      # Iterative reasoning/puzzle tasks prefer TRM
      has_puzzle_keywords?(prompt_lower) ->
        :iterative_reasoning

      # Synthesis/graph tasks prefer GoT
      has_synthesis_keywords?(prompt_lower) ->
        :synthesis

      has_tool_keywords?(prompt_lower) ->
        :tool_use

      has_complex_keywords?(prompt_lower) ->
        :exploration

      has_simple_keywords?(prompt_lower) ->
        :simple_query

      true ->
        :general
    end
  end

  defp has_tool_keywords?(prompt) do
    Enum.any?(@tool_keywords, &String.contains?(prompt, &1))
  end

  defp has_complex_keywords?(prompt) do
    Enum.any?(@complex_keywords, &String.contains?(prompt, &1))
  end

  defp has_simple_keywords?(prompt) do
    Enum.any?(@simple_keywords, &String.contains?(prompt, &1))
  end

  defp has_synthesis_keywords?(prompt) do
    Enum.any?(@synthesis_keywords, &String.contains?(prompt, &1)) or
      Enum.any?(@graph_keywords, &String.contains?(prompt, &1))
  end

  defp has_puzzle_keywords?(prompt) do
    Enum.any?(@puzzle_keywords, &String.contains?(prompt, &1))
  end

  defp select_strategy(complexity_score, task_type, thresholds, available) do
    # First, check task type overrides
    strategy = select_by_task_type(task_type, available)

    # If no task-type override, use complexity score
    strategy = strategy || select_by_complexity(complexity_score, thresholds, available)

    # Final fallback
    strategy || :react
  end

  defp select_by_task_type(:tool_use, available) do
    if :react in available, do: :react
  end

  defp select_by_task_type(:synthesis, available) do
    # Synthesis tasks prefer GoT for combining multiple perspectives
    find_first_available([:got, :tot], available)
  end

  defp select_by_task_type(:exploration, available) do
    # Exploration tasks prefer ToT for branching exploration
    find_first_available([:tot, :got], available)
  end

  defp select_by_task_type(:iterative_reasoning, available) do
    # Iterative reasoning/puzzle tasks prefer TRM for recursive improvement
    find_first_available([:trm, :tot], available)
  end

  defp select_by_task_type(_other, _available), do: nil

  defp select_by_complexity(score, thresholds, available) do
    cond do
      score < thresholds.simple ->
        find_first_available([:cot], available) || List.first(available)

      score > thresholds.complex ->
        find_first_available([:tot, :got], available) || List.first(available)

      true ->
        find_first_available([:react], available) || List.first(available)
    end
  end

  defp find_first_available(preferences, available) do
    Enum.find(preferences, fn pref -> pref in available end)
  end
end
