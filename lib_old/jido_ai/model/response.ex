defmodule Jido.AI.Model.Response do
  @moduledoc """
  Normalized representation of one model response.

  This value captures the response shape consumed by reasoning methods and
  directives:

  - Response classification (`:tool_calls` or `:final_answer`)
  - Ordered multimodal content, extracted text, and optional thinking content
  - Normalized tool calls
  - Usage/model metadata
  - Optional executed tool results
  """

  alias Jido.AI.Effects
  alias Jido.AI.Usage
  alias ReqLLM.Context
  alias ReqLLM.Message.ContentPart

  @type response_type :: :tool_calls | :final_answer
  @type raw_tool_result :: {:ok, term(), [term()]} | {:error, term(), [term()]}
  @type tool_result_content :: String.t() | [ContentPart.t()]

  @type tool_result :: %{
          id: String.t(),
          name: String.t(),
          content: tool_result_content(),
          raw_result: raw_tool_result()
        }

  @type t :: %__MODULE__{
          type: response_type(),
          text: String.t(),
          content_parts: [ContentPart.t()],
          thinking_content: String.t() | nil,
          reasoning_details: list() | nil,
          tool_calls: list(term()),
          usage: map() | nil,
          model: String.t() | nil,
          finish_reason: atom() | nil,
          message_metadata: map(),
          tool_results: list(tool_result())
        }

  defstruct type: :final_answer,
            text: "",
            content_parts: [],
            thinking_content: nil,
            reasoning_details: nil,
            tool_calls: [],
            usage: nil,
            model: nil,
            finish_reason: nil,
            message_metadata: %{},
            tool_results: []

  @doc """
  Builds a response from a ReqLLM response.

  Options:

  - `:model` - Override model from the response payload
  """
  @spec from_response(map() | ReqLLM.Response.t() | t(), keyword()) :: t()
  def from_response(response, opts \\ [])

  def from_response(%__MODULE__{} = response, opts) do
    case Keyword.fetch(opts, :model) do
      {:ok, model} -> %{response | model: model}
      :error -> response
    end
  end

  def from_response(%ReqLLM.Response{} = response, opts) do
    classified = ReqLLM.Response.classify(response)
    message = response.message || %{}

    %__MODULE__{
      type: normalize_type(classified.type),
      text: normalize_text(classified.text),
      content_parts: normalize_content_parts(Map.get(message, :content)),
      thinking_content: normalize_optional_string(classified.thinking),
      reasoning_details: normalize_reasoning_details(Map.get(message, :reasoning_details)),
      tool_calls: normalize_tool_calls(classified.tool_calls),
      usage: normalize_usage(ReqLLM.Response.usage(response)),
      model: Keyword.get(opts, :model, response.model),
      finish_reason: normalize_finish_reason(classified.finish_reason),
      message_metadata: normalize_metadata(Map.get(message, :metadata)),
      tool_results: []
    }
  end

  def from_response(%{} = response, opts) do
    message = get_field(response, :message, %{}) || %{}
    content = get_field(message, :content)
    tool_calls = message |> get_field(:tool_calls, []) |> normalize_tool_calls()
    finish_reason = response |> get_field(:finish_reason) |> normalize_finish_reason()

    %__MODULE__{
      type: classify_type(tool_calls, finish_reason),
      text: extract_from_content(content),
      content_parts: normalize_content_parts(content),
      thinking_content: extract_thinking_content(content),
      reasoning_details: normalize_reasoning_details(get_field(message, :reasoning_details)),
      tool_calls: tool_calls,
      usage: normalize_usage(get_field(response, :usage)),
      model: Keyword.get(opts, :model, get_field(response, :model)),
      finish_reason: finish_reason,
      message_metadata: normalize_metadata(get_field(message, :metadata)),
      tool_results: []
    }
  end

  @doc """
  Builds a response from a map that is already in classified result shape.
  """
  @spec from_result_map(map() | t()) :: t()
  def from_result_map(%__MODULE__{} = response), do: response

  def from_result_map(%{} = map) do
    %__MODULE__{
      type: normalize_type(get_field(map, :type, :final_answer)),
      text: normalize_text(get_field(map, :text, "")),
      content_parts: map |> get_field(:content_parts, []) |> normalize_content_parts(),
      thinking_content: normalize_optional_string(get_field(map, :thinking_content)),
      reasoning_details: normalize_reasoning_details(get_field(map, :reasoning_details)),
      tool_calls: map |> get_field(:tool_calls, []) |> normalize_tool_calls(),
      usage: normalize_usage(get_field(map, :usage)),
      model: normalize_optional_string(get_field(map, :model)),
      finish_reason: normalize_finish_reason(get_field(map, :finish_reason)),
      message_metadata: normalize_metadata(get_field(map, :message_metadata)),
      tool_results: map |> get_field(:tool_results, []) |> normalize_tool_results()
    }
  end

  @doc """
  Returns true when the response requests tool execution.
  """
  @spec needs_tools?(t()) :: boolean()
  def needs_tools?(%__MODULE__{type: :tool_calls}), do: true
  def needs_tools?(%__MODULE__{tool_calls: [_ | _]}), do: true
  def needs_tools?(%__MODULE__{}), do: false

  @doc """
  Projects the response into an assistant message compatible with ReqLLM context.
  """
  @spec assistant_message(t()) :: ReqLLM.Message.t()
  def assistant_message(%__MODULE__{} = response) do
    [metadata: response.message_metadata]
    |> maybe_put_keyword(:tool_calls, assistant_tool_calls(response))
    |> then(&Context.assistant(assistant_content(response), &1))
    |> maybe_add(:reasoning_details, response.reasoning_details)
  end

  @doc """
  Returns the ordered visible content for assistant-message projection.
  """
  @spec assistant_content(t()) :: String.t() | [ContentPart.t()]
  def assistant_content(%__MODULE__{} = response) do
    content_parts = visible_content_parts(response.content_parts)

    if multimodal?(content_parts), do: content_parts, else: response.text
  end

  @doc """
  Returns generated image content parts in response order.
  """
  @spec images(t()) :: [ContentPart.t()]
  def images(%__MODULE__{content_parts: content_parts}) do
    Enum.filter(
      content_parts,
      &match?(%ContentPart{type: type} when type in [:image, :image_url], &1)
    )
  end

  @doc """
  Returns text for text-only responses or ordered content parts for multimodal responses.
  """
  @spec result(t()) :: String.t() | [ContentPart.t()]
  def result(%__MODULE__{} = response) do
    content_parts = visible_content_parts(response.content_parts)

    if multimodal?(content_parts), do: content_parts, else: response.text
  end

  @doc false
  @spec stream_content_part(term()) :: {:ok, ContentPart.t()} | :error
  def stream_content_part(%{
        __struct__: ReqLLM.StreamChunk,
        type: :content_part,
        content_part: %ContentPart{} = content_part
      }),
      do: {:ok, content_part}

  def stream_content_part(_chunk), do: :error

  @doc false
  @spec content_parts_from_chunks(Enumerable.t()) :: [ContentPart.t()]
  def content_parts_from_chunks(chunks) do
    chunks
    |> Enum.reduce([], &prepend_stream_content/2)
    |> Enum.reverse()
  end

  @doc """
  Returns a copy of the response with normalized tool results attached.
  """
  @spec with_tool_results(t(), [map()]) :: t()
  def with_tool_results(%__MODULE__{} = response, tool_results) when is_list(tool_results) do
    %{response | tool_results: normalize_tool_results(tool_results)}
  end

  @doc """
  Extracts text content from an LLM response or content value.

  This supports the canonical response/content normalization shapes used
  across actions and strategy flows.
  """
  @spec extract_text(term()) :: String.t()
  def extract_text(content) when is_binary(content), do: content
  def extract_text(nil), do: ""
  def extract_text(%{message: %{content: content}}), do: extract_from_content(content)

  def extract_text(%{choices: [%{message: %{content: content}} | _]}),
    do: extract_from_content(content)

  def extract_text(%{} = map) do
    cond do
      content = get_in(map, [:message, :content]) ->
        extract_from_content(content)

      content = get_in(map, [:choices, Access.at(0), :message, :content]) ->
        extract_from_content(content)

      content = Map.get(map, :content) ->
        extract_from_content(content)

      true ->
        ""
    end
  end

  def extract_text(content) when is_list(content) do
    if iodata_content?(content) do
      IO.iodata_to_binary(content)
    else
      extract_from_content(content)
    end
  end

  def extract_text(_), do: ""

  @doc """
  Extracts text from a content value (not wrapped in response structure).
  """
  @spec extract_from_content(term()) :: String.t()
  def extract_from_content(nil), do: ""
  def extract_from_content(content) when is_binary(content), do: content

  def extract_from_content(content) when is_list(content) do
    if iodata_content?(content) do
      IO.iodata_to_binary(content)
    else
      content
      |> Enum.filter(&text_content_block?/1)
      |> Enum.map_join("\n", fn
        %{text: text} when is_binary(text) -> text
        _ -> ""
      end)
    end
  end

  def extract_from_content(_), do: ""

  @doc """
  Projects tool results into `role: :tool` messages.
  """
  @spec tool_messages(t() | [map()]) :: [ReqLLM.Message.t()]
  def tool_messages(%__MODULE__{tool_results: tool_results}), do: tool_messages(tool_results)

  def tool_messages(tool_results) when is_list(tool_results) do
    tool_results
    |> normalize_tool_results()
    |> Enum.map(fn result ->
      Context.tool_result(result.id, result.name, result.content)
    end)
  end

  @doc """
  Formats a raw tool execution result into tool message content.
  """
  @spec format_tool_result_content(raw_tool_result() | {:ok, term()} | {:error, term()}) ::
          tool_result_content()
  defdelegate format_tool_result_content(result), to: Jido.AI.Model.Content

  @doc """
  Converts a response to a plain result map for public action/plugin outputs.
  """
  @spec to_result_map(t()) :: map()
  def to_result_map(%__MODULE__{} = response) do
    %{
      type: response.type,
      text: response.text,
      content_parts: response.content_parts,
      thinking_content: response.thinking_content,
      tool_calls: response.tool_calls,
      usage: response.usage,
      model: response.model,
      finish_reason: response.finish_reason
    }
  end

  defp classify_type(tool_calls, :tool_calls) when is_list(tool_calls), do: :tool_calls

  defp classify_type(tool_calls, _finish_reason) when is_list(tool_calls) and tool_calls != [],
    do: :tool_calls

  defp classify_type(_tool_calls, _finish_reason), do: :final_answer

  defp normalize_type(:tool_calls), do: :tool_calls
  defp normalize_type("tool_calls"), do: :tool_calls
  defp normalize_type(_), do: :final_answer

  defp normalize_finish_reason(nil), do: nil
  defp normalize_finish_reason(reason) when is_atom(reason), do: reason
  defp normalize_finish_reason("stop"), do: :stop
  defp normalize_finish_reason("completed"), do: :stop
  defp normalize_finish_reason("tool_calls"), do: :tool_calls
  defp normalize_finish_reason("tool_use"), do: :tool_calls
  defp normalize_finish_reason("length"), do: :length
  defp normalize_finish_reason("max_tokens"), do: :length
  defp normalize_finish_reason("max_output_tokens"), do: :length
  defp normalize_finish_reason("content_filter"), do: :content_filter
  defp normalize_finish_reason("end_turn"), do: :stop
  defp normalize_finish_reason("error"), do: :error
  defp normalize_finish_reason("cancelled"), do: :cancelled
  defp normalize_finish_reason("incomplete"), do: :incomplete
  defp normalize_finish_reason("unknown"), do: :unknown
  defp normalize_finish_reason(_), do: :unknown

  defp normalize_text(text) when is_binary(text), do: text
  defp normalize_text(_), do: ""

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(_), do: nil

  defp visible_content_parts(content_parts) when is_list(content_parts) do
    Enum.reject(content_parts, &match?(%ContentPart{type: :thinking}, &1))
  end

  defp visible_content_parts(_content_parts), do: []

  defp multimodal?(content_parts) do
    Enum.any?(content_parts, &match?(%ContentPart{type: type} when type != :text, &1))
  end

  defp prepend_stream_content(
         %ReqLLM.StreamChunk{type: :content, text: text},
         [%ContentPart{type: :text, text: existing} = part | rest]
       )
       when is_binary(text) and text != "" and is_binary(existing) do
    [%{part | text: existing <> text} | rest]
  end

  defp prepend_stream_content(%ReqLLM.StreamChunk{type: :content, text: text}, content_parts)
       when is_binary(text) and text != "" do
    [ContentPart.text(text) | content_parts]
  end

  defp prepend_stream_content(chunk, content_parts) do
    case stream_content_part(chunk) do
      {:ok, content_part} -> [content_part | content_parts]
      :error -> content_parts
    end
  end

  defp normalize_reasoning_details(reasoning_details)
       when is_list(reasoning_details) and reasoning_details != [],
       do: reasoning_details

  defp normalize_reasoning_details(_), do: nil

  defp extract_thinking_content(content) when is_list(content) do
    content
    |> Enum.filter(fn
      %{type: :thinking, thinking: thinking} when is_binary(thinking) -> true
      %{type: "thinking", thinking: thinking} when is_binary(thinking) -> true
      _ -> false
    end)
    |> Enum.map_join("\n\n", & &1.thinking)
    |> case do
      "" -> nil
      thinking -> thinking
    end
  end

  defp extract_thinking_content(_), do: nil

  defp normalize_tool_calls(nil), do: []

  defp normalize_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, &normalize_tool_call/1)
  end

  defp normalize_tool_calls(_), do: []

  @doc false
  def normalize_tool_call(%{} = tool_call) do
    %{
      id: normalize_text(extract_tool_call_id(tool_call)),
      name: normalize_text(extract_tool_call_name(tool_call)),
      arguments: normalize_tool_arguments(extract_tool_call_arguments(tool_call))
    }
  end

  def normalize_tool_call(other), do: other

  defp assistant_tool_calls(%__MODULE__{type: :tool_calls, tool_calls: tool_calls})
       when is_list(tool_calls),
       do: tool_calls

  defp assistant_tool_calls(%__MODULE__{tool_calls: tool_calls})
       when is_list(tool_calls) and tool_calls != [],
       do: tool_calls

  defp assistant_tool_calls(_response), do: nil

  defp normalize_tool_results(results) when is_list(results) do
    Enum.map(results, &normalize_tool_result/1)
  end

  defp normalize_tool_results(_), do: []

  defp normalize_tool_result(%{} = result) do
    raw_result =
      get_field(result, :raw_result, {:ok, get_field(result, :result), []})
      |> normalize_raw_result()

    content = normalize_tool_result_content(get_field(result, :content), raw_result)

    %{
      id: normalize_text(get_field(result, :id, "")),
      name: normalize_text(get_field(result, :name, "")),
      content: content,
      raw_result: raw_result
    }
  end

  defp normalize_tool_result(other) do
    %{
      id: "",
      name: "",
      content: inspect(other),
      raw_result: {:ok, other, []}
    }
  end

  defp normalize_usage(usage), do: Usage.normalize(usage)

  defp normalize_metadata(%{} = metadata), do: metadata
  defp normalize_metadata(_), do: %{}

  defp text_content_block?(%{type: :text}), do: true
  defp text_content_block?(%{type: "text"}), do: true
  defp text_content_block?(_), do: false

  defp iodata_content?(list), do: has_binary_content?(list) or printable_charlist?(list)

  defp has_binary_content?([]), do: false
  defp has_binary_content?([head | _tail]) when is_binary(head), do: true

  defp has_binary_content?([head | tail]) when is_list(head) do
    has_binary_content?(head) or has_binary_content?(tail)
  end

  defp has_binary_content?([_ | tail]), do: has_binary_content?(tail)

  defp printable_charlist?(list) when is_list(list), do: :io_lib.printable_list(list)

  defp get_field(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_keyword(keyword, _key, nil), do: keyword
  defp maybe_put_keyword(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp normalize_content_parts(parts), do: Jido.AI.Model.Content.normalize_content_parts(parts)
  defp content_parts_list?(parts), do: Jido.AI.Model.Content.content_parts_list?(parts)

  defp normalize_tool_result_content(content, raw_result) when is_binary(content) do
    if canonical_tool_payload?(content), do: content, else: format_tool_result_content(raw_result)
  end

  defp normalize_tool_result_content(content, _raw_result) when is_list(content) do
    if content_parts_list?(content),
      do: normalize_content_parts(content),
      else: format_tool_result_content({:ok, content})
  end

  defp normalize_tool_result_content(nil, raw_result), do: format_tool_result_content(raw_result)

  defp normalize_tool_result_content(content, _raw_result) when is_map(content),
    do: format_tool_result_content({:ok, if(content == %{}, do: nil, else: content)})

  defp normalize_tool_result_content(_content, raw_result),
    do: format_tool_result_content(raw_result)

  defp canonical_tool_payload?(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"ok" => _}} -> true
      _ -> false
    end
  end

  defp normalize_raw_result(raw_result), do: Effects.normalize_result(raw_result)

  defp extract_tool_call_id(%{} = tool_call) do
    get_field(tool_call, :id, "")
  end

  defp extract_tool_call_name(%ReqLLM.ToolCall{} = tool_call) do
    ReqLLM.ToolCall.name(tool_call)
  rescue
    _ -> get_field(tool_call, :name, get_field(get_field(tool_call, :function, %{}), :name, ""))
  end

  defp extract_tool_call_name(%{} = tool_call) do
    get_field(tool_call, :name, get_field(get_field(tool_call, :function, %{}), :name, ""))
  end

  defp extract_tool_call_arguments(%ReqLLM.ToolCall{} = tool_call) do
    ReqLLM.ToolCall.args_map(tool_call)
  rescue
    _ ->
      tool_call
      |> get_field(:arguments, get_field(get_field(tool_call, :function, %{}), :arguments, %{}))
      |> normalize_tool_arguments()
  end

  defp extract_tool_call_arguments(%{} = tool_call) do
    get_field(
      tool_call,
      :arguments,
      get_field(get_field(tool_call, :function, %{}), :arguments, %{})
    )
  end

  defp normalize_tool_arguments(arguments) when is_map(arguments), do: arguments

  defp normalize_tool_arguments(arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp normalize_tool_arguments(_), do: %{}
end
