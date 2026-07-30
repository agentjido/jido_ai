defmodule Jido.AI.CheckpointTest do
  use Jido.AI.TestCase, async: false

  alias Jido.AI.Request

  defmodule ReadTool do
    @moduledoc false
    use Jido.Action,
      name: "read",
      description: "Reads a test path",
      schema: Zoi.object(%{path: Zoi.string()})

    def run(%{path: path}, _context), do: {:ok, %{body: "hello from #{path}"}}
  end

  defmodule CheckpointAgent do
    @moduledoc false
    use Jido.AI.Agent,
      name: "checkpoint_test_agent",
      tools: [ReadTool],
      token_secret: "test-secret-that-is-long-enough-123"
  end

  defmodule CustomCheckpointAgent do
    @moduledoc false
    use Jido.AI.Agent,
      name: "custom_checkpoint_test_agent",
      tools: [ReadTool],
      token_secret: "test-secret-that-is-long-enough-123"

    @impl true
    def checkpoint(agent, ctx) do
      with {:ok, payload} <- super(agent, ctx) do
        {:ok, Map.put(payload, :custom_checkpoint, true)}
      end
    end
  end

  setup do
    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
    end

    :ok
  end

  describe "terminal request state" do
    test "completed, failed, and cancelled requests drop their stream sinks" do
      completed =
        CheckpointAgent.new()
        |> Request.start_request("completed", "query", stream_to: {:pid, self()})
        |> Request.complete_request("completed", "answer")

      failed =
        CheckpointAgent.new()
        |> Request.start_request("failed", "query", stream_to: {:pid, self()})
        |> Request.fail_request("failed", :error)

      cancelling =
        CheckpointAgent.new()
        |> Request.start_request("cancelled", "query", stream_to: {:pid, self()})

      {:ok, cancelled, _directives} =
        CheckpointAgent.on_after_cmd(
          cancelling,
          {:ai_react_cancel, %{request_id: "cancelled", reason: :user_cancelled}},
          []
        )

      refute Map.has_key?(completed.state.requests["completed"], :stream_to)
      refute Map.has_key?(failed.state.requests["failed"], :stream_to)
      refute Map.has_key?(cancelled.state.requests["cancelled"], :stream_to)

      assert_receive {:jido_ai_request_event,
                      %Jido.AI.Runtime.Event{
                        kind: :request_cancelled,
                        request_id: "cancelled"
                      }}
    end
  end

  describe "checkpoint and restore" do
    test "an active streamed request is stored as interrupted without runtime handles" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("active", "query", stream_to: {:pid, self()})
        |> mark_react_run_active("active")

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})
      request = payload.state.requests["active"]
      strategy = payload.state.__strategy__

      assert agent.state.requests["active"].stream_to == {:pid, self()}
      assert request.status == :failed
      assert request.error == :stream_interrupted
      assert request.stream_interrupted == true
      refute Map.has_key?(request, :stream_to)
      assert strategy.status == :idle
      assert strategy.active_request_id == nil
      assert strategy.react_worker_pid == nil
      assert strategy.pending_input_server == nil
      refute Map.has_key?(payload.state, :__task_supervisor_skill__)
      assert runtime_handles(payload) == []
      assert :erlang.binary_to_term(:erlang.term_to_binary(payload), [:safe]) == payload

      {:ok, restored} = CheckpointAgent.restore(payload, %{})

      assert {:error, :stream_interrupted} = Request.get_result(restored, "active")
      assert restored.state.__strategy__.status == :idle
      assert is_pid(restored.state.__task_supervisor_skill__.supervisor)
    end

    test "consumer checkpoint overrides keep the sanitized payload" do
      agent =
        CustomCheckpointAgent.new()
        |> Request.start_request("custom", "query", stream_to: {:pid, self()})

      {:ok, payload} = CustomCheckpointAgent.checkpoint(agent, %{})

      assert payload.custom_checkpoint == true
      assert payload.state.requests["custom"].error == :stream_interrupted
      assert runtime_handles(payload) == []
    end

    test "legacy request sinks are removed during restore" do
      agent = CheckpointAgent.new()
      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})

      legacy_request = %{
        query: "query",
        status: :pending,
        error: nil,
        stream_to: {:pid, self()}
      }

      legacy = put_in(payload, [:state, :requests, "legacy"], legacy_request)
      {:ok, restored} = CheckpointAgent.restore(legacy, %{})

      request = restored.state.requests["legacy"]
      assert request.status == :failed
      assert request.error == :stream_interrupted
      assert request.stream_interrupted == true
      refute Map.has_key?(request, :stream_to)
    end
  end

  describe "request streaming" do
    test "a completed stream checkpoint restores without a process-local sink" do
      script =
        expect_react do
          user("summarize README")
          call("read", %{path: "README.md"})
          answer("README says Hello.")
        end

      pid = start_agent()

      {:ok, %{request: request, events: events}} =
        CheckpointAgent.ask_stream(
          pid,
          "summarize README",
          react_opts(script) ++ [stream_event_timeout_ms: 15_000]
        )

      assert :request_completed in Enum.map(events, & &1.kind)
      assert {:ok, "README says Hello."} = CheckpointAgent.await(request, timeout: 15_000)

      live = server_agent(pid)
      assert Request.stream_sink(live, request.id) == nil

      {:ok, payload} = CheckpointAgent.checkpoint(live, %{})
      assert runtime_handles(payload) == []
      assert :erlang.binary_to_term(:erlang.term_to_binary(payload), [:safe]) == payload

      {:ok, restored} = CheckpointAgent.restore(payload, %{})
      assert restored.state.requests[request.id].status == :completed
      assert restored.state.requests[request.id].result == "README says Hello."
    end
  end

  defp start_agent do
    suffix = System.unique_integer([:positive, :monotonic])
    registry = Module.concat(__MODULE__, :"Registry#{suffix}")
    start_supervised!({Registry, keys: :unique, name: registry}, id: {:registry, suffix})

    {:ok, pid} =
      Jido.AgentServer.start_link(
        agent: CheckpointAgent,
        id: "checkpoint-agent-#{suffix}",
        registry: registry
      )

    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    pid
  end

  defp server_agent(pid) do
    {:ok, state} = Jido.AgentServer.state(pid)
    if is_map(state) and Map.has_key?(state, :agent), do: state.agent, else: state
  end

  defp mark_react_run_active(agent, request_id) do
    update_in(agent.state.__strategy__, fn strategy ->
      Map.merge(strategy, %{
        status: :awaiting_llm,
        active_request_id: request_id,
        react_worker_pid: self(),
        react_worker_status: :running,
        pending_input_server: self()
      })
    end)
  end

  defp runtime_handles(term) when is_pid(term) or is_port(term) or is_reference(term), do: [term]

  defp runtime_handles(term) when is_function(term) do
    if Function.info(term, :type) == {:type, :external}, do: [], else: [term]
  end

  defp runtime_handles(%_{} = term), do: term |> Map.from_struct() |> runtime_handles()

  defp runtime_handles(term) when is_map(term) do
    Enum.flat_map(term, fn {key, value} -> runtime_handles(key) ++ runtime_handles(value) end)
  end

  defp runtime_handles([head | tail]), do: runtime_handles(head) ++ runtime_handles(tail)
  defp runtime_handles(term) when is_tuple(term), do: term |> Tuple.to_list() |> runtime_handles()
  defp runtime_handles(_term), do: []
end
