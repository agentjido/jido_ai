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

  alias Jido.AI.{Observe, ToolAdapter}
  alias Jido.Action.Error.TimeoutError
  alias Jido.Action.Tool, as: ActionTool

  require Logger

  @type response_type :: :tool_calls | :final_answer
  @type tools_map :: %{String.t() => module()}
  @type execute_opts :: [timeout: pos_integer() | nil, tools: tools_map() | [module()] | module() | nil]
  @type execute_result :: {:ok, term()} | {:error, map()}
  @type run_opts :: [timeout: pos_integer() | nil, tools: map() | [module()] | module() | nil]

  @default_timeout 30_000

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
          tool_calls: list(term()),
          usage: map() | nil,
          model: String.t() | nil,
          tool_results: list(tool_result())
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
      text: extract_from_content(content),
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
  def needs_tools?(%__MODULE__{type: :tool_calls}), do: true
  def needs_tools?(%__MODULE__{tool_calls: [_ | _]}), do: true
  def needs_tools?(%__MODULE__{}), do: false

  @doc """
  Projects the turn into an assistant message compatible with ReqLLM context.
  """
  @spec assistant_message(t()) :: map()
  def assistant_message(%__MODULE__{type: :tool_calls} = turn) do
    %{role: :assistant, content: turn.text, tool_calls: turn.tool_calls}
  end

  def assistant_message(%__MODULE__{tool_calls: tool_calls} = turn) when is_list(tool_calls) and tool_calls != [] do
    %{role: :assistant, content: turn.text, tool_calls: tool_calls}
  end

  def assistant_message(%__MODULE__{} = turn), do: %{role: :assistant, content: turn.text}

  @doc """
  Returns a copy of the turn with normalized tool results attached.
  """
  @spec with_tool_results(t(), [map()]) :: t()
  def with_tool_results(%__MODULE__{} = turn, tool_results) when is_list(tool_results) do
    %{turn | tool_results: normalize_tool_results(tool_results)}
  end

  @doc """
  Builds a tools map from action modules.
  """
  @spec build_tools_map(module() | [module()]) :: tools_map()
  def build_tools_map(module) when is_atom(module), do: ToolAdapter.to_action_map(module)
  def build_tools_map(modules) when is_list(modules), do: ToolAdapter.to_action_map(modules)

  @doc """
  Executes a tool by name using a tools map and returns raw action output.
  """
  @spec execute(String.t(), map(), map(), execute_opts()) :: execute_result()
  def execute(tool_name, params, context, opts \\ []) when is_binary(tool_name) do
    context = normalize_context(context)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    tools = opts |> Keyword.get(:tools, %{}) |> ToolAdapter.to_action_map()
    start_time = System.monotonic_time()

    start_execute_telemetry(tool_name, params, context)

    result =
      case Map.fetch(tools, tool_name) do
        {:ok, module} ->
          execute_internal(module, tool_name, params, context, timeout)

        :error ->
          {:error, error_envelope(tool_name, :not_found, "Tool not found: #{tool_name}")}
      end

    finalize_execute_telemetry(tool_name, result, start_time, context)
    result
  end

  @doc """
  Executes an action module directly without registry lookup.
  """
  @spec execute_module(module(), map(), map(), execute_opts()) :: execute_result()
  def execute_module(module, params, context, opts \\ []) do
    context = normalize_context(context)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    tool_name = module.name()
    start_time = System.monotonic_time()

    start_execute_telemetry(tool_name, params, context)
    result = execute_internal(module, tool_name, params, context, timeout)
    finalize_execute_telemetry(tool_name, result, start_time, context)

    result
  end

  @doc """
  Normalizes parameters from LLM format to schema-compliant format.
  """
  @spec normalize_params(map(), keyword() | struct()) :: map()
  def normalize_params(params, schema) when is_map(params) do
    ActionTool.convert_params_using_schema(params, schema)
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
  def extract_text(%{choices: [%{message: %{content: content}} | _]}), do: extract_from_content(content)

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
  Executes all requested tools for the turn and returns the updated turn.
  """
  @spec run_tools(t(), map(), run_opts()) :: {:ok, t()} | {:error, term()}
  def run_tools(turn, context, opts \\ [])

  def run_tools(%__MODULE__{type: :tool_calls} = turn, context, opts) do
    with {:ok, tool_results} <- run_tool_calls(turn.tool_calls, context, opts) do
      {:ok, with_tool_results(turn, tool_results)}
    end
  end

  def run_tools(%__MODULE__{tool_calls: tool_calls} = turn, context, opts)
      when is_list(tool_calls) and tool_calls != [] do
    with {:ok, tool_results} <- run_tool_calls(tool_calls, context, opts) do
      {:ok, with_tool_results(turn, tool_results)}
    end
  end

  def run_tools(%__MODULE__{} = turn, _context, _opts), do: {:ok, turn}

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

  defp execute_internal(module, tool_name, params, context, timeout) do
    schema = module.schema()
    normalized_params = normalize_params(params, schema)

    case Jido.Exec.run(module, normalized_params, context, timeout_opts(timeout)) do
      {:ok, output} ->
        {:ok, output}

      {:ok, output, _directive} ->
        {:ok, output}

      {:error, reason} ->
        {:error, format_error(tool_name, reason)}

      {:error, reason, _directive} ->
        {:error, format_error(tool_name, reason)}
    end
  rescue
    e ->
      {:error, format_exception(tool_name, e, __STACKTRACE__)}
  catch
    kind, reason ->
      {:error, format_catch(tool_name, kind, reason)}
  end

  defp format_error(tool_name, %TimeoutError{} = reason) do
    timeout_ms = reason.timeout || timeout_from_details(reason.details)
    message = Exception.message(reason)

    error_envelope(tool_name, :timeout, message, reason.details || %{})
    |> Map.put(:timeout_ms, timeout_ms)
  end

  defp format_error(tool_name, reason) when is_exception(reason) do
    message = Exception.message(reason)
    error_envelope(tool_name, :execution_error, message, %{exception_type: reason.__struct__})
  end

  defp format_error(tool_name, reason) do
    message = inspect(reason)
    details = reason
    error_envelope(tool_name, :execution_error, message, details)
  end

  defp format_exception(tool_name, exception, stacktrace) do
    Logger.error("Tool execution exception",
      tool_name: tool_name,
      exception_message: Exception.message(exception),
      exception_type: exception.__struct__,
      stacktrace: format_stacktrace_for_logging(stacktrace)
    )

    message = Exception.message(exception)

    error_envelope(tool_name, :exception, message, %{exception_type: exception.__struct__})
    |> Map.put(:exception_type, exception.__struct__)
  end

  defp format_catch(tool_name, kind, reason) do
    message = "Caught #{kind}: #{inspect(reason)}"

    error_envelope(tool_name, :caught, message, %{kind: kind})
    |> Map.put(:kind, kind)
  end

  defp error_envelope(tool_name, type, message, details \\ nil) do
    %{
      error: message,
      message: message,
      tool_name: tool_name,
      type: type,
      details: details
    }
  end

  defp timeout_from_details(%{} = details), do: get_field(details, :timeout)
  defp timeout_from_details(_), do: nil

  defp finalize_execute_telemetry(tool_name, {:error, %{type: :timeout}}, start_time, context) do
    exception_execute_telemetry(tool_name, :timeout, start_time, context)
  end

  defp finalize_execute_telemetry(tool_name, result, start_time, context) do
    stop_execute_telemetry(tool_name, result, start_time, context)
  end

  defp start_execute_telemetry(tool_name, params, context) do
    obs_cfg = context[:observability] || %{}

    metadata =
      %{
        tool_name: tool_name,
        params: Observe.sanitize_sensitive(params),
        call_id: context[:call_id],
        agent_id: context[:agent_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:start),
      %{system_time: System.system_time()},
      metadata
    )
  end

  defp stop_execute_telemetry(tool_name, result, start_time, context) do
    obs_cfg = context[:observability] || %{}
    duration = System.monotonic_time() - start_time

    metadata =
      %{
        tool_name: tool_name,
        result: result,
        call_id: context[:call_id],
        agent_id: context[:agent_id],
        thread_id: context[:thread_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:stop),
      %{duration: duration},
      metadata
    )
  end

  defp exception_execute_telemetry(tool_name, reason, start_time, context) do
    obs_cfg = context[:observability] || %{}
    duration = System.monotonic_time() - start_time

    metadata =
      %{
        tool_name: tool_name,
        reason: reason,
        call_id: context[:call_id],
        agent_id: context[:agent_id],
        thread_id: context[:thread_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:exception),
      %{duration: duration},
      metadata
    )
  end

  defp timeout_opts(timeout) when is_integer(timeout) and timeout > 0, do: [timeout: timeout]
  defp timeout_opts(_), do: []

  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}

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
          execute(tool_name, arguments, context, exec_opts)
      end

    %{
      id: call_id,
      name: tool_name,
      content: format_tool_result_content(raw_result),
      raw_result: raw_result
    }
  end

  defp resolve_tools(context, opts) do
    context = normalize_context(context)

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
  defp printable_charlist?(_), do: false

  defp get_field(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp format_stacktrace_for_logging(stacktrace) do
    stacktrace
    |> Enum.take(5)
    |> Exception.format_stacktrace()
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
