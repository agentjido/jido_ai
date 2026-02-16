defmodule Jido.AI.Turn do
  @moduledoc """
  Canonical representation of a single LLM turn.

  A turn captures the normalized response shape consumed by strategies and
  directives:

  - Response classification (`:tool_calls` or `:final_answer`)
  - Extracted text and optional thinking content
  - Normalized tool calls
  - Usage/model metadata
  - Optional executed tool results
  """

  alias Jido.AI.{Executor, Text, ToolAdapter}

  @type response_type :: :tool_calls | :final_answer
  @type run_opts :: [timeout: pos_integer() | nil, tools: map() | [module()] | module() | nil]

  @type tool_result :: %{
          id: String.t(),
          name: String.t(),
          content: String.t(),
          raw_result: {:ok, term()} | {:error, term()}
        }

  @type t :: %__MODULE__{
          type: response_type(),
          text: String.t(),
          thinking_content: String.t() | nil,
          tool_calls: [term()],
          usage: map() | nil,
          model: String.t() | nil,
          tool_results: [tool_result()]
        }

  defstruct type: :final_answer,
            text: "",
            thinking_content: nil,
            tool_calls: [],
            usage: nil,
            model: nil,
            tool_results: []

  @doc """
  Builds a turn from a ReqLLM response.

  Options:

  - `:model` - Override model from the response payload
  """
  @spec from_response(map() | ReqLLM.Response.t() | t(), keyword()) :: t()
  def from_response(response, opts \\ [])

  def from_response(%__MODULE__{} = turn, opts) do
    case Keyword.fetch(opts, :model) do
      {:ok, model} -> %{turn | model: model}
      :error -> turn
    end
  end

  def from_response(%ReqLLM.Response{} = response, opts) do
    classified = ReqLLM.Response.classify(response)

    %__MODULE__{
      type: normalize_type(classified.type),
      text: normalize_text(classified.text),
      thinking_content: normalize_optional_string(classified.thinking),
      tool_calls: normalize_tool_calls(classified.tool_calls),
      usage: normalize_usage(ReqLLM.Response.usage(response)),
      model: Keyword.get(opts, :model, response.model),
      tool_results: []
    }
  end

  def from_response(%{} = response, opts) do
    message = get_field(response, :message, %{}) || %{}
    content = get_field(message, :content)
    tool_calls = message |> get_field(:tool_calls, []) |> normalize_tool_calls()
    finish_reason = get_field(response, :finish_reason)

    %__MODULE__{
      type: classify_type(tool_calls, finish_reason),
      text: Text.extract_from_content(content),
      thinking_content: extract_thinking_content(content),
      tool_calls: tool_calls,
      usage: normalize_usage(get_field(response, :usage)),
      model: Keyword.get(opts, :model, get_field(response, :model)),
      tool_results: []
    }
  end

  @doc """
  Builds a turn from a map that is already in classified result shape.
  """
  @spec from_result_map(map() | t()) :: t()
  def from_result_map(%__MODULE__{} = turn), do: turn

  def from_result_map(%{} = map) do
    %__MODULE__{
      type: normalize_type(get_field(map, :type, :final_answer)),
      text: normalize_text(get_field(map, :text, "")),
      thinking_content: normalize_optional_string(get_field(map, :thinking_content)),
      tool_calls: map |> get_field(:tool_calls, []) |> normalize_tool_calls(),
      usage: normalize_usage(get_field(map, :usage)),
      model: normalize_optional_string(get_field(map, :model)),
      tool_results: map |> get_field(:tool_results, []) |> normalize_tool_results()
    }
  end

  @doc """
  Returns true when the turn requests tool execution.
  """
  @spec needs_tools?(t()) :: boolean()
  def needs_tools?(%__MODULE__{tool_calls: tool_calls}) when is_list(tool_calls) and tool_calls != [] do
    tool_calls != []
  end

  def needs_tools?(%__MODULE__{type: :tool_calls}), do: true
  def needs_tools?(%__MODULE__{}), do: false

  @doc """
  Projects the turn into an assistant message compatible with ReqLLM context.
  """
  @spec assistant_message(t()) :: map()
  def assistant_message(%__MODULE__{} = turn) do
    if needs_tools?(turn) do
      %{role: :assistant, content: turn.text || "", tool_calls: turn.tool_calls || []}
    else
      %{role: :assistant, content: turn.text || ""}
    end
  end

  @doc """
  Returns a copy of the turn with normalized tool results attached.
  """
  @spec with_tool_results(t(), [map()]) :: t()
  def with_tool_results(%__MODULE__{} = turn, tool_results) when is_list(tool_results) do
    %{turn | tool_results: normalize_tool_results(tool_results)}
  end

  @doc """
  Executes all requested tools for the turn and returns the updated turn.
  """
  @spec run_tools(t(), map(), run_opts()) :: {:ok, t()} | {:error, term()}
  def run_tools(%__MODULE__{} = turn, context, opts \\ []) do
    if needs_tools?(turn) do
      with {:ok, tool_results} <- run_tool_calls(turn.tool_calls, context, opts) do
        {:ok, with_tool_results(turn, tool_results)}
      end
    else
      {:ok, turn}
    end
  end

  @doc """
  Executes normalized tool calls and returns normalized tool results.
  """
  @spec run_tool_calls([term()], map(), run_opts()) :: {:ok, [tool_result()]}
  def run_tool_calls(tool_calls, context, opts \\ []) when is_list(tool_calls) do
    tools = resolve_tools(context, opts)
    timeout = normalize_timeout(Keyword.get(opts, :timeout))

    tool_results =
      Enum.map(tool_calls, fn tool_call ->
        run_single_tool(tool_call, context, tools, timeout)
      end)

    {:ok, tool_results}
  end

  @doc """
  Projects tool results into `role: :tool` messages.
  """
  @spec tool_messages(t() | [map()]) :: [map()]
  def tool_messages(%__MODULE__{tool_results: tool_results}), do: tool_messages(tool_results)

  def tool_messages(tool_results) when is_list(tool_results) do
    tool_results
    |> normalize_tool_results()
    |> Enum.map(fn result ->
      %{
        role: :tool,
        tool_call_id: result.id,
        name: result.name,
        content: result.content
      }
    end)
  end

  @doc """
  Formats a raw tool execution result to string content suitable for tool messages.
  """
  @spec format_tool_result_content({:ok, term()} | {:error, term()}) :: String.t()
  def format_tool_result_content({:ok, result}) when is_binary(result), do: result
  def format_tool_result_content({:ok, result}) when is_map(result) or is_list(result), do: encode_or_inspect(result)
  def format_tool_result_content({:ok, result}), do: inspect(result)

  def format_tool_result_content({:error, error}) when is_map(error) do
    get_field(error, :message) || get_field(error, :error) || "Execution failed"
  end

  def format_tool_result_content({:error, error}), do: inspect(error)

  @doc """
  Converts a turn to a plain result map for public action/plugin outputs.
  """
  @spec to_result_map(t()) :: map()
  def to_result_map(%__MODULE__{} = turn) do
    %{
      type: turn.type,
      text: turn.text,
      thinking_content: turn.thinking_content,
      tool_calls: turn.tool_calls,
      usage: turn.usage,
      model: turn.model
    }
  end

  defp classify_type(tool_calls, :tool_calls) when is_list(tool_calls), do: :tool_calls
  defp classify_type(tool_calls, _finish_reason) when is_list(tool_calls) and tool_calls != [], do: :tool_calls
  defp classify_type(_tool_calls, _finish_reason), do: :final_answer

  defp normalize_type(:tool_calls), do: :tool_calls
  defp normalize_type("tool_calls"), do: :tool_calls
  defp normalize_type(_), do: :final_answer

  defp normalize_text(text) when is_binary(text), do: text
  defp normalize_text(_), do: ""

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(_), do: nil

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

  defp normalize_tool_call(%{} = tool_call) do
    %{
      id: normalize_text(extract_tool_call_id(tool_call)),
      name: normalize_text(extract_tool_call_name(tool_call)),
      arguments: normalize_tool_arguments(extract_tool_call_arguments(tool_call))
    }
  end

  defp normalize_tool_call(other), do: other

  defp normalize_tool_results(results) when is_list(results) do
    Enum.map(results, &normalize_tool_result/1)
  end

  defp normalize_tool_results(_), do: []

  defp normalize_tool_result(%{} = result) do
    raw_result = get_field(result, :raw_result, {:ok, get_field(result, :result)})
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
      raw_result: {:ok, other}
    }
  end

  defp normalize_usage(nil), do: nil

  defp normalize_usage(usage) when is_map(usage) do
    usage
    |> Enum.map(fn {key, value} -> {normalize_usage_key(key), normalize_usage_value(value)} end)
    |> Map.new()
  end

  defp normalize_usage(_), do: nil

  defp normalize_usage_key("input_tokens"), do: :input_tokens
  defp normalize_usage_key("output_tokens"), do: :output_tokens
  defp normalize_usage_key("total_tokens"), do: :total_tokens
  defp normalize_usage_key("cache_creation_input_tokens"), do: :cache_creation_input_tokens
  defp normalize_usage_key("cache_read_input_tokens"), do: :cache_read_input_tokens
  defp normalize_usage_key(key) when is_binary(key), do: key
  defp normalize_usage_key(key), do: key

  defp normalize_usage_value(value) when is_integer(value), do: value
  defp normalize_usage_value(value) when is_float(value), do: value

  defp normalize_usage_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(value) do
          {float, _} -> float
          :error -> 0
        end
    end
  end

  defp normalize_usage_value(_), do: 0

  defp run_single_tool(tool_call, context, tools, timeout) do
    call_id = normalize_text(extract_tool_call_id(tool_call))
    tool_name = normalize_text(extract_tool_call_name(tool_call))
    arguments = normalize_tool_arguments(extract_tool_call_arguments(tool_call))

    exec_opts =
      [tools: tools]
      |> maybe_add_timeout(timeout)

    raw_result =
      case tool_name do
        "" ->
          {:error, %{type: :validation, message: "Missing tool name"}}

        _ ->
          Executor.execute(tool_name, arguments, context, exec_opts)
      end

    %{
      id: call_id,
      name: tool_name,
      content: format_tool_result_content(raw_result),
      raw_result: raw_result
    }
  end

  defp resolve_tools(context, opts) do
    context = if is_map(context), do: context, else: %{}

    tools_input =
      Keyword.get(opts, :tools) ||
        get_field(context, :tools) ||
        get_in(context, [:tool_calling, :tools]) ||
        get_in(context, [:state, :tool_calling, :tools]) ||
        get_in(context, [:agent, :state, :tool_calling, :tools]) ||
        get_in(context, [:plugin_state, :tool_calling, :tools])

    ToolAdapter.to_action_map(tools_input)
  end

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
  defp normalize_timeout(_), do: nil

  defp maybe_add_timeout(opts, nil), do: opts
  defp maybe_add_timeout(opts, timeout), do: Keyword.put(opts, :timeout, timeout)

  defp get_field(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp encode_or_inspect(value) do
    Jason.encode!(value)
  rescue
    _ -> inspect(value)
  end

  defp normalize_tool_result_content(content, _raw_result) when is_binary(content), do: content
  defp normalize_tool_result_content(nil, raw_result), do: format_tool_result_content(raw_result)
  defp normalize_tool_result_content(_content, raw_result), do: format_tool_result_content(raw_result)

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
    get_field(tool_call, :arguments, get_field(get_field(tool_call, :function, %{}), :arguments, %{}))
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
