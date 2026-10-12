defmodule Jido.AI.TestSupport.ReActTimeoutServer do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def url(server), do: GenServer.call(server, :url)

  @impl true
  def init(opts) do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    {:ok, tasks} = Task.Supervisor.start_link()
    server = self()
    {:ok, _} = Task.Supervisor.start_child(tasks, fn -> accept(socket, tasks, server) end)
    {:ok, %{socket: socket, port: port, owner: opts[:owner], modes: opts[:modes], wire: opts[:wire] || :chat}}
  end

  @impl true
  def handle_call(:url, _, state), do: {:reply, "http://127.0.0.1:#{state.port}/v1", state}

  def handle_call(:mode, _, %{modes: [mode | rest]} = state),
    do: {:reply, {mode, state.owner, state.wire}, %{state | modes: rest}}

  @impl true
  def terminate(_, state), do: :gen_tcp.close(state.socket)

  defp accept(listener, tasks, server) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, worker} =
          Task.Supervisor.start_child(tasks, fn ->
            receive do
              :ready -> serve(socket, server)
            end
          end)

        :ok = :gen_tcp.controlling_process(socket, worker)
        send(worker, :ready)
        accept(listener, tasks, server)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve(socket, server) do
    try do
      {:ok, {:http_request, :POST, _, _}} = :gen_tcp.recv(socket, 0, 5_000)
      length = headers(socket, 0)
      :ok = :inet.setopts(socket, packet: :raw)
      {:ok, _body} = :gen_tcp.recv(socket, length, 5_000)
      {mode, owner, wire} = GenServer.call(server, :mode)

      case mode do
        :before_response ->
          if wait(socket, owner) == :released, do: response(socket, "Done", wire)

        :mid_stream ->
          :ok = :gen_tcp.send(socket, response_headers() <> chunk("Partial ", wire))
          if wait(socket, owner) == :released, do: :gen_tcp.send(socket, chunk("Done", wire) <> ending(wire))

        :success ->
          response(socket, "Done", wire)
      end
    after
      :gen_tcp.close(socket)
    end
  end

  defp headers(socket, length) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, {:http_header, _, :"Content-Length", _, value}} -> headers(socket, String.to_integer(value))
      {:ok, {:http_header, _, _, _, _}} -> headers(socket, length)
      {:ok, :http_eoh} -> length
    end
  end

  defp wait(socket, owner) do
    :ok = :inet.setopts(socket, active: :once)
    send(owner, {:provider_waiting, self()})

    receive do
      :release ->
        :ok = :inet.setopts(socket, active: false)
        :released

      {:tcp_closed, ^socket} ->
        send(owner, {:provider_closed, self()})
        :closed

      {:tcp_error, ^socket, _} ->
        send(owner, {:provider_closed, self()})
        :closed
    after
      5_000 -> raise "Provider barrier was not released or cancelled"
    end
  end

  defp response(socket, text, wire), do: :gen_tcp.send(socket, response_headers() <> chunk(text, wire) <> ending(wire))

  defp response_headers do
    "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\n"
  end

  defp chunk(text, :responses) do
    "event: response.output_text.delta\ndata: " <> Jason.encode!(%{delta: text}) <> "\n\n"
  end

  defp chunk(text, :chat) do
    data = %{
      id: "chatcmpl_timeout_test",
      object: "chat.completion.chunk",
      model: "gpt-4o-mini",
      choices: [%{index: 0, delta: %{content: text}, finish_reason: nil}]
    }

    "data: " <> Jason.encode!(data) <> "\n\n"
  end

  defp ending(:responses) do
    data = %{
      response: %{
        id: "resp_timeout_test",
        model: "gpt-4.1-mini",
        status: "completed",
        usage: %{input_tokens: 5, output_tokens: 2, total_tokens: 7}
      }
    }

    "event: response.completed\ndata: " <> Jason.encode!(data) <> "\n\n"
  end

  defp ending(:chat) do
    data = %{
      id: "chatcmpl_timeout_test",
      object: "chat.completion.chunk",
      model: "gpt-4o-mini",
      choices: [%{index: 0, delta: %{}, finish_reason: "stop"}],
      usage: %{prompt_tokens: 5, completion_tokens: 2, total_tokens: 7}
    }

    "data: " <> Jason.encode!(data) <> "\n\ndata: [DONE]\n\n"
  end
end
