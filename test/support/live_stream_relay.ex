defmodule Jido.AI.TestSupport.LiveStreamRelay do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def url(server), do: GenServer.call(server, :url)

  @impl true
  def init(opts) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    {:ok, tasks} = Task.Supervisor.start_link()
    server = self()
    {:ok, _} = Task.Supervisor.start_child(tasks, fn -> accept(listener, tasks, server) end)

    {:ok,
     %{
       listener: listener,
       port: port,
       owner: opts[:owner],
       modes: opts[:modes] || [],
       upstream: opts[:upstream] || "https://api.openai.com/v1",
       api_key: opts[:api_key]
     }}
  end

  @impl true
  def handle_call(:url, _, state), do: {:reply, "http://127.0.0.1:#{state.port}/v1", state}

  def handle_call(:connection, _, state) do
    {mode, modes} =
      case state.modes do
        [mode | modes] -> {mode, modes}
        [] -> {:pass, []}
      end

    {:reply, {mode, Map.take(state, [:owner, :upstream, :api_key])}, %{state | modes: modes}}
  end

  @impl true
  def terminate(_, state), do: :gen_tcp.close(state.listener)

  defp accept(listener, tasks, server) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, pid} =
          Task.Supervisor.start_child(tasks, fn ->
            receive do
              :ready -> serve(socket, server)
            end
          end)

        :ok = :gen_tcp.controlling_process(socket, pid)
        send(pid, :ready)
        accept(listener, tasks, server)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve(socket, server) do
    try do
      {:ok, {:http_request, :POST, {:abs_path, path}, _}} = :gen_tcp.recv(socket, 0, 10_000)
      true = path in ["/v1/responses", "/v1/chat/completions"]
      length = headers(socket, 0)
      :ok = :inet.setopts(socket, packet: :raw)
      {:ok, body} = :gen_tcp.recv(socket, length, 10_000)
      {mode, opts} = GenServer.call(server, :connection)
      :ok = :inet.setopts(socket, active: true)
      forward(socket, path, body, mode, opts)
    after
      :gen_tcp.close(socket)
    end
  end

  defp forward(socket, path, body, mode, opts) do
    api_key = opts.api_key || System.fetch_env!("OPENAI_API_KEY")
    endpoint = opts.upstream <> String.replace_prefix(path, "/v1", "")

    result =
      Req.post(endpoint,
        body: body,
        headers: [
          authorization: "Bearer " <> api_key,
          "content-type": "application/json",
          "accept-encoding": "identity"
        ],
        into: :self,
        decode_body: false,
        retry: false,
        receive_timeout: 60_000
      )

    case result do
      {:ok, %{status: 200} = response} ->
        request_id = response |> Req.Response.get_header("x-request-id") |> List.first()

        state = %{
          socket: socket,
          response: response,
          owner: opts.owner,
          mode: mode,
          buffer: "",
          header_sent?: false,
          hold_next?: false,
          held?: false,
          upstream_done?: false,
          stats: %{
            upstream_status: 200,
            upstream_request_id: request_id,
            received_bytes: 0,
            held_bytes: 0,
            text_frames: 0
          }
        }

        try do
          relay(state)
        after
          Req.cancel_async_response(response)
        end

      {:ok, response} ->
        Req.cancel_async_response(response)
        send(opts.owner, {:relay_rejected, self(), response.status})

      {:error, error} ->
        send(opts.owner, {:relay_error, self(), Exception.message(error)})
    end
  end

  defp relay(%{upstream_done?: true, held?: false} = state) do
    send(state.owner, {:relay_closed, self(), Map.put(state.stats, :reason, :completed)})
  end

  defp relay(state) do
    receive do
      {:tcp_closed, socket} when socket == state.socket ->
        close(state, :client_closed)

      {:tcp_error, socket, _} when socket == state.socket ->
        close(state, :client_closed)

      :release ->
        state |> Map.put(:mode, :pass) |> Map.put(:held?, false) |> Map.put(:hold_next?, false) |> drain() |> relay()

      message ->
        case Req.parse_message(state.response, message) do
          {:ok, chunks} -> chunks |> Enum.reduce(state, &chunk/2) |> relay()
          {:error, error} -> close(state, {:upstream_error, Exception.message(error)})
          :unknown -> relay(state)
        end
    after
      65_000 -> close(state, :relay_timeout)
    end
  end

  defp close(state, reason) do
    result = Req.cancel_async_response(state.response)
    stats = state.stats |> Map.put(:reason, reason) |> Map.put(:upstream_cancel_requested, result == :ok)
    send(state.owner, {:relay_closed, self(), stats})
  end

  defp chunk({:data, data}, state) do
    state = update_in(state.stats.received_bytes, &(&1 + byte_size(data)))
    %{state | buffer: state.buffer <> data} |> drain()
  end

  defp chunk(:done, state), do: %{state | upstream_done?: true}
  defp chunk({:trailers, _}, state), do: state

  defp drain(%{held?: true} = state), do: state

  defp drain(state) do
    case :binary.match(state.buffer, ["\n\n", "\r\n\r\n"]) do
      {offset, length} ->
        size = offset + length
        frame = binary_part(state.buffer, 0, size)
        rest = binary_part(state.buffer, size, byte_size(state.buffer) - size)

        if state.mode == :before_response or state.hold_next? do
          stats = Map.put(state.stats, :held_bytes, byte_size(state.buffer))
          send(state.owner, {:relay_held, self(), stats})
          %{state | held?: true, stats: stats}
        else
          state = send_headers(state)
          :ok = :gen_tcp.send(state.socket, frame)
          text? = text_frame?(frame)
          state = if text?, do: update_in(state.stats.text_frames, &(&1 + 1)), else: state
          hold? = state.mode == :mid_stream and text?
          %{state | buffer: rest, hold_next?: hold?} |> drain()
        end

      :nomatch ->
        state
    end
  end

  defp send_headers(%{header_sent?: true} = state), do: state

  defp send_headers(state) do
    :ok = :gen_tcp.send(state.socket, "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\n")
    %{state | header_sent?: true}
  end

  defp text_frame?(frame) do
    frame
    |> String.split("\n")
    |> Enum.any?(fn line ->
      with "data:" <> data <- line,
           {:ok, decoded} <- Jason.decode(String.trim(data)) do
        case decoded do
          %{"type" => "response.output_text.delta", "delta" => text} -> is_binary(text) and text != ""
          %{"delta" => text} -> is_binary(text) and text != ""
          %{"choices" => choices} -> Enum.any?(choices, &(get_in(&1, ["delta", "content"]) not in [nil, ""]))
          _ -> false
        end
      else
        _ -> false
      end
    end)
  end

  defp headers(socket, length) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, {:http_header, _, :"Content-Length", _, value}} -> headers(socket, String.to_integer(value))
      {:ok, {:http_header, _, _, _, _}} -> headers(socket, length)
      {:ok, :http_eoh} -> length
    end
  end
end
