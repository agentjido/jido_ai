defmodule Jido.AI.Request do
  @moduledoc """
  Request tracking for AI agents with per-request isolation and correlation.

  This module provides a standardized way to track requests and their results
  in AI agents, solving the "single-slot overwrite" problem where concurrent
  requests can overwrite each other's results.

  ## Pattern

  Follows the Elixir `Task.async/await` pattern:

      # Async (returns handle for later awaiting)
      {:ok, request} = MyAgent.ask(pid, "What is 2+2?")

      # Await specific request
      {:ok, result} = MyAgent.await(request, timeout: 30_000)

      # Or use sync convenience wrapper
      {:ok, result} = MyAgent.ask_sync(pid, "What is 2+2?")

  ## Request Struct

  The `Request` struct contains:
  - `id` - Unique request identifier (UUID)
  - `server` - The agent server (pid or via tuple)
  - `query` - The original query/prompt
  - `status` - Current status (`:pending`, `:completed`, `:failed`)
  - `result` - The result when completed
  - `error` - Error details if failed
  - `inserted_at` - When the request was created

  ## State Schema

  Agents using request tracking should include in their state:

      requests: %{request_id => Handle.t()}

  This module provides helpers for managing this map.

  ## Usage in Agent Macros

  ```elixir
  defmodule MyAgent do
    use Jido.AI.Agent, ...

    # ask/2 now returns {:ok, Handle.t()}
    def ask(pid, query, opts \\\\ []) do
      Jido.AI.Request.create_and_send(pid, query, opts,
        signal_type: "ai.react.query",
        source: "/ai/react/agent"
      )
    end

    # await/2 waits for specific request
    def await(request, opts \\\\ []) do
      Jido.AI.Request.await(request, opts)
    end
  end
  ```
  """

  alias Jido.Signal

  @type status :: :pending | :completed | :failed | :timeout
  @type server :: pid() | atom() | {:via, module(), term()}

  @default_timeout 30_000
  @default_max_requests 100

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
                query: Zoi.string(description: "The original query/prompt"),
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
    @spec new(String.t(), server(), String.t()) :: t()
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
      %{request | status: :completed, result: result, completed_at: System.system_time(:millisecond)}
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

  - `:tool_context` - Additional context merged with agent's tool_context
  - `:request_id` - Custom request ID (auto-generated if not provided)

  ## Signal Options (required)

  - `:signal_type` - The signal type to create (e.g., "ai.react.query")
  - `:source` - The signal source (e.g., "/ai/react/agent")

  ## Examples

      {:ok, request} = Request.create_and_send(pid, "What is 2+2?",
        tool_context: %{actor: user},
        signal_type: "ai.react.query",
        source: "/ai/react/agent"
      )
  """
  @spec create_and_send(server(), String.t(), keyword()) ::
          {:ok, Handle.t()} | {:error, term()}
  def create_and_send(server, query, opts) when is_binary(query) do
    signal_type = Keyword.fetch!(opts, :signal_type)
    source = Keyword.fetch!(opts, :source)
    tool_context = Keyword.get(opts, :tool_context, %{})
    request_id = Keyword.get_lazy(opts, :request_id, &generate_id/0)

    # Build payload with request_id for correlation.
    # Keep both query and prompt keys so all strategy start schemas can consume it.
    payload =
      %{query: query, prompt: query, request_id: request_id}
      |> maybe_add_tool_context(tool_context)

    signal = Signal.new!(signal_type, payload, source: source)

    case Jido.AgentServer.cast(server, signal) do
      :ok ->
        request = Handle.new(request_id, server, query)
        {:ok, request}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Synchronously sends a request and waits for the result.

  Convenience wrapper that combines `create_and_send/3` and `await/2`.

  ## Options

  All options from `create_and_send/3` plus:
  - `:timeout` - How long to wait (default: 30_000ms)

  ## Examples

      {:ok, result} = Request.send_and_await(pid, "What is 2+2?",
        timeout: 10_000,
        signal_type: "ai.react.query",
        source: "/ai/react/agent"
      )
  """
  @spec send_and_await(server(), String.t(), keyword()) ::
          {:ok, any()} | {:error, term()}
  def send_and_await(server, query, opts) when is_binary(query) do
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

  `Request.await/2` always uses the internal request paths under
  `state.requests[request_id]` for status, result, and error tracking.

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

    # Use AgentServer's await_completion with request-specific paths
    Jido.AgentServer.await_completion(server,
      timeout: timeout,
      status_path: [:requests, request_id, :status],
      result_path: [:requests, request_id, :result],
      error_path: [:requests, request_id, :error]
    )
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

    # Run awaits concurrently with Task.async_stream
    requests
    |> Task.async_stream(
      fn request -> await(request, timeout: timeout) end,
      timeout: timeout + 1000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {:error, :timeout}
      {:exit, reason} -> {:error, reason}
    end)
  end

  # ---------------------------------------------------------------------------
  # State Management Helpers
  # ---------------------------------------------------------------------------

  @doc """
  Initializes request tracking state fields.

  Call this when setting up agent state to add the `requests` map.

  ## Options

  - `:max_requests` - Maximum requests to keep (default: 100)

  ## Examples

      state = Request.init_state(%{})
      # => %{requests: %{}, __request_tracking__: %{max_requests: 100}}
  """
  @spec init_state(map(), keyword()) :: map()
  def init_state(state, opts \\ []) when is_map(state) do
    max_requests = Keyword.get(opts, :max_requests, @default_max_requests)

    state
    |> Map.put_new(:requests, %{})
    |> Map.put(:__request_tracking__, %{max_requests: max_requests})
  end

  @doc """
  Records a new request in agent state.

  Called in `on_before_cmd/2` when a request starts.

  ## Examples

      def on_before_cmd(agent, {:ai_react_start, %{query: query, request_id: req_id}} = action) do
        agent = Request.start_request(agent, req_id, query)
        {:ok, agent, action}
      end
  """
  @spec start_request(struct(), String.t(), String.t()) :: struct()
  def start_request(agent, request_id, query) when is_binary(request_id) and is_binary(query) do
    request = %{
      query: query,
      status: :pending,
      result: nil,
      error: nil,
      inserted_at: System.system_time(:millisecond),
      completed_at: nil
    }

    state =
      agent.state
      |> put_in([:requests, request_id], request)
      |> maybe_evict_old_requests()
      # Also update convenience fields for backward compatibility
      |> Map.put(:last_query, query)
      |> Map.put(:last_request_id, request_id)
      |> Map.put(:completed, false)
      |> Map.put(:last_answer, "")

    %{agent | state: state}
  end

  @doc """
  Marks a request as completed with a result.

  Called in `on_after_cmd/3` when a request finishes successfully.

  ## Examples

      def on_after_cmd(agent, {:ai_react_start, %{request_id: req_id}}, directives) do
        snap = strategy_snapshot(agent)
        if snap.done? do
          agent = Request.complete_request(agent, req_id, snap.result)
        end
        {:ok, agent, directives}
      end
  """
  @spec complete_request(struct(), String.t(), any(), keyword()) :: struct()
  def complete_request(agent, request_id, result, opts \\ []) do
    meta = Keyword.get(opts, :meta, %{})

    state =
      agent.state
      |> update_in([:requests, request_id], fn
        nil ->
          %{status: :completed, result: result, meta: meta, completed_at: System.system_time(:millisecond)}

        req ->
          %{req | status: :completed, result: result, completed_at: System.system_time(:millisecond)}
          |> Map.put(:meta, Map.merge(Map.get(req, :meta, %{}), meta))
      end)
      |> Map.put(:last_answer, result || "")
      |> Map.put(:completed, true)

    %{agent | state: state}
  end

  @doc """
  Marks a request as failed with an error.

  Called when a request encounters an error.
  """
  @spec fail_request(struct(), String.t(), any()) :: struct()
  def fail_request(agent, request_id, error) do
    state =
      agent.state
      |> update_in([:requests, request_id], fn
        nil ->
          %{status: :failed, error: error, completed_at: System.system_time(:millisecond)}

        req ->
          %{req | status: :failed, error: error, completed_at: System.system_time(:millisecond)}
      end)
      |> Map.put(:completed, true)

    %{agent | state: state}
  end

  @doc """
  Gets a request by ID from agent state.

  Returns `nil` if not found.
  """
  @spec get_request(struct(), String.t()) :: map() | nil
  def get_request(agent, request_id) do
    get_in(agent.state, [:requests, request_id])
  end

  @doc """
  Gets the result of a request if completed.

  Returns `{:ok, result}` if completed, `{:error, error}` if failed,
  or `{:pending, request}` if still in progress.
  """
  @spec get_result(struct(), String.t()) :: {:ok, any()} | {:error, any()} | {:pending, map()} | nil
  def get_result(agent, request_id) do
    case get_request(agent, request_id) do
      nil -> nil
      %{status: :completed, result: result} -> {:ok, result}
      %{status: :failed, error: error} -> {:error, error}
      %{status: :pending} = req -> {:pending, req}
    end
  end

  @doc """
  Extracts request_id from action params, generating one if not present.

  Use this in signal routing or action preparation.
  """
  @spec ensure_request_id(map()) :: {String.t(), map()}
  def ensure_request_id(%{request_id: request_id} = params) when is_binary(request_id) do
    {request_id, params}
  end

  def ensure_request_id(params) when is_map(params) do
    request_id = generate_id()
    {request_id, Map.put(params, :request_id, request_id)}
  end

  # ---------------------------------------------------------------------------
  # Schema Helpers for Agent Macros
  # ---------------------------------------------------------------------------

  @doc """
  Returns the Zoi schema fields for request tracking.

  Include this in your agent macro's schema definition.

  ## Example

      base_schema_ast = quote do
        Zoi.object(Map.merge(
          %{
            model: Zoi.string() |> Zoi.default("..."),
            # ... other fields
          },
          Jido.AI.Request.schema_fields()
        ))
      end
  """
  @spec schema_fields() :: map()
  def schema_fields do
    # Note: This returns a map suitable for Zoi.object
    # The actual Zoi schema wrapping happens in the macro
    %{
      requests: quote(do: Zoi.map() |> Zoi.default(%{})),
      last_request_id: quote(do: Zoi.string() |> Zoi.optional()),
      # Backward compat fields
      last_query: quote(do: Zoi.string() |> Zoi.default("")),
      last_answer: quote(do: Zoi.string() |> Zoi.default("")),
      completed: quote(do: Zoi.boolean() |> Zoi.default(false))
    }
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

  defp normalize_await_result({:ok, %{status: :completed, result: result}}) do
    {:ok, result}
  end

  defp normalize_await_result({:ok, %{status: :failed} = payload}) do
    {:error, payload[:error] || payload[:result] || :failed}
  end

  defp normalize_await_result({:ok, %{status: :timeout}}) do
    {:error, :timeout}
  end

  defp normalize_await_result({:ok, %{error: error}}) when not is_nil(error) do
    {:error, error}
  end

  defp normalize_await_result({:ok, %{result: result}}) do
    {:ok, result}
  end

  defp normalize_await_result({:error, _} = error), do: error

  defp maybe_evict_old_requests(state) do
    max = get_in(state, [:__request_tracking__, :max_requests]) || @default_max_requests
    requests = Map.get(state, :requests, %{})

    if map_size(requests) > max do
      # Keep most recent requests by inserted_at
      sorted =
        requests
        |> Enum.sort_by(fn {_id, req} -> req[:inserted_at] || 0 end, :desc)
        |> Enum.take(max)
        |> Map.new()

      Map.put(state, :requests, sorted)
    else
      state
    end
  end
end
