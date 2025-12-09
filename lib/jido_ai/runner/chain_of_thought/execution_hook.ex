defmodule Jido.AI.Runner.ChainOfThought.ExecutionHook do
  @moduledoc """
  Execution hook integration for Chain-of-Thought reasoning.

  Provides helper functions for implementing `on_before_run/1` callback with
  CoT reasoning capabilities. This enables execution analysis before instructions
  are executed, identifying data flow dependencies and potential error points.

  ## Features

  - Execution-time analysis of pending instruction queue
  - Data flow dependency identification between instructions
  - Potential error point detection
  - Context enrichment for post-execution validation
  - Opt-in behavior via `enable_execution_cot` flag

  ## Usage

  Implement `on_before_run/1` callback in your agent:

      defmodule MyAgent do
        use Jido.Agent

        def on_before_run(agent) do
          Jido.AI.Runner.ChainOfThought.ExecutionHook.generate_execution_plan(agent)
        end
      end

  ## Opt-in Behavior

  Enable execution CoT by setting agent state or context flag:

      agent
      |> Jido.Agent.set(:enable_execution_cot, true)
      |> MyAgent.run()

  Or disable it:

      agent
      |> Jido.Agent.set(:enable_execution_cot, false)
      |> MyAgent.run()
  """

  require Logger
  use TypedStruct

  alias Jido.AI.Actions.TextCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias Jido.AI.Runner.ChainOfThought.ErrorHandler

  typedstruct module: ExecutionStep do
    @moduledoc """
    Structured representation of a single execution step.
    """
    field(:index, non_neg_integer(), enforce: true)
    field(:action, String.t(), enforce: true)
    field(:params_summary, String.t(), default: "")
    field(:expected_inputs, list(String.t()), default: [])
    field(:expected_outputs, list(String.t()), default: [])
    field(:depends_on, list(non_neg_integer()), default: [])
  end

  typedstruct module: DataFlowDependency do
    @moduledoc """
    Represents a data flow dependency between execution steps.
    """
    field(:from_step, non_neg_integer(), enforce: true)
    field(:to_step, non_neg_integer(), enforce: true)
    field(:data_key, String.t(), enforce: true)
    field(:dependency_type, atom(), default: :required)
  end

  typedstruct module: ErrorPoint do
    @moduledoc """
    Represents a potential error point in execution.
    """
    field(:step, non_neg_integer(), enforce: true)
    field(:type, atom(), enforce: true)
    field(:description, String.t(), enforce: true)
    field(:mitigation, String.t(), default: "")
  end

  typedstruct module: ExecutionPlan do
    @moduledoc """
    Structured execution plan result.
    """
    field(:steps, list(ExecutionStep.t()), default: [])
    field(:data_flow, list(DataFlowDependency.t()), default: [])
    field(:error_points, list(ErrorPoint.t()), default: [])
    field(:execution_strategy, String.t(), default: "")
    field(:timestamp, DateTime.t(), enforce: true)
  end

  @doc """
  Generates execution plan for pending instructions.

  This is the main entry point for implementing `on_before_run/1` callback.
  It analyzes the pending instruction queue, identifies data flow dependencies,
  and creates an execution plan with potential error points.

  ## Options (via agent state)

  - `:enable_execution_cot` - Enable/disable execution analysis (default: true)
  - `:execution_model` - Model to use for analysis (default: from config)
  - `:execution_temperature` - Temperature for analysis (default: 0.3)

  ## Examples

      def on_before_run(agent) do
        ExecutionHook.generate_execution_plan(agent)
      end

  ## Returns

  - `{:ok, agent}` - Agent with execution plan in state
  - `{:ok, agent}` - Agent unchanged if execution analysis disabled
  - `{:error, reason}` - Error generating execution plan
  """
  @spec generate_execution_plan(map()) :: {:ok, map()} | {:error, term()}
  def generate_execution_plan(agent) do
    if should_generate_execution_plan?(agent) do
      do_generate_execution_plan(agent)
    else
      Logger.debug("Execution CoT disabled via agent state")
      {:ok, agent}
    end
  end

  @doc """
  Checks if execution plan should be generated based on agent state.

  Returns `true` if `enable_execution_cot` is not explicitly set to `false`.

  ## Examples

      iex> should_generate_execution_plan?(%{state: %{enable_execution_cot: true}})
      true

      iex> should_generate_execution_plan?(%{state: %{enable_execution_cot: false}})
      false

      iex> should_generate_execution_plan?(%{state: %{}})
      true
  """
  @spec should_generate_execution_plan?(map()) :: boolean()
  def should_generate_execution_plan?(agent) do
    get_in(agent, [:state, :enable_execution_cot]) != false
  end

  @doc """
  Adds execution plan to agent state for post-execution validation.

  The plan is stored in the agent's state under `:execution_plan` key,
  making it available to `on_after_run` hook for validation.

  ## Examples

      agent = enrich_agent_with_execution_plan(agent, execution_plan)
      plan = get_in(agent, [:state, :execution_plan])
  """
  @spec enrich_agent_with_execution_plan(map(), ExecutionPlan.t()) :: map()
  def enrich_agent_with_execution_plan(agent, execution_plan) do
    current_state = agent.state || %{}
    updated_state = Map.put(current_state, :execution_plan, execution_plan)
    %{agent | state: updated_state}
  end

  @doc """
  Extracts execution plan from agent state.

  Returns the execution plan if available, or error if not present.

  ## Examples

      {:ok, plan} = get_execution_plan(agent)
  """
  @spec get_execution_plan(map()) :: {:ok, ExecutionPlan.t()} | {:error, :no_plan}
  def get_execution_plan(agent) do
    case get_in(agent, [:state, :execution_plan]) do
      %ExecutionPlan{} = plan -> {:ok, plan}
      nil -> {:error, :no_plan}
      _ -> {:error, :invalid_plan}
    end
  end

  # Private Functions

  @spec do_generate_execution_plan(map()) :: {:ok, map()} | {:error, term()}
  defp do_generate_execution_plan(agent) do
    instructions = get_instructions_list(agent)
    instruction_count = length(instructions)

    Logger.info("Generating execution plan for #{instruction_count} instructions")

    if instruction_count == 0 do
      Logger.debug("No instructions to analyze")
      {:ok, agent}
    else
      with {:ok, plan_text} <- generate_plan_text(instructions, agent),
           {:ok, plan} <- parse_plan_text(plan_text, instructions) do
        Logger.debug("Successfully generated execution plan")
        updated_agent = enrich_agent_with_execution_plan(agent, plan)
        {:ok, updated_agent}
      else
        {:error, reason} ->
          Logger.warning("Failed to generate execution plan: #{inspect(reason)}")
          # Return agent unchanged on error (graceful degradation)
          {:ok, agent}
      end
    end
  end

  @spec get_instructions_list(map()) :: list()
  defp get_instructions_list(%{pending_instructions: queue}) when is_tuple(queue) do
    case :queue.is_queue(queue) do
      true -> :queue.to_list(queue)
      false -> []
    end
  end

  defp get_instructions_list(_agent), do: []

  @spec generate_plan_text(list(), map()) :: {:ok, String.t()} | {:error, term()}
  defp generate_plan_text(instructions, agent) do
    with {:ok, prompt} <- build_execution_prompt(instructions, agent),
         {:ok, model} <- get_execution_model(agent) do
      call_llm_for_execution_plan(prompt, model, agent)
    end
  end

  @spec build_execution_prompt(list(), map()) :: {:ok, Jido.AI.Prompt.t()}
  defp build_execution_prompt(instructions, agent) do
    state_summary = summarize_agent_state(agent.state || %{})
    instructions_summary = summarize_instructions(instructions)
    planning_context = get_planning_context(agent)

    template = """
    You are analyzing a sequence of instructions before execution to create an execution plan.

    Current Agent State:
    #{state_summary}

    #{planning_context}

    Pending Instructions:
    #{instructions_summary}

    Create a detailed execution plan analyzing:

    EXECUTION_STRATEGY: Describe the overall execution approach and ordering strategy.

    STEPS:
    For each step, provide:
    - Step number and action name
    - Expected inputs (what data it needs)
    - Expected outputs (what data it produces)
    - Dependencies (which previous steps it depends on)

    DATA_FLOW:
    - Identify data flowing between steps
    - Note which step outputs feed into which step inputs
    - Format: "Step X output 'key' → Step Y input"

    ERROR_POINTS:
    - Identify potential failure points
    - Note missing data or validation issues
    - Suggest mitigations
    - Format: "Step X: [type] description - mitigation"

    Provide clear, structured analysis focused on execution planning.
    """

    prompt = Prompt.new(:user, template)
    {:ok, prompt}
  end

  @spec get_planning_context(map()) :: String.t()
  defp get_planning_context(agent) do
    case get_in(agent, [:state, :planning_cot]) do
      nil ->
        ""

      planning ->
        """
        Planning Context (from on_before_plan):
        Goal: #{Map.get(planning, :goal, "")}
        Analysis: #{Map.get(planning, :analysis, "")}
        """
    end
  end

  @spec get_execution_model(map()) :: {:ok, Model.t()} | {:error, term()}
  defp get_execution_model(agent) do
    model_name =
      get_in(agent, [:state, :execution_model]) ||
        get_in(agent, [:state, :cot_config, :model]) ||
        "gpt-4o"

    Model.from({:openai, model: model_name})
  end

  @spec call_llm_for_execution_plan(Jido.AI.Prompt.t(), Model.t(), map()) ::
          {:ok, String.t()} | {:error, term()}
  defp call_llm_for_execution_plan(prompt, model, agent) do
    temperature =
      get_in(agent, [:state, :execution_temperature]) ||
        get_in(agent, [:state, :cot_config, :temperature]) ||
        0.3

    ErrorHandler.with_retry(
      fn ->
        params = %{
          model: model,
          prompt: prompt,
          temperature: temperature,
          max_tokens: 2000
        }

        case TextCompletion.run(params, %{}) do
          {:ok, %{content: content}, _directives} when is_binary(content) ->
            {:ok, content}

          {:ok, response, _directives} ->
            Logger.warning("Unexpected response format: #{inspect(response)}")
            {:error, :invalid_response}

          {:error, reason} ->
            {:error, reason}
        end
      end,
      max_retries: 2,
      initial_delay_ms: 500
    )
  end

  @spec parse_plan_text(String.t(), list()) :: {:ok, ExecutionPlan.t()} | {:error, term()}
  defp parse_plan_text(text, instructions) do
    execution_strategy = extract_section(text, "EXECUTION_STRATEGY")
    steps = parse_steps_section(text, instructions)
    data_flow = parse_data_flow_section(text)
    error_points = parse_error_points_section(text)

    plan = %ExecutionPlan{
      steps: steps,
      data_flow: data_flow,
      error_points: error_points,
      execution_strategy: execution_strategy,
      timestamp: DateTime.utc_now()
    }

    if execution_strategy == "" and steps == [] do
      {:error, "Missing execution analysis in plan"}
    else
      {:ok, plan}
    end
  end

  @spec parse_steps_section(String.t(), list()) :: list(ExecutionStep.t())
  defp parse_steps_section(text, instructions) do
    # Extract STEPS section
    case Regex.run(~r/STEPS:\s*(.+?)(?=\n[A-Z_]+:|$)/s, text) do
      [_, _content] ->
        # Parse each step from the content
        # TODO: Parse expected_inputs, expected_outputs, depends_on from LLM response
        instructions
        |> Enum.with_index()
        |> Enum.map(fn {instruction, index} ->
          %ExecutionStep{
            index: index,
            action: get_action_name(instruction),
            params_summary: get_params_summary(instruction),
            expected_inputs: [],
            expected_outputs: [],
            depends_on: []
          }
        end)

      _ ->
        # Fallback: create basic steps from instructions
        instructions
        |> Enum.with_index()
        |> Enum.map(fn {instruction, index} ->
          %ExecutionStep{
            index: index,
            action: get_action_name(instruction),
            params_summary: get_params_summary(instruction)
          }
        end)
    end
  end

  @spec parse_data_flow_section(String.t()) :: list(DataFlowDependency.t())
  defp parse_data_flow_section(text) do
    case Regex.run(~r/DATA_FLOW:\s*(.+?)(?=\n[A-Z_]+:|$)/s, text) do
      [_, content] ->
        # Parse data flow lines like "Step X output 'key' → Step Y input"
        ~r/Step\s+(\d+)\s+.*?→\s+Step\s+(\d+)/
        |> Regex.scan(content)
        |> Enum.map(fn [_, from_str, to_str] ->
          %DataFlowDependency{
            from_step: String.to_integer(from_str),
            to_step: String.to_integer(to_str),
            data_key: "data",
            dependency_type: :required
          }
        end)

      _ ->
        []
    end
  end

  @spec parse_error_points_section(String.t()) :: list(ErrorPoint.t())
  defp parse_error_points_section(text) do
    case Regex.run(~r/ERROR_POINTS:\s*(.+?)(?=\n[A-Z_]+:|$)/s, text) do
      [_, content] ->
        # Parse error points like "Step X: [type] description - mitigation"
        ~r/Step\s+(\d+):\s+\[([^\]]+)\]\s+([^-]+)(?:-\s+(.+))?/
        |> Regex.scan(content)
        |> Enum.map(fn
          [_, step_str, type, description, mitigation] ->
            %ErrorPoint{
              step: String.to_integer(step_str),
              type: String.to_atom(String.downcase(String.trim(type))),
              description: String.trim(description),
              mitigation: String.trim(mitigation || "")
            }

          [_, step_str, type, description] ->
            %ErrorPoint{
              step: String.to_integer(step_str),
              type: String.to_atom(String.downcase(String.trim(type))),
              description: String.trim(description),
              mitigation: ""
            }
        end)

      _ ->
        []
    end
  end

  @spec extract_section(String.t(), String.t()) :: String.t()
  defp extract_section(text, section_name) do
    case Regex.run(~r/#{section_name}:\s*(.+?)(?=\n[A-Z_]+:|$)/s, text) do
      [_, content] -> String.trim(content)
      _ -> ""
    end
  end

  @spec summarize_agent_state(map()) :: String.t()
  defp summarize_agent_state(state) when state == %{}, do: "Empty state"

  defp summarize_agent_state(state) do
    state
    |> Map.drop([:planning_cot, :execution_plan, :cot_config])
    |> Enum.map_join("\n", fn {key, value} -> "- #{key}: #{inspect(value, limit: 3)}" end)
  end

  @spec summarize_instructions(list()) :: String.t()
  defp summarize_instructions([]), do: "No instructions"

  defp summarize_instructions(instructions) do
    instructions
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {instruction, index} ->
      action = get_action_name(instruction)
      params = get_params_summary(instruction)
      "#{index}. #{action} with #{params}"
    end)
  end

  @spec get_action_name(term()) :: String.t()
  defp get_action_name(%{action: action}) when is_atom(action) do
    action |> to_string() |> String.replace("Elixir.", "")
  end

  defp get_action_name(%{"action" => action}) when is_binary(action), do: action
  defp get_action_name(_), do: "UnknownAction"

  @spec get_params_summary(term()) :: String.t()
  defp get_params_summary(%{params: params}) when is_map(params) do
    if map_size(params) == 0 do
      "no params"
    else
      keys = Map.keys(params) |> Enum.take(3) |> Enum.map_join(", ", &to_string/1)
      "params: #{keys}"
    end
  end

  defp get_params_summary(%{"params" => params}) when is_map(params) do
    if map_size(params) == 0 do
      "no params"
    else
      keys = Map.keys(params) |> Enum.take(3) |> Enum.map_join(", ", &to_string/1)
      "params: #{keys}"
    end
  end

  defp get_params_summary(_), do: "no params"
end
