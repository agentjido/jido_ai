defmodule Jido.AI.Runner.ChainOfThought.ExecutionContext do
  @moduledoc """
  Manages reasoning context enrichment for action execution.

  This module provides functions to enrich execution context with reasoning
  information, enabling actions to access step-by-step reasoning plans and
  expected outcomes during execution.
  """

  alias Jido.AI.Runner.ChainOfThought.ReasoningParser.{ReasoningPlan, ReasoningStep}

  use TypedStruct

  typedstruct module: EnrichedContext do
    @moduledoc """
    Enriched execution context containing reasoning information.

    This context is passed to actions during reasoning-guided execution,
    providing access to the overall reasoning plan and current step information.
    """

    field(:reasoning_plan, ReasoningPlan.t())
    field(:current_step, ReasoningStep.t() | nil)
    field(:step_index, integer(), default: 0)
    field(:original_context, map(), default: %{})
  end

  @doc """
  Enriches an execution context with reasoning information.

  Adds reasoning plan and current step information to the context map,
  making it available to actions during execution.

  ## Parameters

  - `original_context` - The original execution context map
  - `reasoning_plan` - The complete reasoning plan
  - `step_index` - The current step index (0-based)

  ## Returns

  An enriched context map with reasoning information under the `:cot` key.

  ## Example

      iex> context = %{state: %{}}
      iex> plan = %ReasoningPlan{goal: "test", steps: [%ReasoningStep{number: 1}]}
      iex> enriched = ExecutionContext.enrich(context, plan, 0)
      iex> enriched.cot.reasoning_plan.goal
      "test"
  """
  @spec enrich(map(), ReasoningPlan.t(), integer()) :: map()
  def enrich(original_context, reasoning_plan, step_index) when is_map(original_context) do
    current_step = get_step_at_index(reasoning_plan.steps, step_index)

    enriched = %EnrichedContext{
      reasoning_plan: reasoning_plan,
      current_step: current_step,
      step_index: step_index,
      original_context: original_context
    }

    Map.put(original_context, :cot, enriched)
  end

  @doc """
  Extracts the reasoning plan from an enriched context.

  ## Parameters

  - `context` - An enriched context map

  ## Returns

  - `{:ok, reasoning_plan}` if reasoning context exists
  - `{:error, :no_reasoning_context}` if context is not enriched
  """
  @spec get_reasoning_plan(map()) :: {:ok, ReasoningPlan.t()} | {:error, :no_reasoning_context}
  def get_reasoning_plan(%{cot: %EnrichedContext{reasoning_plan: plan}}), do: {:ok, plan}
  def get_reasoning_plan(_), do: {:error, :no_reasoning_context}

  @doc """
  Extracts the current step from an enriched context.

  ## Parameters

  - `context` - An enriched context map

  ## Returns

  - `{:ok, reasoning_step}` if current step exists
  - `{:error, reason}` if no step information available
  """
  @spec get_current_step(map()) ::
          {:ok, ReasoningStep.t()} | {:error, :no_reasoning_context | :no_current_step}
  def get_current_step(%{cot: %EnrichedContext{current_step: step}}) when not is_nil(step) do
    {:ok, step}
  end

  def get_current_step(%{cot: %EnrichedContext{current_step: nil}}) do
    {:error, :no_current_step}
  end

  def get_current_step(_), do: {:error, :no_reasoning_context}

  @doc """
  Checks if a context has been enriched with reasoning.

  ## Parameters

  - `context` - A context map

  ## Returns

  Boolean indicating whether reasoning context is present.
  """
  @spec has_reasoning_context?(map()) :: boolean()
  def has_reasoning_context?(%{cot: %EnrichedContext{}}), do: true
  def has_reasoning_context?(_), do: false

  # Private helper functions

  defp get_step_at_index(steps, index) when is_list(steps) do
    Enum.at(steps, index)
  end

  defp get_step_at_index(_, _), do: nil
end
