defmodule Jido.AI.Model.Messages do
  @moduledoc false
  @refs_key :jido_ai_refs

  def entries(messages) do
    Enum.map(messages, fn input ->
      {:ok, context} = normalize_messages([input])
      [message] = context.messages
      refs = message.metadata[@refs_key] || message.metadata[Atom.to_string(@refs_key)] || %{}

      message
      |> clear_refs()
      |> Map.from_struct()
      |> Map.put(:refs, if(refs == %{}, do: nil, else: refs))
      |> Map.put(:timestamp, Map.get(input, :timestamp) || DateTime.utc_now())
    end)
  end

  def messages(entries) do
    with {:ok, context} <- normalize_messages(entries), do: {:ok, context.messages}
  end

  # ReqLLM message metadata carries refs locally. Provider requests remove this
  # private key; response contexts restore only an exact matching input prefix.
  def normalize_messages(messages),
    do: ReqLLM.Context.normalize(Enum.map(messages, &carry_refs/1))

  def provider_context(%ReqLLM.Context{} = context),
    do: %{context | messages: Enum.map(context.messages, &clear_refs/1)}

  def provider_context(context), do: context

  def restore_response_context(
        %ReqLLM.Response{context: %ReqLLM.Context{messages: messages} = context} = response,
        %ReqLLM.Context{messages: sent},
        %ReqLLM.Context{messages: original}
      ) do
    {prefix, suffix} = Enum.split(messages, length(sent))

    if prefix == sent,
      do: %{response | context: %{context | messages: original ++ suffix}},
      else: response
  end

  def restore_response_context(response, _, _), do: response

  defp carry_refs(%ReqLLM.Message{} = message), do: message

  defp carry_refs(message) when is_map(message),
    do: put_refs(message, Map.get(message, :refs, Map.get(message, "refs", %{})))

  defp carry_refs(message), do: message

  def put_refs(message, refs) when is_map(refs) and map_size(refs) > 0 do
    key = if Map.has_key?(message, "role") and not Map.has_key?(message, :role), do: "metadata", else: :metadata
    Map.update(message, key, %{@refs_key => refs}, &Map.put(&1, @refs_key, refs))
  end

  def put_refs(message, _), do: message

  def clear_refs(%ReqLLM.Message{metadata: metadata} = message),
    do: %{message | metadata: Map.drop(metadata, [@refs_key, Atom.to_string(@refs_key)])}

  # Some provider builders add an empty text marker after putting the assistant
  # message in response.context. Keep both views equal only for that exact,
  # lossless difference. Distinct unresolved tool messages must still fail.
  def align_context(
        %ReqLLM.Response{
          message:
            %ReqLLM.Message{
              role: :assistant,
              content: [%ReqLLM.Message.ContentPart{type: :text, text: ""}],
              tool_calls: calls
            } = message,
          context: %ReqLLM.Context{messages: messages} = context
        } = response
      )
      when is_list(calls) and calls != [] do
    case List.pop_at(messages, -1) do
      {%ReqLLM.Message{content: []} = previous, prefix} ->
        if previous == %{message | content: []},
          do: %{response | context: %{context | messages: prefix ++ [message]}},
          else: response

      _ ->
        response
    end
  end

  def align_context(response), do: response

  def bind_response(%ReqLLM.Response{message: %ReqLLM.Message{} = original} = response, refs) do
    message = original |> clear_refs() |> put_refs(refs)

    updated =
      case response.context do
        %ReqLLM.Context{messages: messages} = conversation ->
          case List.pop_at(messages, -1) do
            {^original, prefix} -> %{conversation | messages: prefix ++ [message]}
            _ -> conversation
          end

        other ->
          other
      end

    %{response | message: message, context: updated}
  end

  def bind_response(response, _), do: response
end
