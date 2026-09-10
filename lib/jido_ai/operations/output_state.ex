defmodule Jido.AI.Runtime.OutputState do
  @moduledoc false
  alias Jido.AI.{Output, Session}

  def start(%{output: nil} = state, _value, _context), do: state
  def start(%{output_meta: _} = state, _value, _context), do: state

  def start(state, value, context) do
    raw = raw(value)
    state = Map.put(state, :output_raw, raw)
    report(state, context, :output_started, :started, raw, attempt: 0)
  end

  def validated(%{output: nil} = state, _answer, _context), do: state

  def validated(state, answer, context) do
    opts = [attempt: state.repairs]

    opts =
      if state.repairs > 0,
        do: Keyword.put(opts, :validation_error, state.repair_data.reason),
        else: opts

    status = if state.repairs > 0, do: :repaired, else: :validated
    meta = Output.meta(state.output, status, state.output_raw, opts)
    data = event_data(state.output, :validated, answer, attempt: state.repairs)
    :ok = Session.output(event_context(state, context), :output_validated, meta, data)
    Map.put(state, :output_meta, meta)
  end

  def repair(state, reason, context) do
    report(state, context, :output_repair, :repair, state.output_raw,
      attempt: state.repairs + 1,
      validation_error: reason
    )
  end

  def fail(state, reason, context) do
    reason = Jido.AI.Error.cause(reason)

    if Map.has_key?(state, :output_meta) do
      meta = Output.mark_failed(state.output_meta, reason)
      data = Map.put(meta, :schema_summary, schema_summary(state.output))
      :ok = Session.output(event_context(state, context), :output_failed, meta, data)
    end

    {:error, Jido.AI.Reasoning.failure(state, reason)}
  end

  defp report(state, context, kind, status, value, opts) do
    meta = Output.meta(state.output, status, value, opts)

    :ok =
      Session.output(
        event_context(state, context),
        kind,
        meta,
        Map.put(meta, :schema_summary, schema_summary(state.output))
      )

    Map.put(state, :output_meta, meta)
  end

  defp event_data(output, status, value, opts),
    do: Map.put(Output.meta(output, status, value, opts), :schema_summary, schema_summary(output))

  defp schema_summary(output) do
    schema = Output.json_schema(output)

    %{
      schema_kind: output.schema_kind,
      required: schema["required"] || schema[:required] || [],
      properties: Map.keys(schema["properties"] || schema[:properties] || %{}) |> Enum.sort()
    }
  end

  defp event_context(state, context) do
    Map.put(context, :jido_ai_output_event, %{
      request_id: state.request_id,
      origin: :agent_turn,
      method: state.profile.reasoning.method,
      run_id: state.run_id,
      iteration: state.iterations,
      llm_call_id: state[:llm_call_id],
      model: Jido.AI.Runtime.ModelCall.label(state.model),
      observability: state.profile.observability
    })
  end

  def raw(%ReqLLM.Response{} = response) do
    case ReqLLM.Response.text(response) do
      text when is_binary(text) and text != "" -> text
      _ -> response.object || ""
    end
  end

  def raw(value), do: value

  @doc false
  def content(value) do
    case raw(value) do
      text when is_binary(text) ->
        text

      nil ->
        ""

      other ->
        case Jason.encode(other) do
          {:ok, text} -> text
          {:error, _} -> Kernel.inspect(other)
        end
    end
  end
end
