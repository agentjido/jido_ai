defmodule Jido.AI.Model.Generate do
  @moduledoc "One provider request through ReqLLM. Core Exec owns its work lifetime."
  use Jido.Action, name: "ai_generate"

  @impl Jido.Action
  def run(params, context),
    do:
      Jido.AI.Error.capture(fn ->
        original = params.messages
        provider = Jido.AI.Model.Messages.provider_context(original)

        Jido.AI.Quota.track(context, fn progress ->
          with {:ok, result} <- execute(%{params | messages: provider}, context, progress) do
            response = Jido.AI.Model.Messages.restore_response_context(result.response, provider, original)
            {:ok, %{result | response: response}}
          end
        end)
      end)

  defp execute(
         %{stream: true, model: model, messages: messages, options: opts, schema: schema},
         context,
         progress
       ) do
    kind = if is_nil(schema), do: :stream, else: :stream_object

    with {:ok, stream} <- Jido.AI.Model.Transport.request(kind, model, messages, opts, schema) do
      try do
        callbacks = [
          on_chunk: fn chunk ->
            progress.(Map.get(chunk.metadata, :usage, %{}))
            Jido.AI.Session.activity(context)

            case Jido.AI.Turn.stream_content_part(chunk) do
              {:ok, part} -> delta(context, model, :content_part, part)
              :error -> :ok
            end
          end,
          on_result: fn text -> delta(context, model, :content, text) end,
          on_thinking: fn text -> delta(context, model, :thinking, text) end,
          on_tool_call: fn chunk -> delta(context, model, :tool_call, chunk.name) end
        ]

        with {:ok, response} <- Jido.AI.Usage.Stream.process(stream, callbacks),
             do: {:ok, %{response: Jido.AI.Model.Messages.align_context(response)}}
      after
        ReqLLM.StreamResponse.close(stream)
      end
    end
  end

  defp execute(%{model: model, messages: messages, options: opts, schema: schema}, _, _progress) do
    kind = if is_nil(schema), do: :text, else: :object

    with {:ok, response} <- Jido.AI.Model.Transport.request(kind, model, messages, opts, schema),
         do: {:ok, %{response: Jido.AI.Model.Messages.align_context(response)}}
  end

  defp delta(_, _, _, text) when text in [nil, ""], do: :ok

  defp delta(context, model, kind, text),
    do:
      Jido.AI.Session.emit(context, :llm_delta, %{
        chunk_type: kind,
        delta: text,
        model: Jido.AI.Models.label(model)
      })
end
