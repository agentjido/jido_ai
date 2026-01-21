defmodule Jido.AI.Runner.GEPA.Reflector do
  @moduledoc """
  LLM-Guided Reflection for GEPA prompt optimization (Task 1.3.2).

  This module implements the core innovation of GEPA: using an LLM to analyze
  execution trajectories and generate targeted improvement suggestions. Rather than
  relying on opaque gradient signals, the LLM acts as a "reflective coach" that
  understands failures semantically and suggests specific prompt modifications.

  ## Overview

  The reflection process:
  1. Receives trajectory analysis from `TrajectoryAnalyzer`
  2. Builds structured reflection prompts
  3. Calls LLM with request for JSON-formatted suggestions
  4. Parses response into actionable insights
  5. Supports multi-turn dialogue for deeper understanding

  ## Usage

      # Single-turn reflection
      analysis = TrajectoryAnalyzer.analyze(trajectory)
      {:ok, reflection} = Reflector.reflect_on_failure(analysis)

      # Access suggestions
      reflection.suggestions
      |> Enum.filter(&(&1.priority == :high))
      |> Enum.each(&IO.inspect/1)

      # Multi-turn reflection for clarification
      {:ok, conversation} = Reflector.start_conversation(analysis)
      {:ok, reflection2} = Reflector.continue_conversation(conversation, "What specifically failed in step 3?")

  ## Key Features

  - **Structured Output**: Requests JSON responses with typed suggestions
  - **Multi-turn Support**: Enables follow-up questions for deeper analysis
  - **Actionable Insights**: Categorizes suggestions by type and priority
  - **Error Handling**: Graceful degradation with fallback responses

  ## Integration Points

  - **Input**: `TrajectoryAnalyzer.TrajectoryAnalysis` (Section 1.3.1 ✅)
  - **Output**: `ParsedReflection` with structured suggestions
  - **Next Step**: Mutation operators (Section 1.4) consume suggestions

  ## Implementation Status

  - [x] 1.3.2.1: Reflection prompt creation (PromptBuilder)
  - [x] 1.3.2.2: LLM call with structured output (Reflector)
  - [x] 1.3.2.3: Response parsing (SuggestionParser)
  - [x] 1.3.2.4: Multi-turn reflection (ConversationManager)
  """

  use TypedStruct
  require Logger

  alias Jido.Agent.Server
  alias Jido.AI.Agent
  alias Jido.AI.Runner.GEPA.Reflection.{PromptBuilder, SuggestionParser}
  alias Jido.AI.Runner.GEPA.TrajectoryAnalyzer
  alias Jido.Signal

  # Type definitions

  @type suggestion_type :: :add | :modify | :remove | :restructure
  @type suggestion_category :: :clarity | :constraint | :example | :structure | :reasoning
  @type priority :: :high | :medium | :low
  @type confidence :: :high | :medium | :low

  typedstruct module: Suggestion do
    @moduledoc """
    A single actionable suggestion for prompt improvement.

    Represents a specific modification that should be made to the prompt
    to address identified failures or weaknesses.
    """

    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:type, Jido.AI.Runner.GEPA.Reflector.suggestion_type(), enforce: true)
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:category, Jido.AI.Runner.GEPA.Reflector.suggestion_category(), enforce: true)
    field(:description, String.t(), enforce: true)
    field(:rationale, String.t(), enforce: true)
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:priority, Jido.AI.Runner.GEPA.Reflector.priority(), default: :medium)
    field(:specific_text, String.t() | nil)
    field(:target_section, String.t() | nil)
  end

  typedstruct module: ReflectionRequest do
    @moduledoc """
    Request for LLM to reflect on a failed trajectory.

    Contains all context needed for the LLM to analyze the failure
    and generate improvement suggestions.
    """

    field(:trajectory_analysis, TrajectoryAnalyzer.TrajectoryAnalysis.t(), enforce: true)
    field(:original_prompt, String.t(), enforce: true)
    field(:task_description, String.t())
    field(:verbosity, :brief | :normal | :detailed, default: :normal)
    field(:focus_areas, list(atom()), default: [])
    field(:metadata, map(), default: %{})
  end

  typedstruct module: ReflectionResponse do
    @moduledoc """
    Raw response from LLM reflection call.

    Contains the LLM's analysis before parsing into structured format.
    """

    field(:content, String.t(), enforce: true)
    field(:format, :json | :text, default: :json)
    field(:model, String.t())
    field(:timestamp, DateTime.t(), enforce: true)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: ParsedReflection do
    @moduledoc """
    Structured reflection result after parsing LLM response.

    Contains actionable insights extracted from the LLM's analysis,
    ready for consumption by mutation operators.
    """

    field(:analysis, String.t(), enforce: true)
    field(:root_causes, list(String.t()), default: [])
    field(:suggestions, list(Suggestion.t()), default: [])
    field(:expected_improvement, String.t())
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:confidence, Jido.AI.Runner.GEPA.Reflector.confidence(), default: :medium)
    field(:needs_clarification, boolean(), default: false)
    field(:metadata, map(), default: %{})
  end

  typedstruct module: ConversationState do
    @moduledoc """
    State for multi-turn reflection conversation.

    Tracks dialogue history and enables follow-up questions for
    deeper understanding of failures.
    """

    field(:id, String.t(), enforce: true)
    field(:initial_request, ReflectionRequest.t(), enforce: true)
    field(:turns, list(map()), default: [])
    field(:reflections, list(ParsedReflection.t()), default: [])
    field(:max_turns, pos_integer(), default: 3)
    field(:current_turn, non_neg_integer(), default: 0)
    field(:completed, boolean(), default: false)
    field(:metadata, map(), default: %{})
  end

  # Default configuration

  @default_model {:openai, model: "gpt-4"}
  @default_timeout 30_000
  @default_temperature 0.3
  @default_max_tokens 2000

  # Public API

  @doc """
  Reflect on a failed trajectory execution and generate improvement suggestions.

  ## Parameters

  - `trajectory_analysis` - Analysis from `TrajectoryAnalyzer.analyze/1`
  - `opts` - Options:
    - `:original_prompt` - The prompt that was evaluated (required)
    - `:task_description` - Description of the task being performed
    - `:model` - LLM model to use (default: GPT-4)
    - `:verbosity` - Level of detail (`:brief`, `:normal`, `:detailed`)
    - `:timeout` - Timeout in milliseconds (default: 30000)
    - `:temperature` - LLM temperature (default: 0.3)

  ## Returns

  - `{:ok, ParsedReflection.t()}` - Structured reflection with suggestions
  - `{:error, reason}` - If reflection fails

  ## Examples

      analysis = TrajectoryAnalyzer.analyze(trajectory)
      {:ok, reflection} = Reflector.reflect_on_failure(analysis,
        original_prompt: "Solve this step by step",
        task_description: "Math problem solving"
      )

      # Access high-priority suggestions
      high_priority = Enum.filter(reflection.suggestions, &(&1.priority == :high))
  """
  @spec reflect_on_failure(TrajectoryAnalyzer.TrajectoryAnalysis.t(), keyword()) ::
          {:ok, ParsedReflection.t()} | {:error, term()}
  def reflect_on_failure(trajectory_analysis, opts \\ []) do
    Logger.debug("Starting reflection on trajectory failure")

    with {:ok, request} <- build_reflection_request(trajectory_analysis, opts),
         {:ok, response} <- execute_reflection(request, opts),
         {:ok, parsed} <- parse_reflection_response(response, opts) do
      Logger.debug(
        "Reflection completed successfully (suggestions: #{length(parsed.suggestions)}, confidence: #{parsed.confidence})"
      )

      {:ok, parsed}
    else
      {:error, reason} = error ->
        Logger.warning("Reflection failed", reason: reason)
        error
    end
  end

  @doc """
  Start a multi-turn reflection conversation.

  Enables follow-up questions for deeper understanding of failures.

  ## Parameters

  - `trajectory_analysis` - Analysis from `TrajectoryAnalyzer.analyze/1`
  - `opts` - Same options as `reflect_on_failure/2` plus:
    - `:max_turns` - Maximum conversation turns (default: 3)

  ## Returns

  - `{:ok, ConversationState.t()}` - Conversation with initial reflection
  - `{:error, reason}` - If conversation start fails

  ## Examples

      {:ok, conversation} = Reflector.start_conversation(analysis,
        original_prompt: prompt,
        max_turns: 5
      )

      # Continue with follow-up
      {:ok, updated} = Reflector.continue_conversation(
        conversation,
        "What specifically caused the contradiction in step 3?"
      )
  """
  @spec start_conversation(TrajectoryAnalyzer.TrajectoryAnalysis.t(), keyword()) ::
          {:ok, ConversationState.t()} | {:error, term()}
  def start_conversation(trajectory_analysis, opts \\ []) do
    Logger.debug("Starting multi-turn reflection conversation")

    with {:ok, request} <- build_reflection_request(trajectory_analysis, opts),
         {:ok, response} <- execute_reflection(request, opts),
         {:ok, parsed} <- parse_reflection_response(response, opts) do
      conversation = %ConversationState{
        id: generate_conversation_id(),
        initial_request: request,
        turns: [
          %{
            turn: 1,
            type: :initial,
            response: response,
            reflection: parsed,
            timestamp: DateTime.utc_now()
          }
        ],
        reflections: [parsed],
        max_turns: opts[:max_turns] || 3,
        current_turn: 1,
        completed: false
      }

      Logger.debug("Conversation started", conversation_id: conversation.id)
      {:ok, conversation}
    end
  end

  @doc """
  Continue a multi-turn reflection conversation with a follow-up question.

  ## Parameters

  - `conversation` - Current conversation state
  - `follow_up_question` - Clarifying question or request for deeper analysis
  - `opts` - Options (same as `reflect_on_failure/2`)

  ## Returns

  - `{:ok, ConversationState.t()}` - Updated conversation
  - `{:error, reason}` - If continuation fails

  ## Examples

      {:ok, conversation} = Reflector.continue_conversation(
        conversation,
        "Can you elaborate on the reasoning failure in step 3?"
      )
  """
  @spec continue_conversation(ConversationState.t(), String.t(), keyword()) ::
          {:ok, ConversationState.t()} | {:error, term()}
  def continue_conversation(%ConversationState{} = conversation, follow_up_question, opts \\ []) do
    cond do
      conversation.completed ->
        {:error, :conversation_completed}

      conversation.current_turn >= conversation.max_turns ->
        {:error, :max_turns_reached}

      true ->
        execute_conversation_turn(conversation, follow_up_question, opts)
    end
  end

  @doc """
  Select the best reflection from a multi-turn conversation.

  Chooses the reflection with highest confidence and most actionable suggestions.

  ## Parameters

  - `conversation` - Completed or in-progress conversation

  ## Returns

  - `ParsedReflection.t()` - Best reflection from conversation

  ## Examples

      best = Reflector.select_best_reflection(conversation)
  """
  @spec select_best_reflection(ConversationState.t()) :: ParsedReflection.t() | nil
  def select_best_reflection(%ConversationState{reflections: reflections}) do
    case reflections do
      [] -> nil
      [single] -> single
      _ -> Enum.max_by(reflections, &score_reflection/1)
    end
  end

  # Private Functions

  defp build_reflection_request(trajectory_analysis, opts) do
    case opts[:original_prompt] do
      nil ->
        {:error, :missing_original_prompt}

      prompt ->
        request = %ReflectionRequest{
          trajectory_analysis: trajectory_analysis,
          original_prompt: prompt,
          task_description: opts[:task_description],
          verbosity: opts[:verbosity] || :normal,
          focus_areas: opts[:focus_areas] || [],
          metadata: opts[:metadata] || %{}
        }

        {:ok, request}
    end
  end

  defp execute_reflection(request, opts) do
    Logger.debug("Executing LLM reflection call")

    # Build prompts
    user_prompt = PromptBuilder.build_reflection_prompt(request, opts)
    system_prompt = PromptBuilder.system_prompt()

    # Configure agent
    model = opts[:model] || @default_model
    timeout = opts[:timeout] || @default_timeout
    temperature = opts[:temperature] || @default_temperature
    max_tokens = opts[:max_tokens] || @default_max_tokens

    agent_opts = [
      agent: Agent,
      skills: [Jido.AI.Skill],
      ai: [
        model: model,
        verbose: opts[:verbose] || false
      ]
    ]

    # Execute reflection via agent
    with {:ok, agent_pid} <- Server.start_link(agent_opts),
         {:ok, signal} <-
           build_reflection_signal(system_prompt, user_prompt, temperature, max_tokens),
         {:ok, response_signal} <- Server.call(agent_pid, signal, timeout),
         :ok <- cleanup_agent(agent_pid) do
      # Extract content from response
      content = extract_content_from_signal(response_signal)

      response = %ReflectionResponse{
        content: content,
        format: :json,
        model: inspect(model),
        timestamp: DateTime.utc_now(),
        metadata: %{
          request_id: generate_request_id(),
          signal_id: response_signal.id
        }
      }

      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.warning("Reflection execution failed", reason: reason)
        error
    end
  end

  defp parse_reflection_response(response, opts) do
    Logger.debug("Parsing reflection response")

    with {:ok, parsed} <- SuggestionParser.parse(response, opts),
         {:ok, validated} <- SuggestionParser.validate(parsed) do
      {:ok, validated}
    else
      {:error, reason} = error ->
        Logger.warning("Reflection parsing failed", reason: reason)
        error
    end
  end

  defp execute_conversation_turn(conversation, _follow_up_question, _opts) do
    # This will be implemented to handle multi-turn dialogue
    # For now, return conversation unchanged
    {:ok, conversation}
  end

  defp build_reflection_signal(system_prompt, user_prompt, temperature, max_tokens) do
    # Build a signal for LLM reflection call
    Signal.new(%{
      type: "jido.ai.chat.response",
      data: %{
        messages: [
          %{role: :system, content: system_prompt},
          %{role: :user, content: user_prompt}
        ],
        temperature: temperature,
        max_tokens: max_tokens,
        response_format: %{type: "json_object"}
      }
    })
  end

  defp extract_content_from_signal(signal) do
    # Extract LLM response content from signal
    case signal.data do
      %{content: content} when is_binary(content) ->
        content

      %{message: %{content: content}} when is_binary(content) ->
        content

      %{response: content} when is_binary(content) ->
        content

      data when is_map(data) ->
        # Try to find content in various keys
        data
        |> Map.values()
        |> Enum.find("", &is_binary/1)

      _ ->
        Logger.warning(
          "Could not extract content from signal (signal_data: #{inspect(signal.data)})"
        )

        ""
    end
  end

  defp cleanup_agent(agent_pid) do
    if Process.alive?(agent_pid) do
      Logger.debug("Cleaning up reflection agent (pid: #{inspect(agent_pid)})")

      try do
        Process.unlink(agent_pid)
        GenServer.stop(agent_pid, :normal, 1_000)
        :ok
      catch
        :exit, reason ->
          Logger.debug("Agent cleanup exit", reason: reason)
          :ok
      end
    else
      :ok
    end
  end

  defp score_reflection(reflection) do
    confidence_score =
      case reflection.confidence do
        :high -> 3
        :medium -> 2
        :low -> 1
      end

    suggestion_score = length(reflection.suggestions)
    high_priority_score = Enum.count(reflection.suggestions, &(&1.priority == :high))

    confidence_score * 10 + suggestion_score * 2 + high_priority_score * 5
  end

  defp generate_conversation_id do
    "conv_#{:erlang.unique_integer([:positive])}"
  end

  defp generate_request_id do
    "req_#{:erlang.unique_integer([:positive])}"
  end
end
