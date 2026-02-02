defmodule Jido.AI.TRM.Machine do
  @moduledoc """
  Pure state machine for the TRM (Tiny-Recursive-Model) reasoning pattern.

  This module implements state transitions for a TRM agent without any side effects.
  It uses Fsmx for state machine management and returns directives that describe
  what external effects should be performed.

  ## Overview

  TRM uses recursive reasoning to iteratively improve answers through a
  reason-supervise-improve cycle. Each iteration:
  1. **Reasoning**: Generate insights about the current answer
  2. **Supervision**: Evaluate the answer and provide feedback
  3. **Improvement**: Apply feedback to generate a better answer

  The cycle continues until either:
  - Maximum supervision steps reached
  - ACT (Adaptive Computational Time) threshold exceeded (high confidence)
  - Convergence detected (improvements have plateaued)

  ## States

  - `:idle` - Initial state, waiting for a question
  - `:reasoning` - Generating reasoning insights
  - `:supervising` - Evaluating current answer quality
  - `:improving` - Applying feedback to improve answer
  - `:completed` - Final state, best answer found
  - `:error` - Error state

  ## Usage

  The machine is used by the TRM strategy:

      machine = Machine.new(max_supervision_steps: 5, act_threshold: 0.9)
      {machine, directives} = Machine.update(machine, {:start, question, call_id}, env)

  All state transitions are pure - side effects are described in directives.

  ## Telemetry Events

  The machine emits the following telemetry events:

  ### `[:jido, :ai, :trm, :start]`
  Emitted when reasoning starts with a new question.
  - **Measurements**: (none)
  - **Metadata**: `%{call_id: String.t(), question_length: non_neg_integer()}`

  ### `[:jido, :ai, :trm, :step]`
  Emitted at each supervision step.
  - **Measurements**: `%{step: pos_integer(), quality_score: float()}`
  - **Metadata**: `%{call_id: String.t(), issues_count: non_neg_integer(), suggestions_count: non_neg_integer()}`

  ### `[:jido, :ai, :trm, :act_triggered]`
  Emitted when ACT early stopping triggers.
  - **Measurements**: `%{confidence: float(), threshold: float()}`
  - **Metadata**: `%{call_id: String.t(), step: pos_integer()}`

  ### `[:jido, :ai, :trm, :error]`
  Emitted when an error occurs.
  - **Measurements**: (none)
  - **Metadata**: `%{call_id: String.t(), error: term(), usage: map()}`

  ### `[:jido, :ai, :trm, :complete]`
  Emitted when reasoning completes successfully.
  - **Measurements**: `%{steps: non_neg_integer(), best_score: float(), duration_ms: non_neg_integer()}`
  - **Metadata**: `%{call_id: String.t(), termination_reason: atom(), usage: map()}`

  ## Status Type Boundary

  **Internal (Machine struct):** Status is stored as strings (`"idle"`, `"completed"`)
  due to Fsmx library requirements.

  **External (Strategy state, Snapshots):** Status is converted to atoms (`:idle`,
  `:completed`) via `to_map/1` before storage in agent state.

  Never compare `machine.status` directly with atoms - use `Machine.to_map/1` first.
  """

  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "idle" => ["reasoning"],
      "reasoning" => ["supervising", "error"],
      "supervising" => ["improving", "error"],
      "improving" => ["reasoning", "completed", "error"],
      "completed" => [],
      "error" => []
    }

  alias Jido.AI.TRM.ACT
  alias Jido.AI.TRM.Helpers
  alias Jido.AI.TRM.Supervision

  # Telemetry event names
  @telemetry_prefix [:jido, :ai, :trm]

  @default_max_supervision_steps 5
  @default_act_threshold 0.9

  @typedoc "Internal machine status (string) - required by Fsmx library"
  @type internal_status :: String.t()

  @typedoc "External status (atom) - used in strategy state after to_map/1 conversion"
  @type external_status :: :idle | :reasoning | :supervising | :improving | :completed | :error

  @type termination_reason :: :max_steps | :act_threshold | :convergence_detected | :error | nil

  @type latent_state :: %{
          question_context: String.t() | nil,
          answer_context: String.t() | nil,
          reasoning_trace: [String.t()],
          confidence_score: float(),
          step_count: non_neg_integer()
        }

  @type usage :: %{
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer()
        }

  @type act_state :: %{
          threshold: float(),
          current_confidence: float(),
          history: [float()]
        }

  @type t :: %__MODULE__{
          status: internal_status(),
          question: String.t() | nil,
          current_answer: String.t() | nil,
          answer_history: [String.t()],
          latent_state: latent_state(),
          supervision_feedback: String.t() | nil,
          parsed_feedback: map() | nil,
          supervision_step: non_neg_integer(),
          max_supervision_steps: pos_integer(),
          act_threshold: float(),
          act_state: act_state(),
          act_triggered: boolean(),
          best_answer: String.t() | nil,
          best_score: float(),
          result: term(),
          current_call_id: String.t() | nil,
          termination_reason: termination_reason(),
          streaming_text: String.t(),
          usage: usage(),
          started_at: integer() | nil
        }

  defstruct status: "idle",
            question: nil,
            current_answer: nil,
            answer_history: [],
            latent_state: %{
              question_context: nil,
              answer_context: nil,
              reasoning_trace: [],
              confidence_score: 0.0,
              step_count: 0
            },
            supervision_feedback: nil,
            parsed_feedback: nil,
            supervision_step: 0,
            max_supervision_steps: @default_max_supervision_steps,
            act_threshold: @default_act_threshold,
            act_state: %{threshold: @default_act_threshold, current_confidence: 0.0, history: []},
            act_triggered: false,
            best_answer: nil,
            best_score: 0.0,
            result: nil,
            current_call_id: nil,
            termination_reason: nil,
            streaming_text: "",
            usage: %{},
            started_at: nil

  @type msg ::
          {:start, question :: String.t(), call_id :: String.t()}
          | {:reasoning_result, call_id :: String.t(), result :: term()}
          | {:supervision_result, call_id :: String.t(), result :: term()}
          | {:improvement_result, call_id :: String.t(), result :: term()}
          | {:llm_partial, call_id :: String.t(), delta :: String.t(), chunk_type :: atom()}

  @type directive ::
          {:reason, id :: String.t(), context :: map()}
          | {:supervise, id :: String.t(), context :: map()}
          | {:improve, id :: String.t(), context :: map()}

  @doc """
  Creates a new machine in the idle state with default configuration.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Creates a new machine in the idle state with custom configuration.

  ## Options

  - `:max_supervision_steps` - Maximum iterations before termination (default: 5)
  - `:act_threshold` - Confidence threshold for early stopping (default: 0.9)
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    max_steps = Keyword.get(opts, :max_supervision_steps, @default_max_supervision_steps)
    threshold = Keyword.get(opts, :act_threshold, @default_act_threshold)

    %__MODULE__{
      max_supervision_steps: max_steps,
      act_threshold: threshold,
      act_state: ACT.new(threshold)
    }
  end

  @doc """
  Updates the machine state based on a message.

  Returns the updated machine and a list of directives describing
  external effects to be performed.

  ## Messages

  - `{:start, question, call_id}` - Start TRM reasoning
  - `{:reasoning_result, call_id, result}` - Handle reasoning response
  - `{:supervision_result, call_id, result}` - Handle supervision feedback
  - `{:improvement_result, call_id, result}` - Handle improved answer
  - `{:llm_partial, call_id, delta, chunk_type}` - Handle streaming chunk

  ## Directives

  - `{:reason, id, context}` - Request reasoning LLM call
  - `{:supervise, id, context}` - Request supervision LLM call
  - `{:improve, id, context}` - Request improvement LLM call
  """
  @spec update(t(), msg(), map()) :: {t(), [directive()]}
  def update(machine, msg, env \\ %{})

  # Start: idle → reasoning
  def update(%__MODULE__{status: "idle"} = machine, {:start, question, call_id}, _env) do
    started_at = System.monotonic_time(:millisecond)

    emit_telemetry(:start, %{system_time: System.system_time()}, %{
      call_id: call_id,
      question_length: String.length(question)
    })

    with_transition(machine, "reasoning", fn machine ->
      latent_state = initialize_latent_state(question, nil)

      machine = %{
        machine
        | question: question,
          current_answer: nil,
          answer_history: [],
          latent_state: latent_state,
          supervision_feedback: nil,
          parsed_feedback: nil,
          supervision_step: 1,
          act_state: ACT.new(machine.act_threshold),
          act_triggered: false,
          best_answer: nil,
          best_score: 0.0,
          result: nil,
          current_call_id: call_id,
          termination_reason: nil,
          streaming_text: "",
          usage: %{},
          started_at: started_at
      }

      context = build_reasoning_context(machine)
      {machine, [{:reason, call_id, context}]}
    end)
  end

  # Issue #3 fix: Explicitly reject start requests when busy instead of silently dropping
  def update(%__MODULE__{status: status} = machine, {:start, _question, call_id}, _env)
      when status in ["reasoning", "supervising", "improving"] do
    {machine, [{:request_error, call_id, :busy, "Agent is busy (status: #{status})"}]}
  end

  # Reasoning result: reasoning → supervising
  def update(%__MODULE__{status: "reasoning"} = machine, {:reasoning_result, call_id, result}, _env) do
    if call_id == machine.current_call_id do
      handle_reasoning_result(machine, result)
    else
      {machine, []}
    end
  end

  # Supervision result: supervising → improving
  def update(%__MODULE__{status: "supervising"} = machine, {:supervision_result, call_id, result}, _env) do
    if call_id == machine.current_call_id do
      handle_supervision_result(machine, result)
    else
      {machine, []}
    end
  end

  # Improvement result: improving → reasoning or completed
  def update(%__MODULE__{status: "improving"} = machine, {:improvement_result, call_id, result}, _env) do
    if call_id == machine.current_call_id do
      handle_improvement_result(machine, result)
    else
      {machine, []}
    end
  end

  # Streaming partial for any awaiting state
  def update(%__MODULE__{status: status} = machine, {:llm_partial, call_id, delta, chunk_type}, _env)
      when status in ["reasoning", "supervising", "improving"] do
    if call_id == machine.current_call_id do
      machine =
        case chunk_type do
          :content ->
            Map.update!(machine, :streaming_text, &(&1 <> delta))

          _ ->
            machine
        end

      {machine, []}
    else
      {machine, []}
    end
  end

  # Catch-all for unhandled messages
  def update(machine, _msg, _env) do
    {machine, []}
  end

  # Handle reasoning LLM response
  defp handle_reasoning_result(machine, {:error, reason}) do
    handle_error(machine, reason)
  end

  defp handle_reasoning_result(machine, {:ok, result}) do
    machine = accumulate_usage(machine, result)
    response_text = result.text || ""

    # Update latent state with reasoning insights
    latent_state = update_latent_state(machine.latent_state, :reasoning, response_text)

    # If this is the first reasoning step, use the response as initial answer
    current_answer = machine.current_answer || response_text

    emit_telemetry(:step, %{system_time: System.system_time()}, %{
      step: machine.supervision_step,
      phase: :reasoning,
      call_id: machine.current_call_id
    })

    new_call_id = generate_call_id()

    with_transition(machine, "supervising", fn machine ->
      machine =
        machine
        |> Map.put(:current_answer, current_answer)
        |> Map.put(:latent_state, latent_state)
        |> Map.put(:current_call_id, new_call_id)
        |> Map.put(:streaming_text, "")

      context = build_supervision_context(machine)
      {machine, [{:supervise, new_call_id, context}]}
    end)
  end

  # Handle supervision LLM response
  defp handle_supervision_result(machine, {:error, reason}) do
    handle_error(machine, reason)
  end

  defp handle_supervision_result(machine, {:ok, result}) do
    machine = accumulate_usage(machine, result)
    feedback_text = result.text || ""

    # Use Supervision module to parse feedback
    parsed_feedback = Supervision.parse_supervision_result(feedback_text)
    quality_score = parsed_feedback.quality_score

    # Update ACT state with new confidence
    act_state = ACT.update(machine.act_state, quality_score)

    # Update best answer if this is the best so far
    machine =
      if quality_score > machine.best_score do
        machine
        |> Map.put(:best_answer, machine.current_answer)
        |> Map.put(:best_score, quality_score)
      else
        machine
      end

    # Update latent state with supervision feedback
    latent_state =
      machine.latent_state
      |> update_latent_state(:supervision, feedback_text)
      |> Map.put(:confidence_score, quality_score)

    emit_telemetry(:step, %{system_time: System.system_time()}, %{
      step: machine.supervision_step,
      phase: :supervision,
      quality_score: quality_score,
      issues_count: length(parsed_feedback.issues),
      suggestions_count: length(parsed_feedback.suggestions),
      call_id: machine.current_call_id
    })

    new_call_id = generate_call_id()

    with_transition(machine, "improving", fn machine ->
      machine =
        machine
        |> Map.put(:supervision_feedback, feedback_text)
        |> Map.put(:parsed_feedback, parsed_feedback)
        |> Map.put(:latent_state, latent_state)
        |> Map.put(:act_state, act_state)
        |> Map.put(:current_call_id, new_call_id)
        |> Map.put(:streaming_text, "")

      context = build_improvement_context(machine)
      {machine, [{:improve, new_call_id, context}]}
    end)
  end

  # Handle improvement LLM response
  defp handle_improvement_result(machine, {:error, reason}) do
    handle_error(machine, reason)
  end

  defp handle_improvement_result(machine, {:ok, result}) do
    machine = accumulate_usage(machine, result)
    improved_answer = result.text || ""

    # Add to answer history
    answer_history = machine.answer_history ++ [improved_answer]

    # Update latent state
    latent_state =
      machine.latent_state
      |> update_latent_state(:improvement, improved_answer)
      |> Map.update!(:step_count, &(&1 + 1))

    machine =
      machine
      |> Map.put(:current_answer, improved_answer)
      |> Map.put(:answer_history, answer_history)
      |> Map.put(:latent_state, latent_state)
      |> Map.put(:streaming_text, "")

    emit_telemetry(:step, %{system_time: System.system_time()}, %{
      step: machine.supervision_step,
      phase: :improvement,
      call_id: machine.current_call_id
    })

    # Check termination conditions - first check max steps
    if should_terminate_max_steps?(machine) do
      complete_with_best(machine, :max_steps)
    else
      # Use ACT module for sophisticated early stopping decision
      case ACT.make_decision(machine.act_state, machine.latent_state) do
        {:halt, reason} ->
          termination_reason = map_act_halt_reason(reason)

          emit_telemetry(:act_triggered, %{system_time: System.system_time()}, %{
            confidence: machine.act_state.current_confidence,
            threshold: machine.act_threshold,
            step: machine.supervision_step,
            halt_reason: reason,
            expected_improvement: ACT.calculate_expected_improvement(machine.act_state.history)
          })

          complete_with_best(Map.put(machine, :act_triggered, true), termination_reason)

        {:continue, %{expected_improvement: expected}} ->
          emit_telemetry(:act_continue, %{system_time: System.system_time()}, %{
            confidence: machine.act_state.current_confidence,
            threshold: machine.act_threshold,
            step: machine.supervision_step,
            expected_improvement: expected
          })

          # Continue to next reasoning cycle
          continue_reasoning(machine)
      end
    end
  end

  # Map ACT halt reasons to termination reasons
  defp map_act_halt_reason(:threshold_exceeded), do: :act_threshold
  defp map_act_halt_reason(:convergence_detected), do: :convergence_detected
  defp map_act_halt_reason(:max_improvement_reached), do: :act_threshold

  # Continue to next reasoning iteration
  defp continue_reasoning(machine) do
    new_call_id = generate_call_id()

    with_transition(machine, "reasoning", fn machine ->
      machine =
        machine
        |> Map.update!(:supervision_step, &(&1 + 1))
        |> Map.put(:supervision_feedback, nil)
        |> Map.put(:current_call_id, new_call_id)

      context = build_reasoning_context(machine)
      {machine, [{:reason, new_call_id, context}]}
    end)
  end

  # Handle errors
  defp handle_error(machine, reason) do
    duration_ms = calculate_duration(machine)

    emit_telemetry(:error, %{duration: duration_ms}, %{
      step: machine.supervision_step,
      error: reason,
      usage: machine.usage
    })

    with_transition(machine, "error", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, :error)
        |> Map.put(:result, Helpers.safe_error_message(reason))

      {machine, []}
    end)
  end

  # Complete with best answer
  defp complete_with_best(machine, reason) do
    duration_ms = calculate_duration(machine)

    # Use best answer, or current answer if no best yet
    final_answer = machine.best_answer || machine.current_answer

    emit_telemetry(:complete, %{duration: duration_ms}, %{
      termination_reason: reason,
      steps: machine.supervision_step,
      final_score: machine.best_score,
      act_triggered: machine.act_triggered,
      usage: machine.usage
    })

    with_transition(machine, "completed", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, reason)
        |> Map.put(:result, final_answer)

      {machine, []}
    end)
  end

  # Latent state management

  @doc """
  Initializes the latent state from a question and optional initial answer.
  """
  @spec initialize_latent_state(String.t(), String.t() | nil) :: latent_state()
  def initialize_latent_state(question, answer) do
    %{
      question_context: question,
      answer_context: answer,
      reasoning_trace: [],
      confidence_score: 0.0,
      step_count: 0
    }
  end

  @doc """
  Updates the latent state with new reasoning insights.
  """
  @spec update_latent_state(latent_state(), atom(), String.t()) :: latent_state()
  def update_latent_state(latent_state, phase, content) do
    trace_entry = "[#{phase}] #{String.slice(content, 0, 200)}"
    reasoning_trace = merge_reasoning_trace(latent_state.reasoning_trace, trace_entry)

    latent_state
    |> Map.put(:reasoning_trace, reasoning_trace)
    |> Map.put(:answer_context, content)
  end

  @doc """
  Extracts the current confidence score from latent state.
  """
  @spec extract_confidence(latent_state()) :: float()
  def extract_confidence(latent_state) do
    latent_state.confidence_score
  end

  @doc """
  Merges a new entry into the reasoning trace, keeping recent history.
  """
  @spec merge_reasoning_trace([String.t()], String.t()) :: [String.t()]
  def merge_reasoning_trace(trace, new_entry) do
    # Keep last 10 entries to avoid unbounded growth
    (trace ++ [new_entry])
    |> Enum.take(-10)
  end

  # Termination conditions

  @doc """
  Checks if the machine should terminate due to max steps.
  """
  @spec should_terminate_max_steps?(t()) :: boolean()
  def should_terminate_max_steps?(machine) do
    machine.supervision_step >= machine.max_supervision_steps
  end

  @doc """
  Checks the ACT condition for early stopping.
  """
  @spec check_act_condition(t()) :: boolean()
  def check_act_condition(machine) do
    confidence = extract_confidence(machine.latent_state)
    confidence >= machine.act_threshold
  end

  # Context builders for directives

  defp build_reasoning_context(machine) do
    %{
      question: machine.question,
      current_answer: machine.current_answer,
      latent_state: machine.latent_state,
      step: machine.supervision_step
    }
  end

  defp build_supervision_context(machine) do
    %{
      question: machine.question,
      current_answer: machine.current_answer,
      latent_state: machine.latent_state,
      step: machine.supervision_step,
      # Include previous feedback for context in iterative supervision
      previous_feedback: machine.parsed_feedback
    }
  end

  defp build_improvement_context(machine) do
    %{
      question: machine.question,
      current_answer: machine.current_answer,
      feedback: machine.supervision_feedback,
      parsed_feedback: machine.parsed_feedback,
      latent_state: machine.latent_state,
      step: machine.supervision_step
    }
  end

  # Serialization

  @doc """
  Converts the machine state to a map suitable for strategy state storage.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = machine) do
    machine
    |> Map.from_struct()
    |> Map.update!(:status, &status_to_atom/1)
  end

  defp status_to_atom("idle"), do: :idle
  defp status_to_atom("reasoning"), do: :reasoning
  defp status_to_atom("supervising"), do: :supervising
  defp status_to_atom("improving"), do: :improving
  defp status_to_atom("completed"), do: :completed
  defp status_to_atom("error"), do: :error
  defp status_to_atom(status) when is_atom(status), do: status

  @doc """
  Creates a machine from a map (e.g., from strategy state storage).
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    threshold = Map.get(map, :act_threshold, @default_act_threshold)

    %__MODULE__{
      status: parse_status(map[:status]),
      question: Map.get(map, :question),
      current_answer: Map.get(map, :current_answer),
      answer_history: Map.get(map, :answer_history, []),
      latent_state: Map.get(map, :latent_state, initialize_latent_state("", nil)),
      supervision_feedback: Map.get(map, :supervision_feedback),
      parsed_feedback: Map.get(map, :parsed_feedback),
      supervision_step: Map.get(map, :supervision_step, 0),
      max_supervision_steps: Map.get(map, :max_supervision_steps, @default_max_supervision_steps),
      act_threshold: threshold,
      act_state: Map.get(map, :act_state, ACT.new(threshold)),
      act_triggered: Map.get(map, :act_triggered, false),
      best_answer: Map.get(map, :best_answer),
      best_score: Map.get(map, :best_score, 0.0),
      result: Map.get(map, :result),
      current_call_id: Map.get(map, :current_call_id),
      termination_reason: Map.get(map, :termination_reason),
      streaming_text: Map.get(map, :streaming_text, ""),
      usage: Map.get(map, :usage, %{}),
      started_at: Map.get(map, :started_at)
    }
  end

  defp parse_status(nil), do: "idle"
  defp parse_status(s) when is_atom(s), do: Atom.to_string(s)
  defp parse_status(s) when is_binary(s), do: s

  @doc """
  Generates a unique call ID for LLM requests.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id do
    "trm_#{Jido.Util.generate_id()}"
  end

  # Private helpers

  defp with_transition(machine, new_status, fun) do
    case Fsmx.transition(machine, new_status, state_field: :status) do
      {:ok, machine} -> fun.(machine)
      {:error, _} -> {machine, []}
    end
  end

  defp accumulate_usage(machine, result) do
    case Map.get(result, :usage) do
      nil ->
        machine

      new_usage when is_map(new_usage) ->
        current = machine.usage

        merged =
          Map.merge(current, new_usage, fn _k, v1, v2 ->
            (v1 || 0) + (v2 || 0)
          end)

        %{machine | usage: merged}
    end
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(@telemetry_prefix ++ [event], measurements, metadata)
  end

  defp calculate_duration(%{started_at: nil}), do: 0

  defp calculate_duration(%{started_at: started_at}) do
    System.monotonic_time(:millisecond) - started_at
  end
end
