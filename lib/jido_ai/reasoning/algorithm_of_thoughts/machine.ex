defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.Machine do
  @moduledoc """
  Pure state machine for Algorithm-of-Thoughts (AoT) reasoning.

  AoT in this implementation is intentionally single-query: one LLM generation pass
  that demonstrates algorithmic search behavior in-context and extracts a final answer.
  """

  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "idle" => ["exploring"],
      "exploring" => ["completed", "error"],
      "completed" => [],
      "error" => []
    }

  alias Jido.AI.Reasoning.AlgorithmOfThoughts.Result
  alias Jido.AI.Turn

  @typedoc "Internal machine status (string) - required by Fsmx"
  @type internal_status :: String.t()

  @typedoc "External status used by strategy snapshots"
  @type external_status :: :idle | :exploring | :completed | :error

  @type profile :: :short | :standard | :long
  @type search_style :: :dfs | :bfs
  @type termination_reason :: :success | :missing_explicit_answer | :no_solution | :error | nil

  @type usage :: %{
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          status: internal_status(),
          prompt: String.t() | nil,
          profile: profile(),
          search_style: search_style(),
          temperature: float(),
          max_tokens: pos_integer(),
          examples: [String.t()],
          require_explicit_answer: boolean(),
          current_call_id: String.t() | nil,
          result: map() | nil,
          termination_reason: termination_reason(),
          streaming_text: String.t(),
          usage: usage(),
          started_at: integer() | nil
        }

  defstruct status: "idle",
            prompt: nil,
            profile: :standard,
            search_style: :dfs,
            temperature: 0.0,
            max_tokens: 2048,
            examples: [],
            require_explicit_answer: true,
            current_call_id: nil,
            result: nil,
            termination_reason: nil,
            streaming_text: "",
            usage: %{},
            started_at: nil

  @type msg ::
          {:start, String.t(), String.t()}
          | {:llm_result, String.t(), term()}
          | {:llm_partial, String.t(), String.t(), atom()}

  @type directive ::
          {:call_llm_stream, String.t(), list()}
          | {:request_error, String.t(), atom(), String.t()}

  @doc """
  Builds a new AoT machine with configurable strategy options.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      profile: Keyword.get(opts, :profile, :standard),
      search_style: Keyword.get(opts, :search_style, :dfs),
      temperature: normalize_temperature(Keyword.get(opts, :temperature, 0.0)),
      max_tokens: Keyword.get(opts, :max_tokens, 2048),
      examples: normalize_examples(Keyword.get(opts, :examples, [])),
      require_explicit_answer: Keyword.get(opts, :require_explicit_answer, true)
    }
  end

  @doc """
  Applies a machine event and returns `{updated_machine, directives}`.
  """
  @spec update(t(), msg(), map()) :: {t(), [directive()]}
  def update(machine, msg, env \\ %{})

  def update(%__MODULE__{status: "idle"} = machine, {:start, prompt, call_id}, env) do
    started_at = System.monotonic_time(:millisecond)

    with_transition(machine, "exploring", fn machine ->
      machine =
        machine
        |> Map.put(:prompt, prompt)
        |> Map.put(:result, nil)
        |> Map.put(:termination_reason, nil)
        |> Map.put(:current_call_id, call_id)
        |> Map.put(:streaming_text, "")
        |> Map.put(:usage, %{})
        |> Map.put(:started_at, started_at)

      context = build_generation_context(machine, prompt, env)
      {machine, [{:call_llm_stream, call_id, context}]}
    end)
  end

  # Issue #3 parity: explicitly reject start while busy
  def update(%__MODULE__{status: "exploring"} = machine, {:start, _prompt, call_id}, _env) do
    {machine, [{:request_error, call_id, :busy, "Agent is busy (status: exploring)"}]}
  end

  def update(%__MODULE__{status: "exploring"} = machine, {:llm_partial, call_id, delta, chunk_type}, _env) do
    if call_id == machine.current_call_id and chunk_type == :content do
      {Map.update!(machine, :streaming_text, &(&1 <> delta)), []}
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{status: "exploring"} = machine, {:llm_result, call_id, result}, _env) do
    if call_id == machine.current_call_id do
      handle_llm_result(machine, result)
    else
      {machine, []}
    end
  end

  def update(machine, _msg, _env), do: {machine, []}

  @doc """
  Converts machine state into strategy-storable map form.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = machine) do
    machine
    |> Map.from_struct()
    |> Map.update!(:status, &status_to_atom/1)
  end

  @doc """
  Rebuilds a machine struct from strategy state map data.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    status =
      case map[:status] do
        s when is_atom(s) -> Atom.to_string(s)
        s when is_binary(s) -> s
        _ -> "idle"
      end

    %__MODULE__{
      status: status,
      prompt: map[:prompt],
      profile: map[:profile] || :standard,
      search_style: map[:search_style] || :dfs,
      temperature: normalize_temperature(map[:temperature] || 0.0),
      max_tokens: map[:max_tokens] || 2048,
      examples: normalize_examples(map[:examples] || []),
      require_explicit_answer: if(is_nil(map[:require_explicit_answer]), do: true, else: map[:require_explicit_answer]),
      current_call_id: map[:current_call_id],
      result: map[:result],
      termination_reason: map[:termination_reason],
      streaming_text: map[:streaming_text] || "",
      usage: map[:usage] || %{},
      started_at: map[:started_at]
    }
  end

  @doc """
  Generates a unique call id for AoT LLM stream requests.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id, do: "aot_#{Jido.Util.generate_id()}"

  @doc """
  Returns the default AoT system prompt for a profile/search-style pair.
  """
  @spec default_system_prompt(profile(), search_style(), [String.t()]) :: String.t()
  def default_system_prompt(profile, search_style, examples \\ []) do
    example_text =
      examples
      |> case do
        [] -> default_examples(profile)
        provided -> provided
      end
      |> Enum.join("\n\n")

    """
    You are an Algorithm-of-Thoughts reasoning assistant.

    Follow this execution pattern:
    1. Propose promising first operations.
    2. Expand local branches with concrete calculations.
    3. Backtrack when needed.
    4. Finalize with an explicit line: "answer: ..."

    Search style preference: #{search_style}.

    Always include:
    - "Trying a promising first operation:" markers
    - "Backtracking the solution:" before final derivation when solved
    - Explicit final answer line

    Algorithmic examples:
    #{example_text}
    """
  end

  @doc """
  Parses free-form AoT response text into the structured AoT result shape.
  """
  @spec parse_response(String.t(), boolean()) :: map()
  def parse_response(text, require_explicit_answer \\ true)

  def parse_response(text, require_explicit_answer) when is_binary(text) do
    normalized = String.trim(text)
    answer = extract_answer(normalized)

    first_ops_by_phrase =
      Regex.scan(~r/Trying\s+(?:another\s+)?promising\s+first\s+operation\s*:/i, normalized)
      |> length()

    first_ops_by_index =
      Regex.scan(~r/(?:^|\n)\s*\d+\.\s*[^:\n]+:\s*\([^\)]*\)/m, normalized)
      |> length()

    first_operations_considered = max(first_ops_by_phrase, first_ops_by_index)

    backtracking_steps =
      Regex.scan(~r/(?:^|\n)\s*Step\s*\d+\s*:/i, normalized)
      |> length()

    found_markers =
      Regex.scan(~r/found\s+it|solution\s+found|answer\s*:/i, normalized)
      |> length()

    found_solution? = found_markers > 0 or not is_nil(answer)

    success? =
      cond do
        require_explicit_answer -> is_binary(answer) and answer != ""
        true -> found_solution?
      end

    reason =
      cond do
        success? -> :success
        found_solution? and is_nil(answer) -> :missing_explicit_answer
        true -> :no_solution
      end

    %{
      answer: answer,
      found_solution?: found_solution?,
      first_operations_considered: first_operations_considered,
      backtracking_steps: backtracking_steps,
      success?: success?,
      reason: reason,
      diagnostics: %{
        explicit_answer_required: require_explicit_answer,
        explicit_answer_found: not is_nil(answer),
        non_finalization_detected: found_solution? and is_nil(answer),
        found_markers: found_markers,
        parser_mode: :regex
      }
    }
  end

  def parse_response(_, require_explicit_answer), do: parse_response("", require_explicit_answer)

  @doc """
  Extracts an explicit final answer line from model output text.
  """
  @spec extract_answer(String.t()) :: String.t() | nil
  def extract_answer(text) when is_binary(text) do
    patterns = [
      ~r/(?:^|\n)\s*answer\s*[:：]\s*(.+)$/im,
      ~r/(?:^|\n)\s*final\s+answer\s*[:：]\s*(.+)$/im
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text, capture: :all_but_first) do
        [answer] -> String.trim(answer)
        _ -> nil
      end
    end)
  end

  def extract_answer(_), do: nil

  defp handle_llm_result(machine, {:error, reason, _effects}) do
    handle_llm_result(machine, {:error, reason})
  end

  defp handle_llm_result(machine, {:ok, result, _effects}) do
    handle_llm_result(machine, {:ok, result})
  end

  defp handle_llm_result(machine, {:error, reason}) do
    with_transition(machine, "error", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, :error)
        |> Map.put(:result, error_result(machine, reason))

      {machine, []}
    end)
  end

  defp handle_llm_result(machine, {:ok, result}) do
    {text, usage} = extract_text_and_usage(result, machine.streaming_text)
    machine = machine |> Map.put(:streaming_text, "") |> Map.put(:usage, usage)

    parsed = parse_response(text, machine.require_explicit_answer)

    if parsed.success? do
      with_transition(machine, "completed", fn machine ->
        machine =
          machine
          |> Map.put(:termination_reason, :success)
          |> Map.put(:result, Result.build(machine, parsed, :success, :completed, text))

        {machine, []}
      end)
    else
      reason = parsed.reason

      with_transition(machine, "error", fn machine ->
        machine =
          machine
          |> Map.put(:termination_reason, reason)
          |> Map.put(:result, Result.build(machine, parsed, reason, :error, text))

        {machine, []}
      end)
    end
  end

  defp with_transition(machine, new_status, fun) do
    case Fsmx.transition(machine, new_status, state_field: :status) do
      {:ok, machine} -> fun.(machine)
      {:error, _} -> {machine, []}
    end
  end

  defp status_to_atom("idle"), do: :idle
  defp status_to_atom("exploring"), do: :exploring
  defp status_to_atom("completed"), do: :completed
  defp status_to_atom("error"), do: :error
  defp status_to_atom(status) when is_atom(status), do: status

  defp extract_text_and_usage(result, fallback_streaming_text) do
    case result do
      text when is_binary(text) ->
        {text, %{}}

      %{text: text} = map when is_binary(text) ->
        {text, normalize_usage(Map.get(map, :usage))}

      %{"text" => text} = map when is_binary(text) ->
        {text, normalize_usage(Map.get(map, "usage"))}

      %{content: content} = map when is_binary(content) ->
        {content, normalize_usage(Map.get(map, :usage))}

      %{"content" => content} = map when is_binary(content) ->
        {content, normalize_usage(Map.get(map, "usage"))}

      %{} ->
        turn = Turn.from_response(result)

        text =
          case turn.text do
            text when is_binary(text) and text != "" -> text
            _ -> fallback_streaming_text || ""
          end

        usage = normalize_usage(turn.usage || %{})
        {text, usage}

      _ ->
        {fallback_streaming_text || "", %{}}
    end
  end

  defp normalize_usage(usage) when is_map(usage) do
    input = Map.get(usage, :input_tokens, Map.get(usage, "input_tokens", 0))
    output = Map.get(usage, :output_tokens, Map.get(usage, "output_tokens", 0))
    total = Map.get(usage, :total_tokens, Map.get(usage, "total_tokens", input + output))

    %{
      input_tokens: max(input, 0),
      output_tokens: max(output, 0),
      total_tokens: max(total, 0)
    }
  end

  defp normalize_usage(_), do: %{}

  defp error_result(machine, reason) do
    %{
      answer: nil,
      found_solution?: false,
      first_operations_considered: 0,
      backtracking_steps: 0,
      raw_response: machine.streaming_text || "",
      usage: machine.usage || %{},
      termination: %{
        reason: :error,
        status: :error,
        duration_ms: duration_ms(machine)
      },
      diagnostics: %{
        error: inspect(reason)
      }
    }
  end

  defp duration_ms(%__MODULE__{started_at: nil}), do: 0
  defp duration_ms(%__MODULE__{started_at: started_at}), do: System.monotonic_time(:millisecond) - started_at

  defp normalize_temperature(temp) when is_number(temp), do: temp * 1.0
  defp normalize_temperature(_), do: 0.0

  defp normalize_examples(examples) when is_list(examples) do
    examples
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_examples(_), do: []

  defp build_generation_context(machine, prompt, env) do
    profile = Map.get(env, :profile, machine.profile)
    search_style = Map.get(env, :search_style, machine.search_style)
    examples = normalize_examples(Map.get(env, :examples, machine.examples))

    system_prompt = default_system_prompt(profile, search_style, examples)

    user_prompt =
      """
      Solve this problem using Algorithm-of-Thoughts style search and return an explicit final line as:
      answer: <final answer>

      Problem:
      #{prompt}
      """

    [
      %{role: :system, content: system_prompt},
      %{role: :user, content: String.trim(user_prompt)}
    ]
  end

  defp default_examples(:short) do
    [
      """
      User: 8 6 4 4
      Assistant:
      Trying a promising first operation:
      1. 8 - 6 : (4, 4, 2)
      - 4 + 2 : (6, 4) 24 = 6 * 4 -> found it!
      Backtracking the solution:
      Step 1: 8 - 6 = 2
      Step 2: 4 + 2 = 6
      Step 3: 6 * 4 = 24
      answer: (4 + (8 - 6)) * 4 = 24
      """
    ]
  end

  defp default_examples(:long) do
    default_examples(:standard) ++
      [
        """
        User: 9 8 2 1
        Assistant:
        Trying a promising first operation:
        1. 9 - 1 : (8, 8, 2)
        - 8 * 2 : (16, 8) 24 = 16 + 8 -> found it!
        Backtracking the solution:
        Step 1: 9 - 1 = 8
        Step 2: 8 * 2 = 16
        Step 3: 16 + 8 = 24
        answer: ((9 - 1) * 2) + 8 = 24
        """
      ]
  end

  defp default_examples(:standard) do
    [
      """
      User: 14 8 8 2
      Assistant:
      Trying a promising first operation:
      1. 8 / 2 : (14, 8, 4)
      - 14 - 8 : (6, 4) 24 = 6 * 4 -> found it!
      Backtracking the solution:
      Step 1: 8 / 2 = 4
      Step 2: 14 - 8 = 6
      Step 3: 6 * 4 = 24
      answer: (14 - 8) * (8 / 2) = 24
      """,
      """
      User: 9 5 5 5
      Assistant:
      Trying a promising first operation:
      1. 5 + 5 : (10, 9, 5)
      - 10 + 9 : (19, 5) 24 = 19 + 5 -> found it!
      Backtracking the solution:
      Step 1: 5 + 5 = 10
      Step 2: 10 + 9 = 19
      Step 3: 19 + 5 = 24
      answer: ((5 + 5) + 9) + 5 = 24
      """
    ]
  end
end
