defmodule Jido.AI.Observe.Content do
  @moduledoc false
  # This projection never changes the native data used by execution.
  alias ReqLLM.Message.ContentPart
  @reasoning ~w(reasoning_details thinking_content streaming_thinking thinking_trace last_thinking)
  @rich ~w(arguments prepared_arguments tool_context base_tool_context)
  @diagnostic ~w(content text query prompt result value answer conversation streaming_text system_prompt instructions delta)
  @media [:image, :image_url, :video_url, :file]
  @omitted "[Content not retained]"

  # Signed tokens are not encrypted. Withhold tokens that would disclose
  # content excluded by storage or rich/reasoning stream policy.
  def retainable?(value, policy) do
    policy =
      Map.merge(policy, %{
        store_content: policy[:store_content] == true and policy[:stream_content] == true,
        store_reasoning: policy[:store_reasoning] == true and policy[:stream_reasoning] == true
      })

    not omitted?(value) and project(value, policy, :storage) == value
  end

  defp omitted?(value) when is_map(value),
    do:
      Map.get(value, :content_omitted, Map.get(value, "content_omitted")) == true or
        Enum.any?(Map.values(value), &omitted?/1)

  defp omitted?(value) when is_list(value), do: Enum.any?(value, &omitted?/1)
  defp omitted?(_), do: false

  def project(value, policy, destination, include_content \\ false) do
    {rich, reasoning, text} =
      case destination do
        :storage ->
          {policy[:store_content] == true, policy[:store_reasoning] == true, true}

        :stream ->
          {policy[:stream_content] == true, policy[:stream_reasoning] == true, true}

        :diagnostics ->
          allowed = policy[:diagnostics_content] == true and include_content
          {allowed, allowed, allowed}
      end

    walk(value, %{rich: rich, reasoning: reasoning, text: text, tools: rich}, 0)
  end

  def event(event, policy, destination) do
    event =
      case event do
        %{kind: :llm_delta, data: %{chunk_type: :thinking} = data} ->
          if policy[if(destination == :stream, do: :stream_reasoning, else: :store_reasoning)],
            do: event,
            else: %{event | data: Map.put(data, :delta, "")}

        %{kind: kind, data: data} when kind in [:tool_started, :tool_completed] ->
          if policy[if(destination == :stream, do: :stream_content, else: :store_content)],
            do: event,
            else: %{event | data: data |> Map.delete(:result) |> Map.delete(:completed)}

        _ ->
          event
      end

    project(event, policy, destination)
  end

  def message(message, policy) do
    projected = project(message, policy, :storage)

    projected =
      if message.role == :tool and policy[:store_content] != true,
        do: %{projected | content: [ContentPart.text(@omitted)]},
        else: projected

    {projected, projected != message}
  end

  defp walk(_, _, depth) when depth > 24, do: "[Content limit]"

  # Profile field and model-role names are contracts, not message payload keys.
  # Keep inspection configuration usable while hiding prompt and tool context.
  defp walk(%Jido.AI.Profile{} = value, permissions, depth) do
    models = Map.new(value.models, fn {role, model} -> {role, walk(model, %{permissions | text: true}, depth + 1)} end)

    %{
      value
      | instructions: if(permissions.text, do: walk(value.instructions, permissions, depth + 1), else: nil),
        tool_context: if(permissions.tools, do: walk(value.tool_context, permissions, depth + 1), else: %{}),
        models: models
    }
  end

  defp walk(%ContentPart{type: :thinking} = value, %{reasoning: false}, _),
    do: %{value | type: :text, text: @omitted, data: nil, metadata: %{}}

  defp walk(%ContentPart{type: type}, %{rich: false}, _) when type in @media,
    do: ContentPart.text(@omitted)

  defp walk(%ReqLLM.Message{role: :tool} = value, %{tools: false} = permissions, depth),
    do: walk_map(%{value | content: [ContentPart.text(@omitted)]}, permissions, depth)

  defp walk(%{"role" => "tool"} = value, %{tools: false} = permissions, depth),
    do: walk_map(Map.put(value, "content", @omitted), permissions, depth)

  defp walk(%ReqLLM.ToolCall{} = value, %{tools: false}, _),
    do: %{value | function: Map.put(value.function, :arguments, "{}")}

  defp walk(%ReqLLM.ToolCall{} = value, permissions, depth) do
    case Jason.decode(value.function.arguments) do
      {:ok, arguments} ->
        projected = walk(arguments, permissions, depth + 1)

        function =
          if projected == arguments,
            do: value.function,
            else: Map.put(value.function, :arguments, Jason.encode!(projected))

        function =
          if Map.has_key?(function, :metadata),
            do: Map.update!(function, :metadata, &walk(&1, permissions, depth + 1)),
            else: function

        %{value | function: function}

      _ ->
        %{value | function: Map.put(value.function, :arguments, "{}")}
    end
  end

  defp walk(%{"type" => type} = value, permissions, depth)
       when type in ["image", "image_url", "video_url", "file", "thinking"] do
    if (type == "thinking" and not permissions.reasoning) or (type != "thinking" and not permissions.rich),
      do: %{"type" => "text", "text" => @omitted, "metadata" => %{}},
      else: walk_map(value, permissions, depth)
  end

  defp walk(value, permissions, depth) when is_map(value), do: walk_map(value, permissions, depth)

  defp walk(value, permissions, depth) when is_list(value),
    do: Enum.map(Enum.take(value, 2_000), &walk(&1, permissions, depth + 1))

  defp walk(value, permissions, depth) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&walk(&1, permissions, depth + 1)) |> List.to_tuple()

  defp walk(value, _, _) when is_binary(value) and byte_size(value) > 65_536,
    do: String.slice(value, 0, 16_384) <> "[Content limit]"

  defp walk(value, _, _), do: value

  defp walk_map(value, permissions, depth) do
    value
    |> :maps.to_list()
    |> Enum.take(2_000)
    |> Map.new(fn {key, child} ->
      name = if is_atom(key), do: Atom.to_string(key), else: key

      next =
        cond do
          key == :__struct__ ->
            child

          name == "delta" and Map.get(value, :chunk_type) == :thinking and not permissions.reasoning ->
            ""

          secret?(name) ->
            "[REDACTED]"

          name in @reasoning and not permissions.reasoning ->
            empty(child)

          name in @rich and not permissions.tools ->
            empty(child)

          name in ["result", "completed"] and Map.get(value, :tool_call_id) != nil and not permissions.tools ->
            empty(child)

          name in @diagnostic and not permissions.text ->
            empty(child)

          name in ["token", "checkpoint_token"] and not permissions.text ->
            nil

          name in ["react_checkpoint", "checkpoint"] and is_map(child) ->
            projected = walk(child, permissions, depth + 1)
            if projected == child, do: child, else: nil

          name == "tool_results" and is_list(child) and not permissions.tools ->
            Enum.map(Enum.take(child, 2_000), fn item ->
              item = if is_map(item), do: Map.drop(item, [:result, :arguments, :prepared_arguments]), else: item
              walk(item, permissions, depth + 1)
            end)

          true ->
            walk(child, permissions, depth + 1)
        end

      {key, next}
    end)
  end

  defp empty(value) when is_list(value), do: []
  defp empty(value) when is_binary(value), do: ""
  defp empty(value) when is_map(value), do: %{}
  defp empty(_), do: nil

  defp secret?(key) when is_binary(key) do
    key = if String.valid?(key), do: String.downcase(key), else: ""

    key in ~w(api_key apikey password secret authorization access_token refresh_token private_key) or
      String.ends_with?(key, ["_secret", "_password", "_api_key"])
  end

  defp secret?(_), do: false
end
