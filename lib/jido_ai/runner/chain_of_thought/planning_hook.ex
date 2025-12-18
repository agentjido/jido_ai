defmodule Jido.AI.Runner.ChainOfThought.PlanningHook do
  @moduledoc """
  Planning hook integration for Chain-of-Thought reasoning.

  Provides helper functions for implementing `on_before_plan/3` callback with
  CoT reasoning capabilities. This enables strategic planning analysis before
  instructions are queued to the agent.

  ## Features

  - High-level reasoning about instruction intent and dependencies
  - Dependency analysis between instructions
  - Potential issue identification
  - Context enrichment for downstream hooks
  - Opt-in behavior via `enable_planning_cot` flag

  ## Usage

  Implement `on_before_plan/3` callback in your agent:

      defmodule MyAgent do
        use Jido.Agent

        def on_before_plan(agent, instructions, context) do
          Jido.AI.Runner.ChainOfThought.PlanningHook.generate_planning_reasoning(
            agent,
            instructions,
            context
          )
        end
      end

  ## Opt-in Behavior

  Enable planning CoT by setting context flag:

      agent
      |> MyAgent.enqueue(action, params, context: %{enable_planning_cot: true})

  Or disable it:

      agent
      |> MyAgent.enqueue(action, params, context: %{enable_planning_cot: false})
  """

  require Logger
  use TypedStruct

  alias Jido.AI.Actions.TextCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias Jido.AI.Runner.ChainOfThought.ErrorHandler

  typedstruct module: PlanningReasoning do
    @moduledoc """
    Structured planning reasoning result.
    """
    field(:goal, String.t(), enforce: true)
    field(:analysis, String.t(), enforce: true)
    field(:dependencies, list(String.t()), default: [])
    field(:potential_issues, list(String.t()), default: [])
    field(:recommendations, list(String.t()), default: [])
    field(:timestamp, DateTime.t(), enforce: true)
  end

  @doc """
  Generates planning reasoning for instruction queue.

  This is the main entry point for implementing `on_before_plan/3` callback.
  It generates high-level reasoning about instruction intent, dependencies,
  and potential issues.

  ## Options (via context)

  - `:enable_planning_cot` - Enable/disable planning reasoning (default: true)
  - `:planning_model` - Model to use for planning (default: from config)
  - `:planning_temperature` - Temperature for planning (default: 0.3)

  ## Examples

      def on_before_plan(agent, instructions, context) do
        PlanningHook.generate_planning_reasoning(agent, instructions, context)
      end

  ## Returns

  - `{:ok, agent}` - Agent with planning reasoning in context
  - `{:ok, agent}` - Agent unchanged if planning disabled
  - `{:error, reason}` - Error generating planning reasoning
  """
  @spec generate_planning_reasoning(map(), list(), map()) :: {:ok, map()} | {:error, term()}
  def generate_planning_reasoning(agent, instructions, context) do
    if should_generate_planning?(context) do
      do_generate_planning_reasoning(agent, instructions, context)
    else
      Logger.debug("Planning CoT disabled via context flag")
      {:ok, agent}
    end
  end

  @doc """
  Checks if planning reasoning should be generated based on context.

  Returns `true` if `enable_planning_cot` is not explicitly set to `false`.

  ## Examples

      iex> should_generate_planning?(%{enable_planning_cot: true})
      true

      iex> should_generate_planning?(%{enable_planning_cot: false})
      false

      iex> should_generate_planning?(%{})
      true
  """
  @spec should_generate_planning?(map()) :: boolean()
  def should_generate_planning?(context) do
    Map.get(context, :enable_planning_cot, true)
  end

  @doc """
  Adds planning reasoning to agent context for downstream consumption.

  The reasoning is stored in the agent's state under `:planning_cot` key,
  making it available to `on_before_run` and `on_after_run` hooks.

  ## Examples

      agent = enrich_agent_with_planning(agent, planning_reasoning)
      planning = get_in(agent, [:state, :planning_cot])
  """
  @spec enrich_agent_with_planning(map(), PlanningReasoning.t()) :: map()
  def enrich_agent_with_planning(agent, planning_reasoning) do
    current_state = agent.state || %{}
    updated_state = Map.put(current_state, :planning_cot, planning_reasoning)
    %{agent | state: updated_state}
  end

  @doc """
  Extracts planning reasoning from agent state.

  Returns the planning reasoning if available, or `nil` if not present.

  ## Examples

      {:ok, planning} = get_planning_reasoning(agent)
  """
  @spec get_planning_reasoning(map()) :: {:ok, PlanningReasoning.t()} | {:error, :no_planning}
  def get_planning_reasoning(agent) do
    case get_in(agent, [:state, :planning_cot]) do
      %PlanningReasoning{} = planning -> {:ok, planning}
      nil -> {:error, :no_planning}
      _ -> {:error, :invalid_planning}
    end
  end

  # Private Functions

  @spec do_generate_planning_reasoning(map(), list(), map()) :: {:ok, map()} | {:error, term()}
  defp do_generate_planning_reasoning(agent, instructions, context) do
    Logger.info("Generating planning reasoning for #{length(instructions)} instructions")

    with {:ok, planning_text} <- generate_planning_text(instructions, agent, context),
         {:ok, planning} <- parse_planning_text(planning_text) do
      Logger.debug("Successfully generated planning reasoning")
      updated_agent = enrich_agent_with_planning(agent, planning)
      {:ok, updated_agent}
    else
      {:error, reason} ->
        Logger.warning("Failed to generate planning reasoning: #{inspect(reason)}")
        # Return agent unchanged on error (graceful degradation)
        {:ok, agent}
    end
  end

  @spec generate_planning_text(list(), map(), map()) :: {:ok, String.t()} | {:error, term()}
  defp generate_planning_text(instructions, agent, context) do
    with {:ok, prompt} <- build_planning_prompt(instructions, agent),
         {:ok, model} <- get_planning_model(context) do
      call_llm_for_planning(prompt, model, context)
    end
  end

  @spec build_planning_prompt(list(), map()) :: {:ok, Jido.AI.Prompt.t()}
  defp build_planning_prompt(instructions, agent) do
    state_summary = summarize_agent_state(agent.state || %{})
    instructions_summary = summarize_instructions(instructions)

    template = """
    You are analyzing a sequence of instructions for strategic planning.

    Current Agent State:
    #{state_summary}

    Pending Instructions:
    #{instructions_summary}

    Analyze these instructions and provide strategic planning reasoning:

    GOAL: What is the overall objective of these instructions?

    ANALYSIS: Analyze the intent and flow of these instructions. What are we trying to accomplish?

    DEPENDENCIES:
    - List any dependencies between instructions
    - Identify data flow between steps
    - Note any required ordering

    POTENTIAL_ISSUES:
    - Identify potential problems or risks
    - Note missing preconditions
    - Flag possible failure points

    RECOMMENDATIONS:
    - Suggest optimizations or improvements
    - Recommend additional validation
    - Note best practices to follow

    Provide clear, concise analysis focused on strategic planning.
    """

    prompt = Prompt.new(:user, template)
    {:ok, prompt}
  end

  @spec get_planning_model(map()) :: {:ok, Model.t()} | {:error, term()}
  defp get_planning_model(context) do
    model_name = Map.get(context, :planning_model, "gpt-4o")
    Model.from({:openai, model: model_name})
  end

  @spec call_llm_for_planning(Jido.AI.Prompt.t(), Model.t(), map()) ::
          {:ok, String.t()} | {:error, term()}
  defp call_llm_for_planning(prompt, model, context) do
    temperature = Map.get(context, :planning_temperature, 0.3)

    ErrorHandler.with_retry(
      fn ->
        params = %{
          model: model,
          prompt: prompt,
          temperature: temperature,
          max_tokens: 1500
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

  @spec parse_planning_text(String.t()) :: {:ok, PlanningReasoning.t()} | {:error, term()}
  defp parse_planning_text(text) do
    goal = extract_section(text, "GOAL")
    analysis = extract_section(text, "ANALYSIS")
    dependencies = extract_list_section(text, "DEPENDENCIES")
    potential_issues = extract_list_section(text, "POTENTIAL_ISSUES")
    recommendations = extract_list_section(text, "RECOMMENDATIONS")

    planning = %PlanningReasoning{
      goal: goal,
      analysis: analysis,
      dependencies: dependencies,
      potential_issues: potential_issues,
      recommendations: recommendations,
      timestamp: DateTime.utc_now()
    }

    if String.trim(goal) == "" do
      {:error, "Missing goal in planning reasoning"}
    else
      {:ok, planning}
    end
  end

  @spec extract_section(String.t(), String.t()) :: String.t()
  defp extract_section(text, section_name) do
    case Regex.run(~r/#{section_name}:\s*(.+?)(?=\n[A-Z_]+:|$)/s, text) do
      [_, content] -> String.trim(content)
      _ -> ""
    end
  end

  @spec extract_list_section(String.t(), String.t()) :: list(String.t())
  defp extract_list_section(text, section_name) do
    case Regex.run(~r/#{section_name}:\s*(.+?)(?=\n[A-Z_]+:|$)/s, text) do
      [_, content] ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(fn line -> String.starts_with?(line, "-") end)
        |> Enum.map(fn line -> String.replace_prefix(line, "- ", "") end)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  @spec summarize_agent_state(map()) :: String.t()
  defp summarize_agent_state(state) when state == %{}, do: "Empty state"

  defp summarize_agent_state(state) do
    state
    |> Map.drop([:planning_cot, :cot_config])
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
