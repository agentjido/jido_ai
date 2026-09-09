defmodule Jido.AI.Reasoning.AlgorithmOfThoughts do
  @moduledoc "AoT prompt, parser and structured result rules over the shared Agent/Flow runtime."
  alias Jido.AI.{Output, Profile, Reasoning}
  alias Jido.AI.Reasoning.AlgorithmOfThoughts.{Machine, Result, Strategy}

  def method, do: :algorithm_of_thoughts

  @deprecated "Use method/0 for profile selection and get_result/1 for stored results"
  def strategy_module, do: Strategy

  defdelegate generate_call_id(), to: Machine
  defdelegate default_system_prompt(profile, search_style, examples \\ []), to: Machine

  @doc "Reads an AoT result from the latest retained request or an explicit request ID."
  def get_result(%Jido.Agent{} = agent, request_id \\ nil) do
    case Jido.AI.Reasoning.Linear.stored_record(agent, method(), request_id) do
      %{result: result} when is_map(result) -> result
      %{error: {:failed, _, result}} when is_map(result) -> result
      _ -> nil
    end
  end

  @doc false
  def options(value) do
    with {:ok, value} <-
           Profile.fields(
             value,
             [:profile, :search_style, :examples, :require_explicit_answer],
             "reasoning.options"
           ),
         options =
           Map.merge(
             %{
               profile: :standard,
               search_style: :dfs,
               examples: [],
               require_explicit_answer: true
             },
             value
           ),
         true <- options.profile in [:short, :standard, :long],
         true <- options.search_style in [:dfs, :bfs],
         true <- is_boolean(options.require_explicit_answer),
         true <- is_list(options.examples) and Enum.all?(options.examples, &is_binary/1) do
      {:ok,
       %{
         options
         | examples: options.examples |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
       }}
    else
      false ->
        Profile.error(
          "reasoning.options",
          "Expected an AoT profile, dfs/bfs search, text examples and an explicit-answer boolean"
        )

      error ->
        error
    end
  end

  @doc false
  def instructions(profile, output) do
    options = profile.reasoning.options

    prompt =
      if profile.instructions in [nil, ""],
        do: default_system_prompt(options.profile, options.search_style, options.examples),
        else: profile.instructions

    format =
      if output,
        do:
          "The final answer line must contain JSON that matches this schema:\n" <>
            Jason.encode!(Output.json_schema(output))

    [prompt, format]
  end

  @doc false
  def parse(state, value) do
    raw = Reasoning.raw(value)
    options = state.profile.reasoning.options
    # A successful repair callback returns an already validated value, not model search text.
    callback? =
      state.repairs > 0 and state.output != nil and state.output.repair_fun != nil and
        not is_struct(value, ReqLLM.Response)

    parsed =
      if callback?,
        do: %{
          answer: value,
          success?: true,
          found_solution?: true,
          reason: :success,
          diagnostics: %{parser_mode: :repair_callback}
        },
        else: Machine.parse_response(raw, options.require_explicit_answer)

    result =
      Result.build(
        machine(state),
        parsed,
        parsed.reason,
        if(parsed.success?, do: :completed, else: :error),
        raw
      )

    if parsed.success? do
      with {:ok, answer} <- validate_answer(state.output, result.answer) do
        result = %{result | answer: answer}

        {:ok, result, %{termination_reason: :success, reasoning: %{method: method(), result: result}}}
      end
    else
      {:method_error, {:failed, parsed.reason, result}}
    end
  end

  defp validate_answer(nil, answer), do: {:ok, answer}
  defp validate_answer(output, answer), do: Output.parse(output, answer)

  @doc false
  def failure(_, {:failed, _, %{termination: _}} = reason), do: reason

  def failure(state, reason) do
    parsed = %{diagnostics: %{error: inspect(reason), cause: reason}}
    raw = if state[:response], do: Reasoning.raw(state.response), else: ""
    {:failed, :error, Result.build(machine(state), parsed, :error, :error, raw)}
  end

  defp machine(state) do
    machine = Machine.new(Map.to_list(state.profile.reasoning.options))
    %{machine | started_at: state.deadline - state.profile.controls.timeout, usage: state.usage}
  end
end
