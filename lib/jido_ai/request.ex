defmodule Jido.AI.Request do
  @moduledoc """
  AI request handles, correlation, waiting, and streaming.

  ## Pattern

  Follows the Elixir `Task.async/await` pattern:

      # Async (returns handle for later awaiting)
      {:ok, request} = MyAgent.ask(pid, "What is 2+2?")

      # Await specific request
      {:ok, result} = MyAgent.await(request, timeout: 30_000)

      # Or use sync convenience wrapper
      {:ok, result} = MyAgent.ask_sync(pid, "What is 2+2?")

  ## Request handle

  A `Jido.AI.Request.Handle` contains:
  - `id` - Unique request identifier (UUID)
  - `server` - The agent server (pid or via tuple)
  - `query` - The original query/prompt
  - `status` - Current status (`:pending`, `:completed`, `:failed`)
  - `result` - The result when completed
  - `error` - Error details if failed
  - `inserted_at` - When the request was created

  ## Agent API

  ```elixir
  defmodule MyAgent do
    use Jido.AI.Agent, name: "my_agent"

    agent do
      # Define a session AI profile and route here.
    end
  end
  ```

  The generated `ask/3`, `ask_sync/3`, `ask_stream/3`, and `await/2`
  functions use this module.
  """

  alias Jido.AI.Request.Stream, as: RequestStream
  alias Jido.AI.Query
  alias Jido.Signal

  @type status :: :pending | :completed | :failed | :timeout
  @type server :: pid() | atom() | {:via, module(), term()}

  @default_timeout 30_000

  # ---------------------------------------------------------------------------
  # Handle Struct
  # ---------------------------------------------------------------------------

  defmodule Handle do
    @moduledoc """
    Represents a tracked request handle with correlation ID.

    Similar to `%Task{}`, this struct holds the information needed to
    await a specific request's completion.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique request identifier (UUID)"),
                server: Zoi.any(description: "The agent server (pid, atom, or via tuple)"),
                query: Query.schema(description: "The original query/prompt"),
                status:
                  Zoi.enum([:pending, :completed, :failed, :timeout],
                    description: "Current request status"
                  )
                  |> Zoi.default(:pending),
                result: Zoi.any(description: "The result when completed") |> Zoi.nullish(),
                error: Zoi.any(description: "Error details if failed") |> Zoi.nullish(),
                inserted_at:
                  Zoi.integer(description: "When the request was created (ms)")
                  |> Zoi.nullish(),
                completed_at:
                  Zoi.integer(description: "When the request completed (ms)")
                  |> Zoi.nullish()
              },
              coerce: true
            )

    @type server :: pid() | atom() | {:via, module(), term()}
    @type status :: :pending | :completed | :failed | :timeout
    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc """
    Creates a new Handle struct.
    """
    @spec new(String.t(), server(), Query.t()) :: t()
    def new(id, server, query) do
      %__MODULE__{
        id: id,
        server: server,
        query: query,
        status: :pending,
        inserted_at: System.system_time(:millisecond)
      }
    end

    @doc """
    Marks request as completed with a result.
    """
    @spec complete(t(), any()) :: t()
    def complete(%__MODULE__{} = request, result) do
      %{
        request
        | status: :completed,
          result: result,
          completed_at: System.system_time(:millisecond)
      }
    end

    @doc """
    Marks request as failed with an error.
    """
    @spec fail(t(), any()) :: t()
    def fail(%__MODULE__{} = request, error) do
      %{request | status: :failed, error: error, completed_at: System.system_time(:millisecond)}
    end
  end

  # ---------------------------------------------------------------------------
  # Public API - Creating Requests
  # ---------------------------------------------------------------------------

  @doc """
  Creates a request, sends the signal, and returns the request handle.

  This is the primary entry point for agents implementing `ask/2`.

  ## Options

  - `:model` - Request-scoped model alias or ReqLLM model input
  - `:tool_context` - Additional context merged with agent's tool_context
  - `:tools` - ReAct-only request-scoped tool registry override for this run
  - `:allowed_tools` - ReAct-only request-scoped allowlist of tool names
  - `:request_transformer` - ReAct-only module implementing per-turn request shaping
  - `:max_iterations` - ReAct-only request-scoped maximum reasoning iterations
  - `:stream_timeout_ms` - ReAct-only request-scoped runtime inactivity timeout
  - `:tool_heartbeat_ms` - ReAct-only request-scoped tool-execution keepalive
    interval in ms (0 = off). Emits a `:keepalive` event while tools run.
  - `:req_http_options` - Per-request Req HTTP options forwarded to ReAct runtime
  - `:llm_opts` - Per-request ReqLLM generation options forwarded to ReAct runtime
  - `:file_id` / `:file_ids` / `:file_reference` / `:file_references` - Uploaded
    file references appended to the user query as ReqLLM content parts when supported by the ReqLLM version
  - `:output` - `:raw` to bypass agent-level structured output for this request,
    or a request-scoped structured output config
  - `:extra_refs` - Map of additional refs to attach to the user message thread entry
  - `:stream_to` - Optional request-scoped runtime event sink, currently `{:pid, pid}`
  - `:stream` - Use provider streaming. Defaults to true with an event sink,
    otherwise false. Set false with a sink to receive lifecycle events only.
  - `:request_id` - Custom request ID (auto-generated if not provided)
  - `:run_id` - Custom nonempty run ID (auto-generated if not provided)

  ## Signal Options (required)

  - `:signal_type` - The declared Agent route to call
  - `:source` - The Signal source

  ## Examples

      {:ok, request} = Request.create_and_send(pid, "What is 2+2?",
        tool_context: %{actor: user},
        signal_type: "support.ask",
        source: "/my_app/support"
      )
  """
  @spec create_and_send(server(), Query.t(), keyword()) ::
          {:ok, Handle.t()} | {:error, term()}
  def create_and_send(server, query, opts) when is_binary(query) or is_list(query) do
    signal_type = Keyword.fetch!(opts, :signal_type)
    source = Keyword.fetch!(opts, :source)
    tool_context = Keyword.get(opts, :tool_context, %{})
    tools = Keyword.get(opts, :tools)
    allowed_tools = Keyword.get(opts, :allowed_tools)
    request_transformer = Keyword.get(opts, :request_transformer)
    max_iterations = Keyword.get(opts, :max_iterations)

    stream_timeout_ms = Keyword.get(opts, :stream_timeout_ms)

    tool_heartbeat_ms = Keyword.get(opts, :tool_heartbeat_ms)
    req_http_options = Keyword.get(opts, :req_http_options, [])

    llm_opts =
      Jido.AI.Model.Transport.bind_options([%{role: :user, content: query}], Keyword.get(opts, :llm_opts, []))

    output = Keyword.get(opts, :output)
    request_id = Keyword.get_lazy(opts, :request_id, &generate_id/0)
    stream_to = Keyword.get(opts, :stream_to)

    with {:ok, query} <- Query.attach_file_references(query, opts),
         {:ok, stream_to} <- RequestStream.normalize_sink(stream_to),
         stream = Keyword.get(opts, :stream, stream_to != nil),
         :ok <- validate_stream(stream) do
      # Build payload with request_id for correlation.
      # Keep both query and prompt keys so all strategy start schemas can consume it.
      extra_refs = Keyword.get(opts, :extra_refs, %{})

      payload =
        %{query: query, prompt: query, request_id: request_id, stream: stream}
        |> maybe_add_model(Keyword.get(opts, :model))
        |> maybe_add_tool_context(tool_context)
        |> maybe_add_tools(tools)
        |> maybe_add_allowed_tools(allowed_tools)
        |> maybe_add_request_transformer(request_transformer)
        |> maybe_add_max_iterations(max_iterations)
        |> maybe_add_stream_timeout_ms(stream_timeout_ms)
        |> maybe_add_tool_heartbeat_ms(tool_heartbeat_ms)
        |> maybe_add_req_http_options(req_http_options)
        |> maybe_add_llm_opts(llm_opts)
        |> maybe_add_output(output)
        |> maybe_add_extra_refs(extra_refs)
        |> maybe_add_stream_to(stream_to)

      signal = Signal.new!(signal_type, payload, source: source)

      signal =
        if Keyword.has_key?(opts, :run_id),
          do: %{signal | data: Map.put(signal.data, :run_id, opts[:run_id])},
          else: signal

      Jido.AI.Orchestration.submit(server, signal, stream_to, opts)
    end
  end

  def create_and_send(_server, _query, _opts),
    do: Jido.AI.Profile.error("query", "Expected text or a list of content parts")

  defp validate_stream(value) when is_boolean(value), do: :ok
  defp validate_stream(_), do: Jido.AI.Profile.error("request.stream", "Expected a boolean")

  @doc """
  Synchronously sends a request and waits for the result.

  Convenience wrapper that combines `create_and_send/3` and `await/2`.

  ## Options

  All options from `create_and_send/3` plus:
  - `:timeout` - How long to wait (default: 30_000ms)

  ## Examples

      {:ok, result} = Request.send_and_await(pid, "What is 2+2?",
        timeout: 10_000,
        signal_type: "support.ask",
        source: "/my_app/support"
      )
  """
  @spec send_and_await(server(), Query.t(), keyword()) ::
          {:ok, any()} | {:error, term()}
  def send_and_await(server, query, opts) when is_binary(query) or is_list(query) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    with {:ok, request} <- create_and_send(server, query, opts) do
      await(request, timeout: timeout)
    end
  end

  # ---------------------------------------------------------------------------
  # Public API - Awaiting Requests
  # ---------------------------------------------------------------------------

  @doc """
  Awaits completion of a specific request.

  Similar to `Task.await/2`, this blocks until the request completes,
  fails, or times out.

  ## Options

  - `:timeout` - How long to wait (default: 30_000ms)

  `Request.await/2` reads committed request records through the core Plugin
  state API. A caller timeout does not cancel the model task.

  ## Returns

  - `{:ok, result}` - Request completed successfully
  - `{:error, :timeout}` - Request didn't complete in time
  - `{:error, reason}` - Request failed

  ## Examples

      {:ok, request} = MyAgent.ask(pid, "question")
      {:ok, result} = Request.await(request, timeout: 10_000)
  """
  @spec await(Handle.t(), keyword()) :: {:ok, any()} | {:error, term()}
  def await(%Handle{id: request_id, server: server}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    Jido.AI.Orchestration.await(server, request_id, timeout)
    |> normalize_await_result()
  end

  @doc """
  Awaits multiple requests, returning results in the same order.

  Similar to `Task.await_many/2`.

  ## Options

  - `:timeout` - How long to wait for all requests (default: 30_000ms)

  ## Returns

  A list of results in the same order as the input requests.
  Each element is either `{:ok, result}` or `{:error, reason}`.
  """
  @spec await_many([Handle.t()], keyword()) :: [{:ok, any()} | {:error, term()}]
  def await_many(requests, opts \\ []) when is_list(requests) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    tasks = Enum.map(requests, &Task.async(fn -> await(&1, timeout: :infinity) end))

    tasks
    |> Task.yield_many(timeout)
    |> Enum.map(fn
      {_task, {:ok, result}} ->
        result

      {_task, {:exit, reason}} ->
        {:error, reason}

      {task, nil} ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end)
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp generate_id do
    Jido.Signal.ID.generate!()
  end

  defp maybe_add_tool_context(payload, tool_context) when map_size(tool_context) > 0 do
    Map.put(payload, :tool_context, tool_context)
  end

  defp maybe_add_tool_context(payload, _), do: payload

  defp maybe_add_stream_timeout_ms(payload, stream_timeout_ms)
       when is_integer(stream_timeout_ms) and stream_timeout_ms >= 0 do
    Map.put(payload, :stream_timeout_ms, stream_timeout_ms)
  end

  defp maybe_add_stream_timeout_ms(payload, _), do: payload

  defp maybe_add_tool_heartbeat_ms(payload, tool_heartbeat_ms)
       when is_integer(tool_heartbeat_ms) and tool_heartbeat_ms >= 0 do
    Map.put(payload, :tool_heartbeat_ms, tool_heartbeat_ms)
  end

  defp maybe_add_tool_heartbeat_ms(payload, _), do: payload

  defp maybe_add_max_iterations(payload, max_iterations)
       when is_integer(max_iterations) and max_iterations > 0 do
    Map.put(payload, :max_iterations, max_iterations)
  end

  defp maybe_add_max_iterations(payload, _), do: payload

  defp maybe_add_stream_to(payload, nil), do: payload
  defp maybe_add_stream_to(payload, stream_to), do: Map.put(payload, :stream_to, stream_to)

  defp maybe_add_tools(payload, nil), do: payload
  defp maybe_add_tools(payload, tools), do: Map.put(payload, :tools, tools)

  defp maybe_add_allowed_tools(payload, allowed_tools) when is_list(allowed_tools) do
    Map.put(payload, :allowed_tools, allowed_tools)
  end

  defp maybe_add_allowed_tools(payload, _), do: payload

  defp maybe_add_request_transformer(payload, nil), do: payload

  defp maybe_add_request_transformer(payload, request_transformer),
    do: Map.put(payload, :request_transformer, request_transformer)

  defp maybe_add_model(payload, model) when model in [nil, ""], do: payload
  defp maybe_add_model(payload, model), do: Map.put(payload, :model, model)

  defp maybe_add_req_http_options(payload, options) when options in [nil, []], do: payload

  defp maybe_add_req_http_options(payload, options),
    do: Map.put(payload, :req_http_options, options)

  defp maybe_add_llm_opts(payload, options) when options in [nil, [], %{}], do: payload
  defp maybe_add_llm_opts(payload, options), do: Map.put(payload, :llm_opts, options)

  defp maybe_add_output(payload, nil), do: payload
  defp maybe_add_output(payload, output), do: Map.put(payload, :output, output)

  defp maybe_add_extra_refs(payload, refs) when is_map(refs) and map_size(refs) > 0 do
    Map.put(payload, :extra_refs, refs)
  end

  defp maybe_add_extra_refs(payload, _), do: payload

  defp normalize_await_result({:ok, %{status: :completed, result: result}}) do
    {:ok, result}
  end

  defp normalize_await_result({:ok, %{status: :failed} = payload}) do
    {:error, payload[:error] || payload[:result] || :failed}
  end

  defp normalize_await_result({:ok, %{status: :timeout}}) do
    {:error, :timeout}
  end

  defp normalize_await_result({:error, {:timeout, _diagnostic}}) do
    {:error, :timeout}
  end

  defp normalize_await_result({:ok, %{error: error}}) when not is_nil(error) do
    {:error, error}
  end

  defp normalize_await_result({:ok, %{result: result}}) do
    {:ok, result}
  end

  defp normalize_await_result({:error, _} = error), do: error
end
