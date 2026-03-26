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

  alias Jido.AI.{Effects, Observe, ToolAdapter}
  alias Jido.AI.Signal.Helpers, as: SignalHelpers
  alias Jido.Action.Error.TimeoutError
  alias Jido.Action.Tool, as: ActionTool
  alias ReqLLM.Context
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.ToolResult

  require Logger

  @type response_type :: :tool_calls | :final_answer
  @type tools_map :: %{String.t() => module()}
  @type execute_opts :: [timeout: pos_integer() | nil, tools: tools_map() | [module()] | module() | nil]
  @type execute_result :: {:ok, term(), [term()]} | {:error, term(), [term()]}
  @type run_opts :: [timeout: pos_integer() | nil, tools: map() | [module()] | module() | nil]

  @default_timeout 30_000

  @type tool_result_content :: String.t() | [ContentPart.t()]

  @type tool_result :: %{
          id: String.t(),
          name: String.t(),
          content: tool_result_content(),
          raw_result: execute_result()
        }

  @type t :: %__MODULE__{
          type: response_type(),
          text: String.t(),
          thinking_content: String.t() | nil,
          reasoning_details: list() | nil,
          tool_calls: list(term()),
          usage: map() | nil,
          model: String.t() | nil,
          message_metadata: map(),
          tool_results: list(tool_result())
        }

  defstruct type: :final_answer,
            text: "",
            thinking_content: nil,
            reasoning_details: nil,
            tool_calls: [],
            usage: nil,
            model: nil,
            message_metadata: %{},
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
      reasoning_details: normalize_reasoning_details(Map.get(response.message || %{}, :reasoning_details)),
      tool_calls: normalize_tool_calls(classified.tool_calls),
      usage: normalize_usage(ReqLLM.Response.usage(response)),
      model: Keyword.get(opts, :model, response.model),
      message_metadata: normalize_metadata(response.message.metadata),
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
      reasoning_details: normalize_reasoning_details(get_field(message, :reasoning_details)),
      tool_calls: tool_calls,
      usage: normalize_usage(get_field(response, :usage)),
      model: Keyword.get(opts, :model, get_field(response, :model)),
      message_metadata: normalize_metadata(get_field(message, :metadata)),
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
      reasoning_details: normalize_reasoning_details(get_field(map, :reasoning_details)),
      tool_calls: map |> get_field(:tool_calls, []) |> normalize_tool_calls(),
      usage: normalize_usage(get_field(map, :usage)),
      model: normalize_optional_string(get_field(map, :model)),
      message_metadata: normalize_metadata(get_field(map, :message_metadata)),
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
  @spec assistant_message(t()) :: ReqLLM.Message.t()
  def assistant_message(%__MODULE__{} = turn) do
    [metadata: turn.message_metadata]
    |> maybe_put_keyword(:tool_calls, assistant_tool_calls(turn))
    |> then(&Context.assistant(turn.text, &1))
    |> maybe_add(:reasoning_details, turn.reasoning_details)
  end

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
    exec_opts = Keyword.delete(opts, :timeout)
    tools = opts |> Keyword.get(:tools, %{}) |> ToolAdapter.to_action_map()
    start_time = System.monotonic_time()

    start_execute_telemetry(tool_name, params, context)

    result =
      case Map.fetch(tools, tool_name) do
        {:ok, module} ->
          execute_internal(module, tool_name, params, context, timeout, exec_opts)

        :error ->
          {:error,
           SignalHelpers.error_envelope(
             :not_found,
             "Tool not found: #{tool_name}",
             %{tool_name: tool_name},
             false
           ), []}
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
    exec_opts = Keyword.delete(opts, :timeout)
    tool_name = module.name()
    start_time = System.monotonic_time()

    start_execute_telemetry(tool_name, params, context)
    result = execute_internal(module, tool_name, params, context, timeout, exec_opts)
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
  @spec format_tool_result_content(execute_result() | {:ok, term()} | {:error, term()}) :: tool_result_content()
  def format_tool_result_content({:ok, result, _effects}), do: format_tool_result_content({:ok, result})
  def format_tool_result_content({:error, error, _effects}), do: format_tool_result_content({:error, error})

  def format_tool_result_content({:ok, %ToolResult{} = result}) do
    payload = build_tool_result_payload(result.output, result.content, result.metadata)
    encode_tool_result_envelope(%{ok: true, result: payload}, normalize_content_parts(result.content))
  end

  def format_tool_result_content({:ok, result}) when is_binary(result),
    do: encode_tool_result_envelope(%{ok: true, result: result})

  def format_tool_result_content({:ok, result}) when is_list(result) do
    if content_parts_list?(result) do
      parts = normalize_content_parts(result)
      encode_tool_result_envelope(%{ok: true, result: %{content: serialize_content_parts(parts)}}, parts)
    else
      encode_tool_result_envelope(%{ok: true, result: result})
    end
  end

  def format_tool_result_content({:ok, result}) when is_map(result) do
    case extract_content_parts_result(result) do
      {:ok, output, parts} ->
        encode_tool_result_envelope(%{ok: true, result: build_tool_result_payload(output, parts)}, parts)

      :error ->
        encode_tool_result_envelope(%{ok: true, result: result})
    end
  end

  def format_tool_result_content({:ok, result}), do: encode_tool_result_envelope(%{ok: true, result: result})

  def format_tool_result_content({:error, error}) do
    encode_tool_result_envelope(%{
      ok: false,
      error: SignalHelpers.normalize_error(error, :execution_error, "Tool execution failed")
    })
  end

  def format_tool_result_content(other) do
    encode_tool_result_envelope(%{
      ok: false,
      error: SignalHelpers.error_envelope(:invalid_result, "Invalid tool result envelope", %{result: inspect(other)})
    })
  end

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

  defp normalize_reasoning_details(reasoning_details) when is_list(reasoning_details) and reasoning_details != [],
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

  defp normalize_tool_call(%{} = tool_call) do
    %{
      id: normalize_text(extract_tool_call_id(tool_call)),
      name: normalize_text(extract_tool_call_name(tool_call)),
      arguments: normalize_tool_arguments(extract_tool_call_arguments(tool_call))
    }
  end

  defp normalize_tool_call(other), do: other

  defp assistant_tool_calls(%__MODULE__{type: :tool_calls, tool_calls: tool_calls}) when is_list(tool_calls),
    do: tool_calls

  defp assistant_tool_calls(%__MODULE__{tool_calls: tool_calls}) when is_list(tool_calls) and tool_calls != [],
    do: tool_calls

  defp assistant_tool_calls(_turn), do: nil

  defp normalize_tool_results(results) when is_list(results) do
    Enum.map(results, &normalize_tool_result/1)
  end

  defp normalize_tool_results(_), do: []

  defp normalize_tool_result(%{} = result) do
    raw_result = get_field(result, :raw_result, {:ok, get_field(result, :result), []}) |> normalize_raw_result()
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

  defp normalize_usage(nil), do: nil

  defp normalize_usage(usage) when is_map(usage) do
    usage
    |> Enum.map(fn {key, value} -> {normalize_usage_key(key), normalize_usage_value(value)} end)
    |> Map.new()
  end

  defp normalize_usage(_), do: nil

  defp normalize_metadata(%{} = metadata), do: metadata
  defp normalize_metadata(_), do: %{}

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

  defp execute_internal(module, tool_name, params, context, timeout, exec_opts) do
    schema = module.schema()
    normalized_params = normalize_params(params, schema)
    run_opts = timeout_opts(timeout) ++ exec_opts

    result =
      case Jido.Exec.run(module, normalized_params, context, run_opts) do
        {:ok, output} ->
          {:ok, output, []}

        {:ok, output, effects} ->
          {:ok, output, List.wrap(effects)}

        {:error, reason} ->
          {:error, format_error(tool_name, reason), []}

        {:error, reason, effects} ->
          {:error, format_error(tool_name, reason), List.wrap(effects)}
      end

    apply_effect_policy(result, context)
  rescue
    e ->
      {:error, format_exception(tool_name, e, __STACKTRACE__), []}
  catch
    kind, reason ->
      {:error, format_catch(tool_name, kind, reason), []}
  end

  defp format_error(tool_name, %TimeoutError{} = reason) do
    timeout_ms = reason.timeout || timeout_from_details(reason.details)
    message = Exception.message(reason)

    SignalHelpers.error_envelope(
      :timeout,
      message,
      %{tool_name: tool_name, timeout_ms: timeout_ms}
      |> Map.merge(reason.details || %{}),
      true
    )
  end

  defp format_error(tool_name, reason) when is_exception(reason) do
    SignalHelpers.normalize_error(reason, :execution_error, Exception.message(reason), %{tool_name: tool_name})
  end

  defp format_error(tool_name, reason) do
    SignalHelpers.normalize_error(reason, :execution_error, "Tool execution failed", %{tool_name: tool_name})
  end

  defp format_exception(tool_name, exception, stacktrace) do
    Logger.error("Tool execution exception",
      tool_name: tool_name,
      exception_message: Exception.message(exception),
      exception_type: exception.__struct__,
      stacktrace: format_stacktrace_for_logging(stacktrace)
    )

    message = Exception.message(exception)

    SignalHelpers.error_envelope(
      :exception,
      message,
      %{tool_name: tool_name, exception_type: exception.__struct__},
      false
    )
  end

  defp format_catch(tool_name, kind, reason) do
    message = "Caught #{kind}: #{inspect(reason)}"

    SignalHelpers.error_envelope(
      :caught,
      message,
      %{tool_name: tool_name, kind: kind, reason: inspect(reason)},
      false
    )
  end

  defp timeout_from_details(%{} = details), do: get_field(details, :timeout)
  defp timeout_from_details(_), do: nil

  defp finalize_execute_telemetry(tool_name, {:error, %{type: :timeout}, _effects}, start_time, context) do
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
        request_id: context[:request_id] || context[:run_id],
        run_id: context[:run_id],
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
    duration_native = System.monotonic_time() - start_time

    metadata =
      %{
        tool_name: tool_name,
        result: result,
        call_id: context[:call_id],
        request_id: context[:request_id] || context[:run_id],
        run_id: context[:run_id],
        agent_id: context[:agent_id],
        thread_id: context[:thread_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:stop),
      duration_measurements(duration_native),
      metadata
    )
  end

  defp exception_execute_telemetry(tool_name, reason, start_time, context) do
    obs_cfg = context[:observability] || %{}
    duration_native = System.monotonic_time() - start_time

    metadata =
      %{
        tool_name: tool_name,
        reason: reason,
        call_id: context[:call_id],
        request_id: context[:request_id] || context[:run_id],
        run_id: context[:run_id],
        agent_id: context[:agent_id],
        thread_id: context[:thread_id],
        iteration: context[:iteration]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    Observe.emit(
      obs_cfg,
      Observe.tool_execute(:exception),
      duration_measurements(duration_native),
      metadata
    )
  end

  defp duration_measurements(duration_native) do
    %{duration_ms: System.convert_time_unit(duration_native, :native, :millisecond), duration: duration_native}
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
          {:error, SignalHelpers.error_envelope(:validation, "Missing tool name"), []}

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

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_keyword(keyword, _key, nil), do: keyword
  defp maybe_put_keyword(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp format_stacktrace_for_logging(stacktrace) do
    stacktrace
    |> Enum.take(5)
    |> Exception.format_stacktrace()
  end

  defp encode_tool_result_envelope(payload, parts \\ []) when is_map(payload) and is_list(parts) do
    encoded = Jason.encode!(payload)

    case parts do
      [] -> encoded
      normalized_parts -> [ContentPart.text(encoded) | normalized_parts]
    end
  end

  defp build_tool_result_payload(output, content, metadata \\ %{}) do
    payload =
      %{}
      |> maybe_add(:output, empty_map_to_nil(output))
      |> maybe_add(:content, normalize_tool_result_content_payload(content))
      |> maybe_add(:metadata, empty_map_to_nil(metadata))

    case payload do
      %{output: result} when map_size(payload) == 1 -> result
      %{content: result} when map_size(payload) == 1 -> result
      %{} = map when map_size(map) > 0 -> map
      _ -> nil
    end
  end

  defp extract_content_parts_result(result) do
    case get_field(result, :__content_parts__) do
      parts when is_list(parts) ->
        clean_result =
          result
          |> Map.delete(:__content_parts__)
          |> Map.delete("__content_parts__")

        {:ok, empty_map_to_nil(clean_result), normalize_content_parts(parts)}

      _ ->
        :error
    end
  end

  defp normalize_content_parts(parts) when is_list(parts) do
    Enum.flat_map(parts, fn
      %ContentPart{} = part ->
        [part]

      text when is_binary(text) ->
        [ContentPart.text(text)]

      %{type: type} = part ->
        case normalize_content_part_map(type, part) do
          nil -> [ContentPart.text(inspect(part))]
          normalized -> [normalized]
        end

      %{"type" => type} = part ->
        case normalize_content_part_map(type, part) do
          nil -> [ContentPart.text(inspect(part))]
          normalized -> [normalized]
        end

      other ->
        [ContentPart.text(inspect(other))]
    end)
  end

  defp normalize_content_parts(content) when is_binary(content), do: [ContentPart.text(content)]
  defp normalize_content_parts(nil), do: []
  defp normalize_content_parts(other), do: [ContentPart.text(inspect(other))]

  defp normalize_content_part_map(type, part) when type in [:text, "text"] do
    text = get_field(part, :text)
    metadata = get_field(part, :metadata, %{})
    if is_binary(text), do: ContentPart.text(text, metadata), else: nil
  end

  defp normalize_content_part_map(type, part) when type in [:thinking, "thinking"] do
    text = get_field(part, :thinking) || get_field(part, :text)
    metadata = get_field(part, :metadata, %{})
    if is_binary(text), do: ContentPart.thinking(text, metadata), else: nil
  end

  defp normalize_content_part_map(type, part) when type in [:image_url, "image_url"] do
    url = get_field(part, :url)
    metadata = get_field(part, :metadata, %{})
    if is_binary(url), do: ContentPart.image_url(url, metadata), else: nil
  end

  defp normalize_content_part_map(type, part) when type in [:image, "image"] do
    data = get_field(part, :data)
    media_type = get_field(part, :media_type, "image/png")
    metadata = get_field(part, :metadata, %{})

    cond do
      is_binary(data) and metadata == %{} -> ContentPart.image(data, media_type)
      is_binary(data) -> ContentPart.image(data, media_type, metadata)
      true -> nil
    end
  end

  defp normalize_content_part_map(type, part) when type in [:file, "file"] do
    data = get_field(part, :data)
    filename = get_field(part, :filename)
    media_type = get_field(part, :media_type, "application/octet-stream")

    if is_binary(data) and is_binary(filename) do
      ContentPart.file(data, filename, media_type)
    else
      nil
    end
  end

  defp normalize_content_part_map(_, _), do: nil

  defp content_parts_list?(parts) when is_list(parts) and parts != [] do
    Enum.all?(parts, fn
      %ContentPart{} -> true
      %{type: type} when type in [:text, :thinking, :image_url, :image, :file] -> true
      %{"type" => type} when type in ["text", "thinking", "image_url", "image", "file"] -> true
      _ -> false
    end)
  end

  defp content_parts_list?(_), do: false

  defp empty_map_to_nil(%{} = map) when map_size(map) == 0, do: nil
  defp empty_map_to_nil(value), do: value

  defp normalize_tool_result_content_payload(content) when is_binary(content), do: content

  defp normalize_tool_result_content_payload(content) when is_list(content) do
    if content_parts_list?(content),
      do: serialize_content_parts(normalize_content_parts(content)),
      else: content
  end

  defp normalize_tool_result_content_payload(nil), do: nil
  defp normalize_tool_result_content_payload(other), do: other

  defp serialize_content_parts(parts) when is_list(parts) do
    Enum.map(parts, fn
      %ContentPart{} = part ->
        part
        |> Map.from_struct()
        |> Enum.reject(fn
          {:metadata, metadata} -> metadata in [nil, %{}]
          {_key, value} -> is_nil(value)
        end)
        |> Map.new()

      other ->
        other
    end)
  end

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
    do: encode_tool_result_envelope(%{ok: true, result: build_tool_result_payload(content, nil)})

  defp normalize_tool_result_content(_content, raw_result), do: format_tool_result_content(raw_result)

  defp canonical_tool_payload?(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"ok" => _}} -> true
      _ -> false
    end
  end

  defp normalize_raw_result(raw_result), do: Effects.normalize_result(raw_result)

  defp apply_effect_policy(result, context) do
    policy = Effects.policy_from_context(context, Effects.default_policy())
    {filtered_result, stats} = Effects.filter_result(result, policy)

    if stats.dropped_count > 0 do
      Logger.debug("Dropped disallowed tool effects count=#{stats.dropped_count} status=#{elem(filtered_result, 0)}")
    end

    filtered_result
  end

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
