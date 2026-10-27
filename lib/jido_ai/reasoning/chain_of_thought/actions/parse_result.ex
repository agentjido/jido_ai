defmodule Jido.AI.Reasoning.ChainOfThought.Actions.ParseResult do
  @moduledoc "Parses numbered steps and a conclusion into the terminal result."

  use Jido.Action,
    id: "jido.ai/reasoning/chain-of-thought/actions/parse-result",
    vsn: 1,
    name: "jido_ai_chain_of_thought_parse_result",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @conclusion ~r/^\s*(?:\#{1,6}\s*)?(?:\*\*|__)?(?:conclusion|answer|final answer)\s*[:\-]?(?:\*\*|__)?\s*(.*)$/i
  @step ~r/^\s*(?:\#{1,6}\s*)?(?:\*\*|__)?(?:step\s+)?(\d+)[.:)](?:\*\*|__)?\s*(.*)$/i

  @impl Jido.Action
  def run(%{turn: %{model_outcome: %{status: :error}} = turn}, _context) do
    {:ok, terminal(turn, :failed, :model, turn.model_outcome.reason)}
  end

  def run(%{turn: %{model_outcome: %{status: :budget}} = turn}, _context) do
    {:ok, terminal(turn, :failed, :limits, turn.model_outcome.reason)}
  end

  def run(%{turn: %{output_allowed: false} = turn}, _context) do
    {:ok, terminal(turn, :blocked, :output, turn.output_reason)}
  end

  def run(%{turn: turn}, _context) do
    raw = turn.model_outcome.text
    {steps, conclusion} = parse(raw)

    reasoning = %{
      method: :chain_of_thought,
      steps: steps,
      steps_count: length(steps),
      conclusion: conclusion,
      raw_response: raw
    }

    result = %{
      status: :completed,
      output: conclusion || raw,
      model_calls: turn.model_calls,
      tool_rounds: 0,
      tool_calls: 0,
      tool_errors: 0,
      retries: turn.retries,
      guardrail: :none,
      reason: "",
      reasoning: reasoning
    }

    {:ok, %{turn: turn, result: result}}
  end

  @doc "Extracts numbered steps and the marked conclusion from model text."
  @spec parse(term()) :: {[map()], String.t() | nil}
  def parse(text) when is_binary(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.reduce({[], nil, nil}, &parse_line/2)
    |> finish()
  end

  def parse(_text), do: {[], nil}

  defp parse_line(line, {steps, conclusion, current}) do
    cond do
      conclusion ->
        {steps, append(conclusion, line), current}

      match = Regex.run(@conclusion, String.trim(line)) ->
        [_, value] = match
        {flush(steps, current), String.trim(value), nil}

      match = Regex.run(@step, line) ->
        [_, number, content] = match
        next = %{number: String.to_integer(number), content: String.trim(content)}
        {flush(steps, current), nil, next}

      current && String.trim(line) != "" ->
        {steps, nil, %{current | content: append(current.content, line)}}

      true ->
        {steps, nil, current}
    end
  end

  defp finish({steps, conclusion, current}) do
    conclusion = if conclusion in [nil, ""], do: nil, else: String.trim(conclusion)
    {flush(steps, current), conclusion}
  end

  defp flush(steps, nil), do: steps
  defp flush(steps, step), do: steps ++ [step]
  defp append("", value), do: String.trim(value)
  defp append(value, line), do: String.trim(value <> "\n" <> line)

  defp terminal(turn, status, guardrail, reason) do
    %{
      turn: turn,
      result: %{
        status: status,
        output: "",
        model_calls: turn.model_calls,
        tool_rounds: 0,
        tool_calls: 0,
        tool_errors: 0,
        retries: turn.retries,
        guardrail: guardrail,
        reason: reason,
        reasoning: %{
          method: :chain_of_thought,
          steps: [],
          steps_count: 0,
          conclusion: nil,
          raw_response: ""
        }
      }
    }
  end
end
