defmodule ServerSentEvent.Client do
  @moduledoc ~S"""
  Client that pulls and processes events from a server sent event stream.

  This client can be used to manage reconnecting a dropped connection.

  A specific client needs to implement the callbacks from this behaviour.
  Note there is no `use` macro in this module, therefore all callbacks must be implemented.

  ## Example

      defmodule AutoConnect do
        @behaviour ServerSentEvent.Client

        # Start connecting to the endpoint as soon as client is started.
        def init(state) do
          {:connect, request(state), state}
        end

        # The client has successfully connected, or reconnected, to the event stream.
        def handle_connect(_response, state) do
          {:noreply, state}
        end

        # Retry connecting to endpoint 1 second after a failure to connect.
        def handle_connect_failure(reason, state) do
          Process.sleep(1_000)
          {:connect, request(state), state}
        end

        # Immediatly try to reconnect when the connection is lost.
        def handle_disconnect(_, state) do
          {:connect, request(state), state}
        end

        # Update the running state of the client with the id of each event as it arrives.
        # This event id is used for reconnection.
        def handle_event(event, state) do
          IO.puts("I just got a new event: #{inspect(event)}")
          %{state | last_event_id: event.id}
        end

        # When stop message is received this process will exit with reason :normal.
        def handle_info(:stop, state) do
          {:stop, :normal, state}
        end

        # Not a callback but helpful pattern for creating requests in several callbacks
        defp request({url: url}) do
          Raxx.request(:GET, url)
          |> Raxx.set_header("accept", "text/event-stream")
          |> Raxx.set_header("last-event-id", state.last_event_id)
        end
      end

      # Starting the client
      {:ok, pid} = AutoConnect.start_link(%{url: "http://www.example.com/events", last_event_id: "0"})

      The client can also be added to a supervision tree

      children = [
        {AutoConnect, %{url: "http://www.example.com/events", last_event_id: "0"}}
      ]
  """

  @typedoc """
  State of the client process.

  The initial value of this state given as the second argument to start_link/3
  """
  @type state :: term

  @type request :: Raxx.Request.t()
  @type response :: Raxx.Response.t()

  @typedoc """
  Return value from any callback, except `handle_event/2`

  This value instructs the client process with what it should do next

  - `:connect` start the process of connection to an event source, using the request given.
  - `:noreply` do nothing, and wait for next message.
  - `:stop` stop the client and exit with reason.
  """
  @type return :: {:connect, request, state} | {:noreply, state} | {:stop, atom, state}
  @callback init(state) :: {:connect, request, state} | {:ok, state}
  @callback handle_connect(response, state) :: return
  @callback handle_connect_failure(term, state) :: return
  @callback handle_disconnect(term, state) :: return
  @callback handle_info(term, state) :: return
  @callback handle_event(ServerSentEvent.t(), state) :: state

  use GenServer
  @enforce_keys [:module, :internal_state, :socket, :chunk_buffer, :sse_buffer]
  defstruct @enforce_keys

  @spec start(module, state, GenServer.options()) :: GenServer.on_start()
  def start(module, internal_state, options \\ []) do
    state = %__MODULE__{
      module: module,
      internal_state: internal_state,
      socket: nil,
      chunk_buffer: "",
      sse_buffer: ""
    }

    GenServer.start(__MODULE__, state, options)
  end

  @spec start_link(module, state, GenServer.options()) :: GenServer.on_start()
  def start_link(module, internal_state, options \\ []) do
    state = %__MODULE__{
      module: module,
      internal_state: internal_state,
      socket: nil,
      chunk_buffer: "",
      sse_buffer: ""
    }

    GenServer.start_link(__MODULE__, state, options)
  end

  @impl GenServer
  def init(state) do
    case state.module.init(state.internal_state) do
      {:connect, request, internal_state} ->
        {:ok, %{state | internal_state: internal_state}, {:continue, {:connect, request}}}

      {:ok, internal_state} ->
        {:ok, %{state | internal_state: internal_state}}
    end
  end

  @impl GenServer
  def handle_continue({:connect, request}, state) do
    case start_streaming(request, state) do
      {:ok, {response, state}} ->
        if response do
          case wrap_response(state.module.handle_connect(response, state.internal_state), state) do
            # Maybe we should stop here without handling the packet?
            {:stop, request, state} ->
              {:stop, request, handle_packet("", state)}

            {:noreply, state} ->
              {:noreply, handle_packet("", state)}

            # This case is a no-op but handled elsewhere
            {:noreply, state, continuation} ->
              {:noreply, handle_packet("", state), continuation}
          end
        else
          wrap_response({:noreply, state.internal_state}, state)
        end

      {:error, reason} ->
        state.module.handle_connect_failure(reason, state.internal_state)
        |> wrap_response(state)
    end
  end

  @impl GenServer
  def handle_info({transport, socket, packet}, state = %__MODULE__{socket: {transport, socket}})
      when transport in [:tcp, :ssl] do
    state = handle_packet(packet, state)
    {:noreply, state}
  end

  def handle_info({transport_closed, socket}, state = %{socket: {_transport, socket}})
      when transport_closed in [:tcp_closed, :ssl_closed] do
    state = %{state | socket: nil}

    state.module.handle_disconnect({:ok, :closed}, state.internal_state)
    |> wrap_response(%{state | chunk_buffer: "", sse_buffer: ""})
  end

  def handle_info(other, state) do
    state.module.handle_info(other, state.internal_state)
    |> wrap_response(state)
  end

  def handle_packet(packet, state) do
    # As we are running the server, raising an error for badly formatted events
    {:ok, {chunks, chunk_buffer}} = pop_all_chunks(state.chunk_buffer <> packet)

    {:ok, {events, sse_buffer}} =
      ServerSentEvent.parse_all(state.sse_buffer <> :erlang.iolist_to_binary(chunks))

    # Call active before processing events in case event processing is slow
    # Return value is `:ok` or `{:error, reason}`, reason is most likely `:closed`.
    # The socket has already been set to active.
    # A :tcp_closed message will be received in case of socket closing, shutdown of this process is handled their.
    _ = set_active(state.socket)

    internal_state =
      Enum.reduce(events, state.internal_state, fn e, s -> state.module.handle_event(e, s) end)

    %{state | internal_state: internal_state, chunk_buffer: chunk_buffer, sse_buffer: sse_buffer}
  end

  defp start_streaming(request, state = %{socket: nil}) do
    case connect(request) do
      {:ok, socket} ->
        binary =
          case Raxx.HTTP1.serialize_request(request, connection: :close) do
            {head, {:complete, data}} ->
              [head, data]

            {_head, _body_state} ->
              raise "ServerSentEvent.Client must be started with a complete request."
          end

        case send_data(socket, binary) do
          :ok ->
            receive_response_head(socket, state)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_streaming(_request, state) do
    {:ok, {nil, state}}
  end

  defp receive_response_head(socket, state, head_buffer \\ "") do
    case recv(socket, 0, 2_000) do
      {:ok, packet} ->
        head_buffer = head_buffer <> packet

        case Raxx.HTTP1.parse_response(head_buffer) do
          {:ok, {response, _connection_state, :chunked, chunk_buffer}} ->
            :ok = set_active(socket)
            state = %{state | socket: socket, chunk_buffer: chunk_buffer}
            {:ok, {response, state}}

          {:ok, {response, _connection_state, _body_read_state, _buffer}} ->
            {:error, {:bad_response, response}}

          {:more, :undefined} ->
            receive_response_head(socket, state, head_buffer)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wrap_response({:noreply, internal_state}, state = %__MODULE__{}) do
    {:noreply, %{state | internal_state: internal_state}}
  end

  defp wrap_response({:connect, request, internal_state}, state = %__MODULE__{}) do
    {:noreply, %{state | internal_state: internal_state}, {:continue, {:connect, request}}}
  end

  defp wrap_response({:stop, reason, internal_state}, state = %__MODULE__{}) do
    {:stop, reason, %{state | internal_state: internal_state}}
  end

  defp pop_all_chunks(buffer, chunks \\ []) do
    case Raxx.HTTP1.parse_chunk(buffer) do
      {:ok, {nil, rest}} ->
        {:ok, {Enum.reverse(chunks), rest}}

      {:ok, {chunk, rest}} ->
        pop_all_chunks(rest, [chunk | chunks])
    end
  end

  defp connect(request) do
    scheme = request.scheme || :http
    host = :erlang.binary_to_list(Raxx.request_host(request))
    port = Raxx.request_port(request)
    options = [mode: :binary, active: false]

    case scheme do
      :http ->
        case :gen_tcp.connect(host, port, options, 2_000) do
          {:ok, socket} ->
            {:ok, {:tcp, socket}}

          {:error, reason} ->
            {:error, reason}
        end

      :https ->
        case :ssl.connect(host, port, options, 2_000) do
          {:ok, socket} ->
            {:ok, {:ssl, socket}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp set_active({:tcp, socket}) do
    :inet.setopts(socket, active: :once)
  end

  defp set_active({:ssl, socket}) do
    :ssl.setopts(socket, active: :once)
  end

  defp send_data({:tcp, socket}, message) do
    :gen_tcp.send(socket, message)
  end

  defp send_data({:ssl, socket}, message) do
    :ssl.send(socket, message)
  end

  defp recv({:tcp, socket}, bytes, timeout) do
    :gen_tcp.recv(socket, bytes, timeout)
  end

  defp recv({:ssl, socket}, bytes, timeout) do
    :ssl.recv(socket, bytes, timeout)
  end
end
