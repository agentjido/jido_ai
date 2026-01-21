defmodule Jido.AI.Runner.ChainOfThought.ReasoningPrompt do
  @moduledoc """
  Prompt templates for Chain-of-Thought reasoning generation.

  This module provides prompt templates for different CoT reasoning modes:
  - Zero-shot: Simple "Let's think step by step" prompting
  - Few-shot: Reasoning with examples (future)
  - Structured: Task-specific structured reasoning (future)
  """

  alias Jido.AI.Prompt

  @doc """
  Generates a zero-shot reasoning prompt for the given instructions and agent state.

  The zero-shot prompt uses the "Let's think step by step" pattern which has been
  shown to improve reasoning accuracy by 8-15% on complex tasks.

  ## Parameters

  - `instructions` - List of pending instructions to reason about
  - `agent_state` - Current agent state map
  - `opts` - Optional keyword list of options

  ## Returns

  A `%Jido.AI.Prompt{}` struct containing the reasoning prompt.

  ## Example

      iex> instructions = [%{action: MyAction, params: %{value: 42}}]
      iex> state = %{context: "some context"}
      iex> prompt = ReasoningPrompt.zero_shot(instructions, state)
      iex> [message] = prompt.messages
      iex> message.content =~ "Let's think step by step"
      true
  """
  @spec zero_shot(list(), map(), keyword()) :: Prompt.t()
  def zero_shot(instructions, agent_state, _opts \\ []) do
    instruction_count = length(instructions)
    instructions_text = format_instructions(instructions)
    state_text = format_state(agent_state)

    template = """
    You are an AI reasoning assistant helping to plan the execution of agent instructions.
    Your task is to analyze the pending instructions and create a step-by-step reasoning plan
    that will guide their execution.

    #{if state_text != "", do: "Current Agent State:\n#{state_text}\n", else: ""}
    Pending Instructions (#{instruction_count} total):
    #{instructions_text}

    Let's think step by step about how to execute these instructions:

    1. What is the overall goal of these instructions?
    2. What are the dependencies between instructions?
    3. What is the expected outcome of each step?
    4. What potential issues or edge cases should we consider?
    5. What is the step-by-step execution plan?

    Please provide a detailed reasoning plan in the following format:

    GOAL: [Brief description of the overall goal]

    ANALYSIS:
    [Detailed analysis of the instructions, dependencies, and considerations]

    EXECUTION_PLAN:
    Step 1: [First step with expected outcome]
    Step 2: [Second step with expected outcome]
    ...

    EXPECTED_RESULTS:
    [What results do we expect after executing all steps?]

    POTENTIAL_ISSUES:
    [Any potential problems, edge cases, or things to watch for]
    """

    Prompt.new(:user, template)
  end

  @doc """
  Generates a structured reasoning prompt optimized for code generation tasks.

  Uses program structure reasoning (sequence, branch, loop) aligned with actual code patterns
  as described in the research, providing 13.79% improvement over standard CoT.

  ## Parameters

  - `instructions` - List of pending instructions to reason about
  - `agent_state` - Current agent state map
  - `opts` - Optional keyword list of options

  ## Returns

  A `%Jido.AI.Prompt{}` struct containing the structured reasoning prompt.
  """
  @spec structured(list(), map(), keyword()) :: Prompt.t()
  def structured(instructions, agent_state, _opts \\ []) do
    instructions_text = format_instructions(instructions)
    state_text = format_state(agent_state)

    template = """
    You are an AI reasoning assistant helping to plan code-related agent instructions.
    Use structured reasoning aligned with program structure (sequence, branch, loop).

    #{if state_text != "", do: "Current Agent State:\n#{state_text}\n", else: ""}
    Pending Instructions:
    #{instructions_text}

    Let's use structured reasoning for these instructions:

    UNDERSTAND:
    - What data structures are involved?
    - What are the input/output requirements?
    - What are the constraints and edge cases?

    PLAN:
    - SEQUENCE: What operations must happen in order?
    - BRANCH: What conditional logic is needed?
    - LOOP: What iterative processing is required?
    - FUNCTIONAL PATTERNS: What higher-order functions or compositions apply?

    IMPLEMENT:
    - Step 1: [First implementation step]
    - Step 2: [Second implementation step]
    ...

    VALIDATE:
    - What tests or checks should verify correctness?
    - What error conditions should be handled?

    Please provide your structured reasoning following this format.
    """

    Prompt.new(:user, template)
  end

  @doc """
  Generates a few-shot reasoning prompt with examples.

  This will be implemented in future tasks when we have specific example sets.

  ## Parameters

  - `instructions` - List of pending instructions to reason about
  - `agent_state` - Current agent state map
  - `opts` - Optional keyword list of options including :examples

  ## Returns

  A `%Jido.AI.Prompt{}` struct containing the few-shot reasoning prompt.
  """
  @spec few_shot(list(), map(), keyword()) :: Prompt.t()
  def few_shot(instructions, agent_state, opts \\ []) do
    # Placeholder - will be enhanced with actual examples in future tasks
    zero_shot(instructions, agent_state, opts)
  end

  # Private helper functions

  defp format_instructions([]), do: "(No instructions)"

  defp format_instructions(instructions) do
    instructions
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {instruction, index} ->
      action_name = get_action_name(instruction)
      params_text = format_params(instruction)
      "#{index}. #{action_name}#{params_text}"
    end)
  end

  defp get_action_name(%{action: action}) when is_atom(action) do
    action |> to_string() |> String.split(".") |> List.last()
  end

  defp get_action_name(%{"action" => action}) when is_binary(action), do: action
  defp get_action_name(_), do: "UnknownAction"

  defp format_params(%{params: params}) when is_map(params) and map_size(params) > 0 do
    params_str =
      params
      |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
      |> String.slice(0, 100)

    " (#{params_str})"
  end

  defp format_params(%{"params" => params}) when is_map(params),
    do: format_params(%{params: params})

  defp format_params(_), do: ""

  defp format_state(state) when is_map(state) and map_size(state) > 0 do
    state
    |> Enum.reject(fn {k, _v} -> k in [:cot_config, :__struct__] end)
    |> Enum.map_join("\n", fn {k, v} ->
      value_str = inspect(v) |> String.slice(0, 200)
      "  #{k}: #{value_str}"
    end)
  end

  defp format_state(_), do: ""
end
