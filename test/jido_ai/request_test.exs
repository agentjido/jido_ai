defmodule JidoTest.AI.RequestTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request
  alias Jido.AI.Request.Handle
  alias Jido.AI.Runtime.Event
  alias ReqLLM.Message.ContentPart

  defmodule TestRequestTransformer do
    def transform_request(request, _state, _config, _context), do: {:ok, request}
  end

  defmodule FakeRuntimeServer do
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def last_signal(pid) do
      GenServer.call(pid, :last_signal)
    end

    def last_context(pid), do: GenServer.call(pid, :last_context)

    @impl true
    def init(opts) do
      {:ok,
       %{
         await_result: Keyword.get(opts, :await_result, {:ok, %{status: :completed, result: "ok"}}),
         await_delay_ms: Keyword.get(opts, :await_delay_ms, 0),
         request_id: Keyword.get(opts, :request_id),
         last_context: nil,
         last_signal: nil
       }}
    end

    @impl true
    def handle_call(:last_signal, _from, state) do
      {:reply, state.last_signal, state}
    end

    def handle_call(:last_context, _from, state), do: {:reply, state.last_context, state}

    def handle_call(:agent, _from, state), do: {:reply, agent(), state}

    def handle_call({:plugin_state, Jido.AI.Orchestration.Plugin}, _from, state) do
      if state.await_delay_ms > 0, do: Process.sleep(state.await_delay_ms)
      {:ok, record} = state.await_result
      {:reply, {:ok, %{state.request_id => record}}, state}
    end

    def handle_call({:signal, ref, signal, _deadline, context}, _from, state) when is_reference(ref) do
      id = signal.data.request_id
      agent = %{agent() | state: %{requests: %{id => %{id: id, status: :pending}}}}
      {:reply, {:ok, agent}, %{state | last_signal: signal, last_context: context}}
    end

    # This fixture tests the client message contract. Session execution is
    # covered by the real Agent integration tests.
    defp agent do
      %Jido.Agent{
        module: __MODULE__,
        name: "request_transport_fixture",
        schema: Zoi.object(%{}),
        state: %{requests: %{}},
        plugins: [{Jido.AI.Orchestration.Plugin, []}]
      }
    end
  end

  describe "Handle struct" do
    test "new/3 creates a pending request with timestamp" do
      handle = Handle.new("req-123", self(), "What is 2+2?")

      assert handle.id == "req-123"
      assert handle.server == self()
      assert handle.query == "What is 2+2?"
      assert handle.status == :pending
      assert handle.result == nil
      assert handle.error == nil
      assert is_integer(handle.inserted_at)
      assert handle.completed_at == nil
    end

    test "complete/2 marks request as completed with result" do
      handle = Handle.new("req-123", self(), "query")
      completed = Handle.complete(handle, "answer")

      assert completed.status == :completed
      assert completed.result == "answer"
      assert is_integer(completed.completed_at)
      assert completed.completed_at >= handle.inserted_at
    end

    test "fail/2 marks request as failed with error" do
      handle = Handle.new("req-123", self(), "query")
      failed = Handle.fail(handle, :timeout)

      assert failed.status == :failed
      assert failed.error == :timeout
      assert is_integer(failed.completed_at)
    end
  end

  describe "runtime await contracts" do
    test "request stream enumerable yields matching events until terminal event" do
      handle = Handle.new("req_stream", self(), "query")
      tag = Request.Stream.message_tag()

      first =
        Event.new(%{
          seq: 1,
          run_id: "req_stream",
          request_id: "req_stream",
          iteration: 1,
          kind: :llm_delta,
          data: %{chunk_type: :content, delta: "hello"}
        })

      terminal =
        Event.new(%{
          seq: 2,
          run_id: "req_stream",
          request_id: "req_stream",
          iteration: 1,
          kind: :request_completed,
          data: %{result: "done"}
        })

      other =
        Event.new(%{
          seq: 1,
          run_id: "other",
          request_id: "other",
          iteration: 1,
          kind: :request_completed,
          data: %{}
        })

      send(self(), {tag, other})
      send(self(), {tag, first})
      send(self(), {tag, terminal})

      assert [^first, ^terminal] =
               handle
               |> Request.Stream.events(stream_event_timeout_ms: 10)
               |> Enum.to_list()
    end

    test "create_and_send/3 emits request-scoped signal payload and returns handle" do
      server = start_runtime_server([])

      assert {:ok, handle} =
               Request.create_and_send(server, "What is 2+2?",
                 signal_type: "ai.test.query",
                 source: "/ai/test",
                 request_id: "req_123",
                 tool_context: %{actor: "user_1"},
                 tools: [:tool_override],
                 allowed_tools: ["calculator"],
                 request_transformer: TestRequestTransformer,
                 max_iterations: 3,
                 stream_timeout_ms: 4_321,
                 stream_to: {:pid, self()},
                 req_http_options: [plug: {Req.Test, []}],
                 llm_opts: [thinking: "enabled", reasoning_effort: :high],
                 extra_refs: %{slack_ts: "1234.001", custom_id: "abc"}
               )

      assert handle.id == "req_123"
      assert handle.server == server
      assert handle.status == :pending

      signal = FakeRuntimeServer.last_signal(server)
      assert %Jido.Signal{} = signal
      assert signal.type == "ai.test.query"
      assert signal.source == "/ai/test"
      assert signal.data.query == "What is 2+2?"
      assert signal.data.prompt == "What is 2+2?"
      assert signal.data.request_id == "req_123"
      resources = FakeRuntimeServer.last_context(server).jido_ai_request
      assert Map.keys(signal.data) |> Enum.sort() == [:extra_refs, :prompt, :query, :request_id]
      assert resources.tool_context == %{actor: "user_1"}
      assert resources.tools == [:tool_override]
      assert resources.allowed_tools == ["calculator"]
      assert resources.request_transformer == TestRequestTransformer
      assert resources.max_iterations == 3
      assert resources.stream_timeout_ms == 4_321
      assert resources.stream_to == {:pid, self()}
      assert resources.req_http_options == [plug: {Req.Test, []}]
      assert resources.llm_opts == [thinking: "enabled", reasoning_effort: :high]
      assert signal.data.extra_refs == %{slack_ts: "1234.001", custom_id: "abc"}
    end

    test "create_and_send/3 rejects invalid stream sink" do
      server = start_runtime_server([])

      assert {:error, {:invalid_stream_to, :bad_sink}} =
               Request.create_and_send(server, "What is 2+2?",
                 signal_type: "ai.test.query",
                 source: "/ai/test",
                 stream_to: :bad_sink
               )
    end

    test "create_and_send/3 appends uploaded file references when supported by ReqLLM" do
      server = start_runtime_server([])

      result =
        Request.create_and_send(server, "Summarize this document.",
          signal_type: "ai.test.query",
          source: "/ai/test",
          request_id: "req_file",
          file_references: [
            %{
              file_id: "file_123",
              media_type: "application/pdf",
              title: "Quarterly report"
            }
          ]
        )

      if function_exported?(ContentPart, :file_id, 3) do
        assert {:ok, handle} = result
        signal = FakeRuntimeServer.last_signal(server)

        assert [text_part, file_part] = signal.data.query
        assert signal.data.prompt == signal.data.query
        assert handle.query == signal.data.query
        assert %ContentPart{type: :text, text: "Summarize this document."} = text_part

        file_part = Map.from_struct(file_part)
        assert file_part.type == :file
        assert file_part.file_id == "file_123"
        assert file_part.media_type == "application/pdf"
        assert file_part.metadata.title == "Quarterly report"
      else
        assert {:error, {:unsupported_content_part_file_id, message}} = result
        assert message =~ "ReqLLM.Message.ContentPart.file_id/3"
        assert FakeRuntimeServer.last_signal(server) == nil
      end
    end

    test "await/2 returns successful result for completed request payload" do
      server =
        start_runtime_server(
          request_id: "req_ok",
          await_result: {:ok, %{status: :completed, result: "The answer is 4"}}
        )

      handle = Handle.new("req_ok", server, "query")
      assert {:ok, "The answer is 4"} = Request.await(handle, timeout: 100)
    end

    test "await/2 returns rejection reason for failed request payload" do
      server =
        start_runtime_server(
          request_id: "req_busy",
          await_result: {:ok, %{status: :failed, error: {:rejected, :busy, "Agent is busy"}}}
        )

      handle = Handle.new("req_busy", server, "query")
      assert {:error, {:rejected, :busy, "Agent is busy"}} = Request.await(handle, timeout: 100)
    end

    test "await/2 normalizes AgentServer timeout diagnostics to :timeout" do
      server =
        start_runtime_server(
          request_id: "req_timeout",
          await_result: {:ok, %{status: :completed, result: "too late"}},
          await_delay_ms: 50
        )

      handle = Handle.new("req_timeout", server, "query")
      assert {:error, :timeout} = Request.await(handle, timeout: 5)
    end

    test "send_and_await/3 and await/2 normalize alternate terminal payloads" do
      completed =
        start_runtime_server(
          request_id: "req_sync",
          await_result: {:ok, %{status: :completed, result: "sync"}}
        )

      assert {:ok, "sync"} =
               Request.send_and_await(completed, "query",
                 request_id: "req_sync",
                 signal_type: "ai.test.query",
                 source: "/ai/test",
                 timeout: 100
               )

      timeout = start_runtime_server(request_id: "req_status_timeout", await_result: {:ok, %{status: :timeout}})
      assert {:error, :timeout} = Request.await(Handle.new("req_status_timeout", timeout, "query"), timeout: 100)

      error = start_runtime_server(request_id: "req_error", await_result: {:ok, %{error: :bad}})
      assert {:error, :bad} = Request.await(Handle.new("req_error", error, "query"), timeout: 100)

      result = start_runtime_server(request_id: "req_result", await_result: {:ok, %{result: "fallback"}})
      assert {:ok, "fallback"} = Request.await(Handle.new("req_result", result, "query"), timeout: 100)
    end

    test "await_many/2 shuts down requests that exceed the shared timeout" do
      server =
        start_runtime_server(
          request_id: "req_too_slow",
          await_result: {:ok, %{status: :completed, result: "late"}},
          await_delay_ms: 100
        )

      assert [{:error, :timeout}] =
               Request.await_many([Handle.new("req_too_slow", server, "query")], timeout: 1)
    end

    test "await_many/2 preserves input order under concurrent completion" do
      slow_server =
        start_runtime_server(
          request_id: "req_slow",
          await_result: {:ok, %{status: :completed, result: "slow"}},
          await_delay_ms: 40
        )

      fast_server =
        start_runtime_server(
          request_id: "req_fast",
          await_result: {:ok, %{status: :completed, result: "fast"}},
          await_delay_ms: 1
        )

      requests = [
        Handle.new("req_slow", slow_server, "slow"),
        Handle.new("req_fast", fast_server, "fast")
      ]

      assert [{:ok, "slow"}, {:ok, "fast"}] = Request.await_many(requests, timeout: 150)
    end

    test "await_many/2 applies one timeout to the full request set" do
      requests =
        for index <- 1..(System.schedulers_online() + 1) do
          server =
            start_runtime_server(
              request_id: "req_total_#{index}",
              await_result: {:ok, %{status: :completed, result: index}},
              await_delay_ms: 50
            )

          Handle.new("req_total_#{index}", server, "query")
        end

      started = System.monotonic_time(:millisecond)
      results = Request.await_many(requests, timeout: 75)
      elapsed = System.monotonic_time(:millisecond) - started

      assert Enum.all?(results, &match?({:ok, _}, &1))
      assert elapsed < 110
    end
  end

  defp start_runtime_server(opts) do
    start_supervised!(%{
      id: make_ref(),
      start: {FakeRuntimeServer, :start_link, [opts]}
    })
  end
end
