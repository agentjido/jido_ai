defmodule JidoAI.Examples.MockLLMTest do
  use ExUnit.Case, async: true
  @moduletag :example

  alias JidoAI.Examples.MockLLM
  @model MockLLM.model()

  defp server(script), do: start_supervised!({MockLLM, script: script, observer: self()})

  defp done!(server) do
    assert %{remaining: [], unexpected: [], waiting: []} = MockLLM.report(server)
  end

  defp tool do
    ReqLLM.Tool.new!(
      name: "multiply",
      description: "Multiply two numbers",
      parameter_schema: [a: [type: :integer, required: true], b: [type: :integer, required: true]],
      callback: fn _ -> raise "ReqLLM must not execute this tool" end
    )
  end

  for streaming? <- [false, true] do
    test "Anthropic text, fragmented tools and objects decode with streaming #{streaming?}" do
      server =
        server([
          %{reply: {:anthropic, {:text, "Ready"}}},
          %{reply: {:anthropic, {:tools, [%{id: "multiply_one", name: "multiply", arguments: %{a: 2, b: 3}}]}}},
          %{reply: {:anthropic, {:object, %{answer: "Object"}}}}
        ])

      model = "anthropic:claude-sonnet-4-5"
      options = MockLLM.options(server, :anthropic)

      for {operation, opts} <- [{:text, options}, {:tools, Keyword.put(options, :tools, [tool()])}, {:object, options}] do
        response = anthropic_response(unquote(streaming?), operation, model, opts)

        assert response.usage.total_tokens == 15

        case operation do
          :text ->
            assert ReqLLM.Response.text(response) == "Ready"

          :object ->
            assert response.object == %{"answer" => "Object"}

          :tools ->
            assert [%{id: "multiply_one", function: %{name: "multiply", arguments: arguments}}] =
                     ReqLLM.Response.tool_calls(response)

            assert Jason.decode!(arguments) == %{"a" => 2, "b" => 3}
        end
      end

      assert Enum.all?(MockLLM.report(server).requests, &(&1.path == "/v1/messages"))
      done!(server)
    end
  end

  defp anthropic_response(streaming?, operation, model, opts) do
    case {streaming?, operation} do
      {true, :object} ->
        assert {:ok, stream} = ReqLLM.stream_object(model, "Extract", Zoi.object(%{answer: Zoi.string()}), opts)
        assert {:ok, response} = ReqLLM.StreamResponse.process_stream(stream)
        response

      {true, _} ->
        assert {:ok, stream} = ReqLLM.stream_text(model, "Work", opts)
        assert {:ok, response} = ReqLLM.StreamResponse.process_stream(stream)
        response

      {false, :object} ->
        assert {:ok, response} =
                 ReqLLM.generate_object(model, "Extract", Zoi.object(%{answer: Zoi.string()}), opts)

        response

      {false, _} ->
        assert {:ok, response} = ReqLLM.generate_text(model, "Work", opts)
        response
    end
  end

  test "normal mock shutdown keeps its linked caller alive and closes owned resources" do
    for _ <- 1..20 do
      {caller, monitor} =
        spawn_monitor(fn ->
          {:ok, mock} = MockLLM.start_link(script: [])
          state = :sys.get_state(mock)

          monitors =
            for pid <- [mock, state.acceptor, state.supervisor], do: {pid, Process.monitor(pid)}

          assert :ok = GenServer.stop(mock, :normal)

          for {pid, ref} <- monitors do
            assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
          end
        end)

      assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 2_000
    end
  end

  test "request-based replies use decoded wire input for text and streamed objects" do
    server =
      server([
        %{
          reply:
            {:from_request,
             fn body ->
               {:text, "Received " <> List.last(body["messages"])["content"]}
             end}
        },
        %{
          reply:
            {:from_request,
             fn body ->
               {:object, %{received: List.last(body["messages"])["content"], streamed: body["stream"]}}
             end}
        }
      ])

    assert {:ok, response} = ReqLLM.generate_text(@model, "dynamic text", MockLLM.options(server))
    assert ReqLLM.Response.text(response) == "Received dynamic text"
    assert {:ok, stream} = ReqLLM.stream_text(@model, "dynamic object", MockLLM.options(server))
    assert {:ok, response} = ReqLLM.StreamResponse.process_stream(stream)
    assert response.object == %{"received" => "dynamic object", "streamed" => true}
    assert response.usage.total_tokens == 15
    done!(server)
  end

  test "object scripts answer a forced structured output tool through the provider protocol" do
    server = server(List.duplicate(%{reply: {:object, %{answer: "ok"}}}, 2))

    assert {:ok, response} =
             ReqLLM.generate_object(
               MockLLM.model("gpt-4o"),
               "Answer",
               Zoi.object(%{answer: Zoi.string()}),
               MockLLM.options(server)
             )

    assert response.object == %{"answer" => "ok"}
    assert response.usage.total_tokens == 15

    assert {:ok, stream} =
             ReqLLM.stream_object(
               MockLLM.model("gpt-4o"),
               "Answer",
               Zoi.object(%{answer: Zoi.string()}),
               MockLLM.options(server)
             )

    assert {:ok, streamed} = ReqLLM.StreamResponse.process_stream(stream)
    assert streamed.object == %{"answer" => "ok"} and streamed.usage.total_tokens == 15

    assert Enum.all?(
             MockLLM.report(server).requests,
             &match?(
               %{body: %{"tool_choice" => %{"function" => %{"name" => "structured_output"}}}},
               &1
             )
           )

    done!(server)
  end

  test "records actual provider input and returns text and usage" do
    server =
      server([
        %{
          match: %{path: "/v1/chat/completions", body: %{"model" => "gpt-4o-mini"}},
          reply: {:text, "Ready"}
        }
      ])

    assert {:ok, response} = ReqLLM.generate_text(@model, "Hello", MockLLM.options(server))
    assert ReqLLM.Response.text(response) == "Ready"
    assert ReqLLM.Response.usage(response).total_tokens == 15
    assert [%{body: %{"messages" => messages}}] = MockLLM.report(server).requests
    assert List.last(messages) == %{"role" => "user", "content" => "Hello"}
    done!(server)
  end

  test "returns a tool batch with stable IDs and decoded arguments" do
    calls = [
      %{id: "a", name: "multiply", arguments: %{a: 2, b: 3}},
      %{id: "b", name: "multiply", arguments: %{a: 4, b: 5}}
    ]

    server = server([%{reply: {:tools, calls}}])

    assert {:ok, response} =
             ReqLLM.generate_text(
               @model,
               "Calculate",
               Keyword.put(MockLLM.options(server), :tools, [tool()])
             )

    actual = Enum.map(ReqLLM.Response.tool_calls(response), &ReqLLM.ToolCall.to_map/1)
    assert Enum.map(actual, & &1.id) == ["a", "b"]
    assert Enum.map(actual, & &1.arguments) == [%{"a" => 2, "b" => 3}, %{"a" => 4, "b" => 5}]

    assert [%{body: %{"tools" => [%{"function" => %{"name" => "multiply"}}]}}] =
             MockLLM.report(server).requests

    done!(server)
  end

  test "structured generation uses real provider schema encoding and validation" do
    server = server([%{reply: {:object, %{answer: "ok"}}}])
    schema = Zoi.object(%{answer: Zoi.string()})

    assert {:ok, response} =
             ReqLLM.generate_object(@model, "Extract", schema, MockLLM.options(server))

    assert ReqLLM.Response.object(response) in [%{answer: "ok"}, %{"answer" => "ok"}]

    assert [%{body: %{"response_format" => %{"type" => "json_schema"}}}] =
             MockLLM.report(server).requests

    done!(server)
  end

  test "streams text chunks and usage through actual SSE decoding" do
    server = server([%{reply: {:text, ["Hel", "lo"]}}])
    assert {:ok, stream} = ReqLLM.stream_text(@model, "Hello", MockLLM.options(server))
    assert ReqLLM.StreamResponse.text(stream) == "Hello"
    assert ReqLLM.StreamResponse.usage(stream).total_tokens == 15
    done!(server)
  end

  test "streams fragmented tool arguments through actual SSE decoding" do
    server =
      server([%{reply: {:tools, [%{id: "call-1", name: "multiply", arguments: %{a: 6, b: 7}}]}}])

    assert {:ok, stream} =
             ReqLLM.stream_text(
               @model,
               "Calculate",
               Keyword.put(MockLLM.options(server), :tools, [tool()])
             )

    assert {:ok, response} = ReqLLM.StreamResponse.process_stream(stream)

    assert [%{id: "call-1", name: "multiply", arguments: %{"a" => 6, "b" => 7}}] =
             Enum.map(ReqLLM.Response.tool_calls(response), &ReqLLM.ToolCall.to_map/1)

    done!(server)
  end

  test "returns embeddings with input order and usage" do
    server =
      server([
        %{match: %{path: "/v1/embeddings"}, reply: {:embeddings, [[0.1, 0.2], [0.3, 0.4]]}}
      ])

    assert {:ok, result} =
             ReqLLM.embed(
               "openai:text-embedding-3-small",
               ["first", "second"],
               Keyword.put(MockLLM.options(server, :embedding), :return_usage, true)
             )

    assert result.embedding == [[0.1, 0.2], [0.3, 0.4]]
    assert [%{body: %{"input" => ["first", "second"]}}] = MockLLM.report(server).requests
    done!(server)
  end

  test "errors and exhausted scripts cannot become invented successful answers" do
    server = server([%{reply: {:error, 429, "Capacity limit"}}])
    assert {:error, _} = ReqLLM.generate_text(@model, "First", MockLLM.options(server))
    done!(server)
    assert {:error, _} = ReqLLM.generate_text(@model, "Unscripted", MockLLM.options(server))
    assert length(MockLLM.report(server).unexpected) == 1
    assert length(MockLLM.report(server).requests) == 2
  end

  test "a held request does not block independent concurrent model calls" do
    server =
      server([
        %{match: %{body: %{"model" => "gpt-4o-mini"}}, reply: {:wait, :first, {:text, "first"}}},
        %{match: %{body: %{"model" => "gpt-4o"}}, reply: {:text, "second"}}
      ])

    first = Task.async(fn -> ReqLLM.generate_text(@model, "First", MockLLM.options(server)) end)
    assert_receive {:mock_llm_waiting, ^server, :first, _}, 5_000

    assert {:ok, second} =
             ReqLLM.generate_text(MockLLM.model("gpt-4o"), "Second", MockLLM.options(server))

    assert ReqLLM.Response.text(second) == "second"
    :ok = MockLLM.release(server, :first)
    assert {:ok, first_response} = Task.await(first)
    assert ReqLLM.Response.text(first_response) == "first"
    done!(server)
  end

  test "a disconnected client releases a held connection worker" do
    server = server([%{reply: {:wait, :cancel, {:text, "late"}}}])
    url = MockLLM.options(server)[:base_url] |> URI.parse()
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", url.port, [:binary, active: false])
    body = Jason.encode!(%{model: "gpt-4o-mini", messages: []})

    :ok =
      :gen_tcp.send(
        socket,
        "POST /v1/chat/completions HTTP/1.1\r\nhost: localhost\r\ncontent-length: #{byte_size(body)}\r\n\r\n" <>
          body
      )

    assert_receive {:mock_llm_waiting, ^server, :cancel, worker}, 1_000
    monitor = Process.monitor(worker)
    :gen_tcp.close(socket)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    assert_receive {:mock_llm_closed, ^server, ^worker}, 1_000
    done!(server)
    assert MockLLM.report(server).workers == []
  end

  test "SSE barriers expose partial output before the stream finishes" do
    server =
      server([%{reply: {:stream, [%{content: "first"}, {:wait, :middle}, %{content: "second"}]}}])

    owner = self()

    task =
      Task.async(fn ->
        {:ok, stream} = ReqLLM.stream_text(@model, "Stream", MockLLM.options(server))

        stream
        |> ReqLLM.StreamResponse.tokens()
        |> Enum.map(fn text ->
          send(owner, {:token, text})
          text
        end)
      end)

    assert_receive {:mock_llm_waiting, ^server, :middle, _}, 5_000
    assert_receive {:token, "first"}, 1_000
    :ok = MockLLM.release(server, :middle)
    assert Task.await(task) == ["first", "second"]
    done!(server)
  end

  test "strict object validation rejects provider data that violates the requested schema" do
    server = server([%{reply: {:object, %{answer: ""}}}])
    opts = Keyword.put(MockLLM.options(server), :output_validation, :strict)

    assert {:error, %{tag: :structured_output_validation_failed}} =
             ReqLLM.generate_object(
               @model,
               "Extract",
               Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)}),
               opts
             )

    done!(server)
  end

  test "raw malformed provider envelopes reach the real decoder" do
    server = server([%{reply: {:raw, %{choices: "invalid"}}}])
    # ReqLLM 1.22 raises for this shape. The Agent example proves Exec contains it.
    assert_raise Protocol.UndefinedError, fn ->
      ReqLLM.generate_text(@model, "Hello", MockLLM.options(server))
    end

    done!(server)
  end

  test "a receive timeout closes a held request without consuming a later response" do
    server = server([%{reply: {:wait, :timeout, {:text, "late"}}}])

    task =
      Task.async(fn ->
        opts = MockLLM.options(server) |> Keyword.put(:receive_timeout, 100)
        ReqLLM.generate_text(@model, "Wait", opts)
      end)

    assert_receive {:mock_llm_waiting, ^server, :timeout, worker}, 5_000
    monitor = Process.monitor(worker)
    assert {:error, _} = Task.await(task, 5_000)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    assert_receive {:mock_llm_closed, ^server, ^worker}, 1_000
    done!(server)
  end
end
