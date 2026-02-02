defmodule Jido.AI.ChainOfThought.Machine do
  @moduledoc """
  Pure state machine for the Chain-of-Thought (CoT) reasoning pattern.

  This module implements state transitions for a CoT agent without any side effects.
  It uses Fsmx for state machine management and returns directives that describe
  what external effects should be performed.

  ## Overview

  Chain-of-Thought prompting encourages LLMs to break down complex problems into
  intermediate steps before providing a final answer. This leads to better reasoning
  on multi-step problems like math, logic, and common sense reasoning.

  ## States

  - `:idle` - Initial state, waiting for a prompt
  - `:reasoning` - Waiting for LLM response with reasoning
  - `:completed` - Final state, reasoning complete
  - `:error` - Error state

  ## Usage

  The machine is used by the CoT strategy:

      machine = Machine.new()
      {machine, directives} = Machine.update(machine, {:start, prompt, call_id}, env)

  All state transitions are pure - side effects are described in directives.

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
      "reasoning" => ["completed", "error"],
      "completed" => [],
      "error" => []
    }

  # Telemetry event names
  @telemetry_prefix [:jido, :ai, :cot]

  @typedoc "Internal machine status (string) - required by Fsmx library"
  @type internal_status :: String.t()

  @typedoc "External status (atom) - used in strategy state after to_map/1 conversion"
  @type external_status :: :idle | :reasoning | :completed | :error

  @type termination_reason :: :success | :error | nil

  @type step :: %{
          number: pos_integer(),
          content: String.t()
        }

  @type usage :: %{
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          status: internal_status(),
          prompt: String.t() | nil,
          steps: [step()],
          conclusion: String.t() | nil,
          raw_response: String.t() | nil,
          result: term(),
          current_call_id: String.t() | nil,
          termination_reason: termination_reason(),
          streaming_text: String.t(),
          usage: usage(),
          started_at: integer() | nil
        }

  defstruct status: "idle",
            prompt: nil,
            steps: [],
            conclusion: nil,
            raw_response: nil,
            result: nil,
            current_call_id: nil,
            termination_reason: nil,
            streaming_text: "",
            usage: %{},
            started_at: nil

  @type msg ::
          {:start, prompt :: String.t(), call_id :: String.t()}
          | {:llm_result, call_id :: String.t(), result :: term()}
          | {:llm_partial, call_id :: String.t(), delta :: String.t(), chunk_type :: atom()}

  @type directive ::
          {:call_llm_stream, id :: String.t(), context :: list()}

  @doc """
  Creates a new machine in the idle state.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Updates the machine state based on a message.

  Returns the updated machine and a list of directives describing
  external effects to be performed.

  ## Messages

  - `{:start, prompt, call_id}` - Start CoT reasoning
  - `{:llm_result, call_id, result}` - Handle LLM response
  - `{:llm_partial, call_id, delta, chunk_type}` - Handle streaming chunk

  ## Directives

  - `{:call_llm_stream, id, context}` - Request LLM call with CoT prompt
  """
  @spec update(t(), msg(), map()) :: {t(), [directive()]}
  def update(machine, msg, env \\ %{})

  def update(%__MODULE__{status: "idle"} = machine, {:start, prompt, call_id}, env) do
    system_prompt = Map.get(env, :system_prompt, default_system_prompt())
    conversation = [system_message(system_prompt), user_message(prompt)]
    started_at = System.monotonic_time(:millisecond)

    # Emit start telemetry
    emit_telemetry(:start, %{system_time: System.system_time()}, %{
      call_id: call_id,
      prompt_length: String.length(prompt)
    })

    with_transition(machine, "reasoning", fn machine ->
      machine =
        machine
        |> Map.put(:prompt, prompt)
        |> Map.put(:steps, [])
        |> Map.put(:conclusion, nil)
        |> Map.put(:raw_response, nil)
        |> Map.put(:result, nil)
        |> Map.put(:current_call_id, call_id)
        |> Map.put(:termination_reason, nil)
        |> Map.put(:streaming_text, "")
        |> Map.put(:usage, %{})
        |> Map.put(:started_at, started_at)

      {machine, [{:call_llm_stream, call_id, conversation}]}
    end)
  end

  # Issue #3 fix: Explicitly reject start requests when busy instead of silently dropping
  def update(%__MODULE__{status: "reasoning"} = machine, {:start, _prompt, call_id}, _env) do
    {machine, [{:request_error, call_id, :busy, "Agent is busy (status: reasoning)"}]}
  end

  def update(%__MODULE__{status: "reasoning"} = machine, {:llm_result, call_id, result}, _env) do
    if call_id == machine.current_call_id do
      handle_llm_response(machine, result)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{status: "reasoning"} = machine, {:llm_partial, call_id, delta, chunk_type}, _env) do
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

  def update(machine, _msg, _env) do
    {machine, []}
  end

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
  defp status_to_atom("completed"), do: :completed
  defp status_to_atom("error"), do: :error
  defp status_to_atom(status) when is_atom(status), do: status

  @doc """
  Creates a machine from a map (e.g., from strategy state storage).
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    status =
      case map[:status] do
        s when is_atom(s) -> Atom.to_string(s)
        s when is_binary(s) -> s
        nil -> "idle"
      end

    %__MODULE__{
      status: status,
      prompt: map[:prompt],
      steps: map[:steps] || [],
      conclusion: map[:conclusion],
      raw_response: map[:raw_response],
      result: map[:result],
      current_call_id: map[:current_call_id],
      termination_reason: map[:termination_reason],
      streaming_text: map[:streaming_text] || "",
      usage: map[:usage] || %{},
      started_at: map[:started_at]
    }
  end

  @doc """
  Generates a unique call ID for LLM requests.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id do
    "cot_#{Jido.Util.generate_id()}"
  end

  @doc """
  Returns the default CoT system prompt.
  """
  @spec default_system_prompt() :: String.t()
  def default_system_prompt do
    """
    You are a helpful AI assistant that thinks through problems step by step.

    When solving problems:
    1. Break down the problem into clear, logical steps
    2. Show your reasoning for each step
    3. Number your steps (Step 1:, Step 2:, etc.)
    4. After all steps, provide your final answer clearly marked as "Conclusion:" or "Answer:"

    Think carefully and explain your reasoning at each step.
    """
  end

  # Private helpers

  defp with_transition(machine, new_status, fun) do
    case Fsmx.transition(machine, new_status, state_field: :status) do
      {:ok, machine} -> fun.(machine)
      {:error, _} -> {machine, []}
    end
  end

  defp handle_llm_response(machine, {:error, reason}) do
    duration_ms = calculate_duration(machine)

    emit_telemetry(:complete, %{duration: duration_ms}, %{
      termination_reason: :error,
      error: reason,
      usage: machine.usage
    })

    with_transition(machine, "error", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, :error)
        |> Map.put(:result, "Error: #{inspect(reason)}")

      {machine, []}
    end)
  end

  defp handle_llm_response(machine, {:ok, result}) do
    # Extract usage
    machine = accumulate_usage(machine, result)

    # Get the response text
    response_text = result.text || ""

    # Extract steps and conclusion
    {steps, conclusion} = extract_steps_and_conclusion(response_text)

    duration_ms = calculate_duration(machine)

    emit_telemetry(:complete, %{duration: duration_ms}, %{
      termination_reason: :success,
      steps_count: length(steps),
      usage: machine.usage
    })

    with_transition(machine, "completed", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, :success)
        |> Map.put(:raw_response, response_text)
        |> Map.put(:steps, steps)
        |> Map.put(:conclusion, conclusion)
        |> Map.put(:result, conclusion || response_text)

      {machine, []}
    end)
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

  @doc """
  Extracts reasoning steps and conclusion from LLM response text.

  Supports multiple formats:
  - Numbered steps: "Step 1:", "1.", "1)"
  - Bullet points: "- ", "* ", "• "
  - Conclusion markers: "Conclusion:", "Answer:", "Therefore:", "Final Answer:"

  Returns `{steps, conclusion}` where steps is a list of step maps and
  conclusion is the final answer string or nil.
  """
  @spec extract_steps_and_conclusion(String.t()) :: {[step()], String.t() | nil}
  def extract_steps_and_conclusion(text) when is_binary(text) do
    # Split into lines for processing
    lines = String.split(text, ~r/\r?\n/, trim: false)

    # Try to find conclusion first
    {content_lines, conclusion} = extract_conclusion(lines)

    # Extract steps from the content
    steps = extract_steps(Enum.join(content_lines, "\n"))

    {steps, conclusion}
  end

  def extract_steps_and_conclusion(_), do: {[], nil}

  # Extract conclusion from lines
  defp extract_conclusion(lines) do
    conclusion_patterns = [
      ~r/^(?:conclusion|answer|therefore|final answer|in conclusion|thus|hence|so)\s*[:\-]?\s*/i
    ]

    # Find the index of conclusion marker
    conclusion_idx =
      Enum.find_index(lines, fn line ->
        trimmed = String.trim(line)
        Enum.any?(conclusion_patterns, &Regex.match?(&1, trimmed))
      end)

    case conclusion_idx do
      nil ->
        {lines, nil}

      idx ->
        content_lines = Enum.take(lines, idx)
        conclusion_lines = Enum.drop(lines, idx)

        conclusion =
          conclusion_lines
          |> Enum.join("\n")
          |> String.replace(
            ~r/^(?:conclusion|answer|therefore|final answer|in conclusion|thus|hence|so)\s*[:\-]?\s*/i,
            ""
          )
          |> String.trim()

        conclusion = if conclusion != "", do: conclusion

        {content_lines, conclusion}
    end
  end

  # Extract steps from text
  defp extract_steps(text) do
    # Pattern for numbered steps at the beginning of a line:
    # "Step 1:", "Step 1.", "1.", "1)", "1:"
    # Must be at line start or after newline
    step_pattern = ~r/(?:^|\n)\s*(?:step\s+)?(\d+)[.:\)]\s*/i

    # Find all matches with their positions
    matches = Regex.scan(step_pattern, text, return: :index)

    if matches == [] do
      # Try bullet points if no numbered steps
      extract_bullet_steps(text)
    else
      # Extract step content between markers
      extract_steps_from_matches(text, matches)
    end
  end

  defp extract_steps_from_matches(text, matches) do
    # Get start positions and step numbers
    positions =
      matches
      |> Enum.map(fn [{start, len} | _] ->
        matched = String.slice(text, start, len)

        number =
          case Regex.run(~r/(\d+)/, matched) do
            [_, n] -> String.to_integer(n)
            _ -> 0
          end

        {start + len, number}
      end)

    # Add end position for last step
    positions_with_end = positions ++ [{String.length(text), nil}]

    # Extract content between positions
    positions
    |> Enum.with_index()
    |> Enum.map(fn {{start_pos, number}, idx} ->
      {next_pos, _} = Enum.at(positions_with_end, idx + 1)

      content =
        String.slice(text, start_pos, next_pos - start_pos)
        |> String.trim()
        # Remove trailing newlines
        |> String.replace(~r/\n\s*$/, "")

      %{number: number, content: content}
    end)
    |> Enum.filter(fn step -> step.content != "" end)
  end

  # Extract bullet point steps
  defp extract_bullet_steps(text) do
    bullet_pattern = ~r/^[\-\*•]\s+/m

    # Only extract if there are actual bullet points in the text
    if Regex.match?(bullet_pattern, text) do
      parts =
        text
        |> String.split(bullet_pattern, trim: true)
        |> Enum.filter(&(String.trim(&1) != ""))

      parts
      |> Enum.with_index(1)
      |> Enum.map(fn {content, idx} ->
        %{
          number: idx,
          content: String.trim(content)
        }
      end)
    else
      []
    end
  end

  # Message builders
  defp system_message(content), do: %{role: :system, content: content}
  defp user_message(content), do: %{role: :user, content: content}

  # Telemetry helpers
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(@telemetry_prefix ++ [event], measurements, metadata)
  end

  defp calculate_duration(%{started_at: nil}), do: 0

  defp calculate_duration(%{started_at: started_at}) do
    System.monotonic_time(:millisecond) - started_at
  end
end
