defmodule Jido.AI.Test.MockLLM do
  @moduledoc """
  Shared HTTP/SSE model server for deterministic AI tests.

  Scripts match decoded requests. The first matching remaining entry is consumed.
  This permits independent concurrent requests without depending on arrival order.
  Unmatched requests fail and remain in the report. No response is invented.

  Responses include text, objects, tool batches, embeddings, HTTP errors, raw
  provider data, named SSE events, and Anthropic messages. A `{:wait, tag, response}` barrier can hold work
  until `release/2`. A disconnected client releases the connection worker.
  This server replaces the provider only. ReqLLM, tools, Flows, and Agents run.
  """
  use GenServer

  @type response ::
          {:text, String.t() | [String.t()]}
          | {:object, map()}
          | {:tools, [map()]}
          | {:embeddings, [[number()]]}
          | {:error, pos_integer(), String.t()}
          | {:raw, map()}
          | {:sse, [{String.t(), map()} | {:wait, term()} | :disconnect]}
          | {:anthropic, {:text, String.t()} | {:tools, [map()]} | {:object, map()}}
          | {:stream, [map() | {:usage, map()} | {:wait, term()} | :disconnect]}
          | {:stream, [map() | {:usage, map()} | {:wait, term()} | :disconnect], String.t()}
          | {:stream, [map()], String.t(), map()}
          | {:wait, term(), response()}
          | {:from_request, (map() -> response())}
          | :disconnect

  @type entry :: %{required(:reply) => response(), optional(:match) => map()}

  @spec start_link(keyword()) :: GenServer.on_start()
  @doc "Starts a local HTTP model server with the supplied response script."
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Selects the tested chat wire format explicitly, independent of catalog defaults."
  def model(id \\ "gpt-4o-mini") do
    {:ok, model} = ReqLLM.model("openai:" <> id)
    %{model | extra: Map.put(model.extra || %{}, :wire, %{protocol: "openai_chat"})}
  end

  @spec options(GenServer.server(), :chat | :embedding | :anthropic) :: keyword()
  @doc "Returns ReqLLM options that point the selected protocol at this server."
  def options(server, operation \\ :chat) do
    url = GenServer.call(server, :url)
    url = if operation == :anthropic, do: String.trim_trailing(url, "/v1"), else: url

    common = [
      api_key: "local-example-key",
      base_url: url,
      req_http_options: [retry: false, receive_timeout: 5_000]
    ]

    if operation == :embedding,
      do: common,
      else: common ++ [max_retries: 0, receive_timeout: 5_000]
  end

  @spec report(GenServer.server()) :: map()
  @doc "Returns captured requests and script outcomes for assertions."
  def report(server), do: GenServer.call(server, :report)

  @spec release(GenServer.server(), term()) :: :ok | {:error, :not_waiting}
  @doc "Releases a named response barrier when the server is waiting on it."
  def release(server, tag), do: GenServer.call(server, {:release, tag})

  @impl true
  def init(opts) do
    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :http_bin,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listener)
    {:ok, supervisor} = Task.Supervisor.start_link()
    server = self()
    {:ok, acceptor} = Task.start_link(fn -> accept(listener, supervisor, server) end)

    {:ok,
     %{
       owner_monitor: if(opts[:owner], do: Process.monitor(opts[:owner])),
       listener: listener,
       supervisor: supervisor,
       acceptor: acceptor,
       port: port,
       observer: Keyword.get(opts, :observer),
       script: Keyword.fetch!(opts, :script),
       requests: [],
       unexpected: [],
       waiting: %{},
       workers: %{}
     }}
  end

  @impl true
  def handle_call(:url, _from, state), do: {:reply, "http://127.0.0.1:#{state.port}/v1", state}

  def handle_call(:report, _from, state) do
    {:reply,
     %{
       requests: Enum.reverse(state.requests),
       remaining: state.script,
       unexpected: Enum.reverse(state.unexpected),
       waiting: Map.keys(state.waiting),
       workers: Map.values(state.workers)
     }, state}
  end

  def handle_call({:request, request}, _from, state) do
    state = %{state | requests: [request | state.requests]}

    case Enum.find_index(state.script, &matches?(Map.get(&1, :match, %{}), request)) do
      nil ->
        {:reply, {:error, 500, "Unexpected mock LLM request"}, %{state | unexpected: [request | state.unexpected]}}

      index ->
        {entry, script} = List.pop_at(state.script, index)
        {:reply, entry.reply, %{state | script: script}}
    end
  end

  def handle_call({:waiting, tag, worker}, _from, state) do
    if Map.has_key?(state.waiting, tag) do
      {:reply, {:error, :duplicate_barrier}, state}
    else
      notify(state, {:mock_llm_waiting, self(), tag, worker})
      {:reply, :ok, %{state | waiting: Map.put(state.waiting, tag, worker)}}
    end
  end

  def handle_call({:release, tag}, _from, state) do
    case Map.pop(state.waiting, tag) do
      {nil, _} ->
        {:reply, {:error, :not_waiting}, state}

      {worker, waiting} ->
        send(worker, {:release, tag})
        {:reply, :ok, %{state | waiting: waiting}}
    end
  end

  def handle_call({:worker, worker}, _from, state) do
    ref = Process.monitor(worker)
    {:reply, :ok, %{state | workers: Map.put(state.workers, ref, worker)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _owner, _reason}, %{owner_monitor: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, ref, :process, worker, _reason}, state) do
    waiting = Map.reject(state.waiting, fn {_tag, pid} -> pid == worker end)
    notify(state, {:mock_llm_closed, self(), worker})
    {:noreply, %{state | workers: Map.delete(state.workers, ref), waiting: waiting}}
  end

  @impl true
  def terminate(_reason, state) do
    # Child shutdown must not replace this server's normal exit reason and
    # propagate a shutdown exit to the caller that owns the mock.
    Process.unlink(state.acceptor)
    Process.unlink(state.supervisor)
    :gen_tcp.close(state.listener)
    Process.exit(state.acceptor, :shutdown)
    if Process.alive?(state.supervisor), do: Supervisor.stop(state.supervisor)
    :ok
  end

  defp notify(%{observer: pid}, event) when is_pid(pid), do: send(pid, event)
  defp notify(_, _), do: :ok

  defp matches?(expected, actual) when is_map(expected) and is_map(actual) do
    Enum.all?(expected, fn {key, value} ->
      Map.has_key?(actual, key) and matches?(value, Map.fetch!(actual, key))
    end)
  end

  defp matches?(expected, actual), do: expected == actual

  defp accept(listener, supervisor, server) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, worker} =
          Task.Supervisor.start_child(supervisor, fn ->
            receive do
              {:socket, socket} -> serve(socket, server)
            end
          end)

        :ok = GenServer.call(server, {:worker, worker})
        :ok = :gen_tcp.controlling_process(socket, worker)
        send(worker, {:socket, socket})
        accept(listener, supervisor, server)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve(socket, server) do
    with {:ok, {:http_request, :POST, {:abs_path, path}, _}} <- :gen_tcp.recv(socket, 0, 5_000),
         {:ok, headers} <- headers(socket, %{}),
         raw_length when is_binary(raw_length) <- headers["content-length"],
         {length, ""} <- Integer.parse(raw_length),
         true <- length > 0 and length <= 2_000_000,
         :ok <- :inet.setopts(socket, packet: :raw),
         {:ok, body} <- :gen_tcp.recv(socket, length, 5_000),
         {:ok, decoded} <- Jason.decode(body) do
      request = %{path: path, headers: headers, body: decoded}
      reply = GenServer.call(server, {:request, request})
      respond(socket, server, decoded, reply)
    end
  after
    :gen_tcp.close(socket)
  end

  defp headers(socket, headers) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, :http_eoh} ->
        {:ok, headers}

      {:ok, {:http_header, _, name, _, value}} ->
        name = String.downcase(to_string(name))
        headers = Map.update(headers, name, value, &(List.wrap(&1) ++ [value]))
        headers(socket, headers)

      error ->
        error
    end
  end

  defp respond(socket, server, request, {:from_request, fun}) when is_function(fun, 1),
    do: respond(socket, server, request, fun.(request))

  defp respond(socket, server, request, {:wait, tag, reply}) do
    if wait(socket, server, tag) == :ok, do: respond(socket, server, request, reply)
  end

  defp respond(_socket, _server, _request, :disconnect), do: :ok

  defp respond(socket, _server, _request, {:error, status, message}) do
    json(socket, status, %{error: %{message: message, type: "mock_error", code: "mock_error"}})
  end

  defp respond(socket, server, _request, {:sse, events}) do
    :ok = start_stream(socket)

    result =
      Enum.reduce_while(events, :ok, fn
        :disconnect, _ ->
          {:halt, :closed}

        {:wait, tag}, _ ->
          if(wait(socket, server, tag) == :ok, do: {:cont, :ok}, else: {:halt, :closed})

        {name, body}, _ ->
          case send_chunk(socket, "event: #{name}\ndata: #{Jason.encode!(body)}\n\n") do
            :ok -> {:cont, :ok}
            _ -> {:halt, :closed}
          end
      end)

    if result == :ok, do: :gen_tcp.send(socket, "0\r\n\r\n")
  end

  defp respond(socket, server, request, {:anthropic, {:object, object}}) do
    reply =
      case request["tool_choice"] do
        %{"name" => name} -> {:tools, [%{id: "schema", name: name, arguments: object}]}
        _ -> {:text, Jason.encode!(object)}
      end

    respond(socket, server, request, {:anthropic, reply})
  end

  defp respond(socket, server, request, {:anthropic, reply}) do
    content = anthropic_content(reply)
    reason = if match?({:tools, _}, reply), do: "tool_use", else: "end_turn"

    message = %{
      id: "msg_mock",
      type: "message",
      role: "assistant",
      model: request["model"],
      content: content,
      stop_reason: reason,
      stop_sequence: nil,
      usage: %{input_tokens: 10, output_tokens: 5}
    }

    if request["stream"] do
      start =
        message
        |> Map.put(:content, [])
        |> Map.put(:stop_reason, nil)
        |> Map.put(:usage, %{input_tokens: 10, output_tokens: 0})

      blocks = Enum.with_index(content) |> Enum.flat_map(fn {block, index} -> anthropic_block(block, index) end)

      events =
        [{"message_start", %{type: "message_start", message: start}}] ++
          blocks ++
          [
            {"message_delta",
             %{type: "message_delta", delta: %{stop_reason: reason, stop_sequence: nil}, usage: %{output_tokens: 5}}},
            {"message_stop", %{type: "message_stop"}}
          ]

      respond(socket, server, request, {:sse, events})
    else
      json(socket, 200, message)
    end
  end

  defp respond(socket, _server, _request, {:raw, data}), do: json(socket, 200, data)

  defp respond(socket, _server, request, {:embeddings, vectors}) do
    data =
      Enum.with_index(vectors, fn vector, index ->
        %{object: "embedding", index: index, embedding: vector}
      end)

    json(socket, 200, %{
      object: "list",
      data: data,
      model: request["model"],
      usage: %{prompt_tokens: 5, total_tokens: 5}
    })
  end

  defp respond(
         socket,
         server,
         %{"tool_choice" => %{"function" => %{"name" => name}}} = request,
         {:object, object}
       ) do
    respond(
      socket,
      server,
      request,
      {:tools, [%{id: "mock_object", name: name, arguments: object}]}
    )
  end

  defp respond(
         socket,
         server,
         %{"input" => _, "tool_choice" => %{"type" => "function", "name" => name}} = request,
         {:object, object}
       ) do
    respond(
      socket,
      server,
      request,
      {:tools, [%{id: "mock_object", name: name, arguments: object}]}
    )
  end

  defp respond(socket, _server, %{"input" => _, "stream" => true}, _reply),
    do:
      json(socket, 501, %{
        error: %{message: "Responses streaming is not implemented by this mock"}
      })

  defp respond(socket, _server, %{"input" => _} = request, reply) do
    json(socket, 200, %{
      id: "resp_mock_" <> Integer.to_string(System.unique_integer([:positive])),
      object: "response",
      status: "completed",
      model: request["model"],
      output: response_output(reply),
      usage: %{input_tokens: 10, output_tokens: 5, total_tokens: 15}
    })
  end

  defp respond(socket, server, request, reply) do
    if request["stream"] do
      stream(socket, server, request, reply)
    else
      {message, finish} = message(reply)

      json(socket, 200, %{
        id: "mock-response",
        object: "chat.completion",
        created: 1,
        model: request["model"],
        choices: [%{index: 0, message: message, finish_reason: finish}],
        usage: usage()
      })
    end
  end

  defp response_output({:tools, calls}) do
    Enum.map(calls, fn call ->
      %{
        type: "function_call",
        id: "fc_" <> call.id,
        call_id: call.id,
        name: call.name,
        arguments: Jason.encode!(call.arguments),
        status: "completed"
      }
    end)
  end

  defp response_output(reply) do
    {message, _} = message(reply)

    [
      %{
        type: "message",
        id: "msg_mock",
        role: "assistant",
        status: "completed",
        content: [%{type: "output_text", text: message.content, annotations: []}]
      }
    ]
  end

  defp message({:text, text}),
    do: {%{role: "assistant", content: IO.iodata_to_binary(text)}, "stop"}

  defp message({:object, value}), do: message({:text, Jason.encode!(value)})

  defp message({:tools, calls}) do
    tools =
      Enum.map(calls, fn call ->
        %{
          id: call.id,
          type: "function",
          function: %{name: call.name, arguments: Jason.encode!(call.arguments)}
        }
      end)

    {%{role: "assistant", content: nil, tool_calls: tools}, "tool_calls"}
  end

  defp start_stream(socket),
    do:
      :gen_tcp.send(
        socket,
        "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\ntransfer-encoding: chunked\r\nconnection: close\r\n\r\n"
      )

  defp anthropic_content({:text, text}), do: [%{type: "text", text: text}]

  defp anthropic_content({:tools, calls}),
    do: Enum.map(calls, &%{type: "tool_use", id: &1.id, name: &1.name, input: &1.arguments})

  defp anthropic_block(%{type: "text", text: text}, index) do
    [
      {"content_block_start", %{type: "content_block_start", index: index, content_block: %{type: "text", text: ""}}},
      {"content_block_delta", %{type: "content_block_delta", index: index, delta: %{type: "text_delta", text: text}}},
      {"content_block_stop", %{type: "content_block_stop", index: index}}
    ]
  end

  defp anthropic_block(%{type: "tool_use", input: input} = block, index) do
    json = Jason.encode!(input)
    split = div(byte_size(json), 2)
    parts = [binary_part(json, 0, split), binary_part(json, split, byte_size(json) - split)]

    [{"content_block_start", %{type: "content_block_start", index: index, content_block: %{block | input: %{}}}}] ++
      Enum.map(
        parts,
        &{"content_block_delta",
         %{type: "content_block_delta", index: index, delta: %{type: "input_json_delta", partial_json: &1}}}
      ) ++
      [{"content_block_stop", %{type: "content_block_stop", index: index}}]
  end

  defp stream(socket, server, request, reply) do
    :ok = start_stream(socket)

    {deltas, finish} = deltas(reply)

    result =
      Enum.reduce_while(deltas, :ok, fn
        :disconnect, _ ->
          {:halt, :closed}

        {:wait, tag}, _ ->
          case wait(socket, server, tag) do
            :ok -> {:cont, :ok}
            _ -> {:halt, :closed}
          end

        {:usage, usage}, _ ->
          case event(
                 socket,
                 Map.put(
                   chunk(request, [%{index: 0, delta: %{}, finish_reason: nil}]),
                   :usage,
                   usage
                 )
               ) do
            :ok -> {:cont, :ok}
            _ -> {:halt, :closed}
          end

        delta, _ ->
          case event(socket, chunk(request, [%{index: 0, delta: delta, finish_reason: nil}])) do
            :ok -> {:cont, :ok}
            _ -> {:halt, :closed}
          end
      end)

    if result == :ok do
      event(socket, chunk(request, [%{index: 0, delta: %{}, finish_reason: finish}]))
      event(socket, Map.put(chunk(request, []), :usage, stream_usage(reply)))
      send_chunk(socket, "data: [DONE]\n\n")
      :gen_tcp.send(socket, "0\r\n\r\n")
    end
  end

  defp deltas({:text, text}), do: {Enum.map(List.wrap(text), &%{content: &1}), "stop"}
  defp deltas({:object, value}), do: deltas({:text, Jason.encode!(value)})
  defp deltas({:stream, deltas}), do: {deltas, "stop"}
  defp deltas({:stream, deltas, finish}), do: {deltas, finish}
  defp deltas({:stream, deltas, finish, _usage}), do: {deltas, finish}

  defp deltas({:tools, calls}) do
    chunks =
      Enum.with_index(calls)
      |> Enum.flat_map(fn {call, index} ->
        arguments = Jason.encode!(call.arguments)
        split = div(byte_size(arguments), 2)
        left = binary_part(arguments, 0, split)
        right = binary_part(arguments, split, byte_size(arguments) - split)

        [
          %{
            tool_calls: [
              %{
                index: index,
                id: call.id,
                type: "function",
                function: %{name: call.name, arguments: left}
              }
            ]
          },
          %{tool_calls: [%{index: index, function: %{arguments: right}}]}
        ]
      end)

    {chunks, "tool_calls"}
  end

  defp wait(socket, server, tag) do
    :ok = :inet.setopts(socket, active: :once)
    :ok = GenServer.call(server, {:waiting, tag, self()})

    receive do
      {:release, ^tag} -> :inet.setopts(socket, active: false)
      {:tcp_closed, ^socket} -> :closed
      {:tcp_error, ^socket, _} -> :closed
    after
      10_000 -> :timeout
    end
  end

  defp chunk(request, choices),
    do: %{
      id: "mock-response",
      object: "chat.completion.chunk",
      created: 1,
      model: request["model"],
      choices: choices
    }

  defp stream_usage({:stream, _, _, usage}), do: usage
  defp stream_usage(_), do: usage()

  defp usage, do: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
  defp event(socket, data), do: send_chunk(socket, "data: #{Jason.encode!(data)}\n\n")

  defp send_chunk(socket, payload),
    do: :gen_tcp.send(socket, [Integer.to_string(byte_size(payload), 16), "\r\n", payload, "\r\n"])

  defp json(socket, status, value) do
    body = Jason.encode!(value)

    :gen_tcp.send(socket, [
      "HTTP/1.1 #{status} Mock\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
      body
    ])
  end
end
