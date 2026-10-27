defmodule Jido.AI.Context.ReqLLM do
  @moduledoc "Lowers one prepared Jido AI context into a ReqLLM request."

  alias Jido.AI.Context

  @doc "Renders one prepared context as a model, ReqLLM context, and request options."
  @spec render(Context.t()) ::
          {:ok, %{model: String.t(), context: ReqLLM.Context.t(), options: keyword()}}
          | {:error, term()}
  def render(%Context{stage: :prepared} = context) do
    with model when is_binary(model) and model != "" <- Map.get(context.request, :model),
         {:ok, messages} <- render_messages(context.items) do
      options =
        context.request
        |> Map.get(:options, %{})
        |> options()
        |> put_option(:tools, Map.get(context.request, :tools))
        |> put_option(:tool_choice, Map.get(context.request, :tool_choice))

      {:ok, %{model: model, context: ReqLLM.Context.new(messages), options: options}}
    else
      _other -> {:error, :invalid_model_context}
    end
  end

  def render(%Context{}), do: {:error, :context_not_prepared}

  defp render_messages(items) do
    items
    |> Enum.filter(&(&1.state == :included))
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, messages} ->
      case message(item) do
        {:ok, message} -> {:cont, {:ok, [message | messages]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end

  defp message(%{role: :system} = item) do
    with {:ok, content} <- content(item.content) do
      {:ok, ReqLLM.Context.system(content, item.metadata)}
    end
  end

  defp message(%{role: :user} = item) do
    with {:ok, content} <- content(item.content) do
      {:ok, ReqLLM.Context.user(content, item.metadata)}
    end
  end

  defp message(%{role: :assistant, tool_calls: calls} = item)
       when is_list(calls) and calls != [] do
    with {:ok, content} <- content(item.content) do
      tool_calls =
        Enum.map(calls, fn call ->
          arguments = field(call, :arguments)
          encoded = if is_binary(arguments), do: arguments, else: Jason.encode!(arguments)
          ReqLLM.ToolCall.new(field(call, :id), field(call, :name), encoded)
        end)

      {:ok, ReqLLM.Context.assistant(content, tool_calls: tool_calls, metadata: item.metadata)}
    end
  rescue
    _error -> {:error, :invalid_model_context}
  end

  defp message(%{role: :assistant} = item) do
    with {:ok, content} <- content(item.content) do
      {:ok, ReqLLM.Context.assistant(content, item.metadata)}
    end
  end

  defp message(%{role: :tool} = item) do
    {:ok,
     ReqLLM.Context.tool_result_message(
       item.name,
       item.tool_call_id,
       item.output,
       item.metadata
     )}
  rescue
    _error -> {:error, :invalid_model_context}
  end

  defp message(_item), do: {:error, :invalid_model_context}

  defp options(value) when is_map(value), do: Map.to_list(value)
  defp options(value) when is_list(value), do: value
  defp options(_value), do: []

  defp put_option(options, _key, nil), do: options
  defp put_option(options, :tools, []), do: options
  defp put_option(options, key, value), do: Keyword.put(options, key, value)

  defp content(value) when is_binary(value), do: {:ok, value}

  defp content(value) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn part, {:ok, parts} ->
      case content_part(part) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | parts]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
    end
  end

  defp content(_value), do: {:error, :invalid_model_context}

  defp content_part(%ReqLLM.Message.ContentPart{} = part), do: {:ok, part}

  defp content_part(part) when is_map(part) do
    with type when not is_nil(type) <- content_type(field(part, :type)) do
      attrs = %{
        type: type,
        text: field(part, :text),
        url: field(part, :url),
        data: field(part, :data),
        file_id: field(part, :file_id),
        media_type: field(part, :media_type),
        filename: field(part, :filename),
        metadata: field(part, :metadata) || %{}
      }

      attrs
      |> then(&struct(ReqLLM.Message.ContentPart, &1))
      |> then(&Zoi.parse(ReqLLM.Message.ContentPart.schema(), &1))
    else
      _other -> {:error, :invalid_model_context}
    end
  end

  defp content_part(_part), do: {:error, :invalid_model_context}

  defp content_type(type)
       when type in [:text, :image_url, :video_url, :image, :file, :thinking, :provider_block],
       do: type

  defp content_type("text"), do: :text
  defp content_type("image_url"), do: :image_url
  defp content_type("video_url"), do: :video_url
  defp content_type("image"), do: :image
  defp content_type("file"), do: :file
  defp content_type("thinking"), do: :thinking
  defp content_type("provider_block"), do: :provider_block
  defp content_type(_type), do: nil

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
