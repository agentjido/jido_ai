defmodule Jido.AI.CheckpointTest do
  @moduledoc """
  Regression coverage for agentjido/jido_ai#327.

  Request stream sinks (`stream_to: {:pid, pid}`) used to be written into
  durable checkpoints. A pid encodes its node atom, and
  `:erlang.binary_to_term/2` with `[:safe]` refuses to create that atom in a VM
  that has never seen it — so a checkpoint became permanently undecodable after
  a distribution config change, surfacing as `{:error, :invalid_term}`.
  """

  use Jido.AI.TestCase, async: false

  alias Jido.AI.Checkpoint
  alias Jido.AI.Request

  doctest Jido.AI.Checkpoint
  doctest Jido.AI.Request, only: [sanitize_requests: 2]

  @gate_owner :jido_ai_checkpoint_test_gate_owner

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defmodule ReadTool do
    @moduledoc false
    use Jido.Action,
      name: "read",
      description: "Reads a test path",
      schema: Zoi.object(%{path: Zoi.string()})

    def run(%{path: path}, _context), do: {:ok, %{body: "hello from #{path}"}}
  end

  defmodule GateTool do
    @moduledoc false
    use Jido.Action,
      name: "gate",
      description: "Blocks until the test releases it",
      schema: Zoi.object(%{token: Zoi.string()})

    # Suspends the ReAct run inside tool execution so the test can take a
    # checkpoint while the request is genuinely still in flight. The owner is
    # reached by registered name rather than :tool_context, so no test pid is
    # smuggled into agent state.
    def run(%{token: token}, _context) do
      send(Jido.AI.CheckpointTest.gate_owner(), {:gate_entered, token, self()})

      receive do
        {:gate_release, ^token} -> {:ok, %{released: true}}
      after
        10_000 -> {:error, :gate_timeout}
      end
    end
  end

  defmodule CheckpointAgent do
    @moduledoc false
    use Jido.AI.Agent,
      name: "checkpoint_test_agent",
      tools: [ReadTool, GateTool],
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

  @doc false
  def gate_owner, do: @gate_owner

  setup do
    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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

  defp request_record(payload, request_id), do: get_in(payload, [:state, :requests, request_id])

  defp mark_react_run_active(agent, request_id) do
    update_in(agent.state.__strategy__, fn strategy ->
      Map.merge(strategy, %{
        status: :awaiting_llm,
        active_request_id: request_id,
        react_worker_pid: self(),
        react_worker_status: :running,
        pending_input_server: self(),
        run_tool_context: %{request: request_id},
        run_req_http_options: [receive_timeout: 1_000],
        run_llm_opts: [temperature: 0.1]
      })
    end)
  end

  # ---------------------------------------------------------------------------
  # Acceptance criterion 1 - terminal states drop the stream sink
  # ---------------------------------------------------------------------------

  describe "terminal request states drop the stream sink" do
    test "complete_request/4 removes stream_to" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_done", "query", stream_to: {:pid, self()})

      assert agent.state.requests["req_done"].stream_to == {:pid, self()}

      agent = Request.complete_request(agent, "req_done", "answer")

      assert agent.state.requests["req_done"].status == :completed
      refute Map.has_key?(agent.state.requests["req_done"], :stream_to)
    end

    test "fail_request/3 removes stream_to" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_failed", "query", stream_to: {:pid, self()})
        |> Request.fail_request("req_failed", {:failed, :boom, nil})

      assert agent.state.requests["req_failed"].status == :failed
      refute Map.has_key?(agent.state.requests["req_failed"], :stream_to)
    end

    test "cancellation removes stream_to and emits a terminal event to the sink" do
      tag = Request.Stream.message_tag()

      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_cancel", "query", stream_to: {:pid, self()})

      {:ok, agent, _directives} =
        CheckpointAgent.on_after_cmd(
          agent,
          {:ai_react_cancel, %{request_id: "req_cancel", reason: :user_cancelled}},
          []
        )

      assert agent.state.requests["req_cancel"].status == :failed
      assert agent.state.requests["req_cancel"].error == {:cancelled, :user_cancelled}
      refute Map.has_key?(agent.state.requests["req_cancel"], :stream_to)

      # The consumer's enumerable halts on this event instead of waiting for a
      # worker acknowledgement that a cancelled run may never send.
      assert_receive {^tag,
                      %Jido.AI.Runtime.Event{
                        kind: :request_cancelled,
                        request_id: "req_cancel",
                        data: %{reason: :user_cancelled}
                      }}

      assert Request.Stream.terminal_kind?(:request_cancelled)
    end

    test "request-error rejection removes stream_to after notifying the sink" do
      tag = Request.Stream.message_tag()

      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_busy", "query", stream_to: {:pid, self()})

      {:ok, agent, _action} =
        CheckpointAgent.on_before_cmd(
          agent,
          {:ai_react_request_error, %{request_id: "req_busy", reason: :busy, message: "busy"}}
        )

      assert agent.state.requests["req_busy"].status == :failed
      refute Map.has_key?(agent.state.requests["req_busy"], :stream_to)
      assert_receive {^tag, %Jido.AI.Runtime.Event{kind: :request_failed, request_id: "req_busy"}}
    end

    test "failing an already-completed request leaves the completed record intact" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_done", "query", stream_to: {:pid, self()})
        |> Request.complete_request("req_done", "answer")
        |> Request.fail_request("req_done", {:failed, :late, nil})

      assert agent.state.requests["req_done"].status == :completed
      assert agent.state.requests["req_done"].result == "answer"
      refute Map.has_key?(agent.state.requests["req_done"], :stream_to)
    end
  end

  # ---------------------------------------------------------------------------
  # Handle scanning - the invariant the other tests rely on
  # ---------------------------------------------------------------------------

  describe "runtime_handles/1" do
    test "reports pids, ports, references, and anonymous functions with their paths" do
      port = Port.open({:spawn, "cat"}, [:binary])
      on_exit(fn -> if Port.info(port), do: Port.close(port) end)

      term = %{
        sink: {:pid, self()},
        nested: [%{ref: make_ref()}],
        port: port,
        fun: fn -> :anonymous end
      }

      handles = Checkpoint.runtime_handles(term)

      assert {[:sink, {:elem, 1}], :pid} in handles
      assert {[:nested, {:at, 0}, :ref], :reference} in handles
      assert {[:port], :port} in handles
      assert {[:fun], :function} in handles
      assert length(handles) == 4
    end

    test "ignores plain data and external function captures" do
      # &Mod.fun/arity encodes as a module/function/arity triple, which [:safe]
      # accepts; only anonymous funs are rejected outright.
      term = %{numbers: [1, 2], text: "ok", atoms: {:a, :b}, capture: &Enum.map/2}

      assert Checkpoint.runtime_handles(term) == []
    end

    test "descends into structs" do
      event =
        Jido.AI.Runtime.Event.new(%{
          seq: 0,
          run_id: "run",
          request_id: "req",
          iteration: 0,
          kind: :request_completed,
          data: %{pid: self()}
        })

      assert [{[Jido.AI.Runtime.Event, :data, :pid], :pid}] = Checkpoint.runtime_handles(event)
    end

    test "reports runtime handles used as map keys" do
      pid = self()
      ref = make_ref()
      fun = fn -> :anonymous end

      handles = Checkpoint.runtime_handles(%{pid => :pid, ref => :ref, fun => :fun})

      assert Enum.any?(handles, fn
               {[{:key, ^pid}], :pid} -> true
               _other -> false
             end)

      assert Enum.any?(handles, fn
               {[{:key, ^ref}], :reference} -> true
               _other -> false
             end)

      assert Enum.any?(handles, fn
               {[{:key, ^fun}], :function} -> true
               _other -> false
             end)
    end

    test "descends into improper list tails" do
      ref = make_ref()

      assert [
               {[{:at, 0}], :pid},
               {[{:tail, 1}], :reference}
             ] = Checkpoint.runtime_handles([self() | ref])
    end
  end

  # ---------------------------------------------------------------------------
  # Acceptance criterion 2 - payloads are pid-free, active requests included
  # ---------------------------------------------------------------------------

  describe "checkpoint payloads" do
    test "an active streamed request is failed in the payload and flagged interrupted" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_active", "query", stream_to: {:pid, self()})

      # The live agent keeps its sink; only the payload is sanitized.
      assert agent.state.requests["req_active"].stream_to == {:pid, self()}

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})
      record = request_record(payload, "req_active")

      assert record.status == :failed
      assert record.error == :stream_interrupted
      refute Map.has_key?(record, :stream_to)
      assert record.stream_interrupted == true
      assert Checkpoint.runtime_handles(payload) == []
      assert agent.state.requests["req_active"].stream_to == {:pid, self()}
      assert agent.state.requests["req_active"].status == :pending
    end

    test "a completed streamed request contributes no pid and is not flagged" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_done", "query", stream_to: {:pid, self()})
        |> Request.complete_request("req_done", "answer")

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})
      record = request_record(payload, "req_done")

      assert record.status == :completed
      refute Map.has_key?(record, :stream_to)
      refute Map.has_key?(record, :stream_interrupted)
      assert Checkpoint.runtime_handles(payload) == []
    end

    test "strategy worker handles and task supervisor are stripped" do
      agent = CheckpointAgent.new()

      agent =
        put_in(agent.state.__strategy__, %{
          agent.state.__strategy__
          | react_worker_pid: self(),
            react_worker_status: :running,
            pending_input_server: self(),
            pending_worker_start: %{context: %{state: %{sink: self()}}}
        })

      assert Checkpoint.runtime_handles(agent.state) != []

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})
      strategy = payload.state.__strategy__

      assert strategy.react_worker_pid == nil
      assert strategy.react_worker_status == :missing
      assert strategy.pending_input_server == nil
      assert strategy.pending_worker_start == nil
      assert strategy.status == :idle
      assert strategy.active_request_id == nil
      refute Map.has_key?(payload.state, :__task_supervisor_skill__)
      assert Checkpoint.runtime_handles(payload) == []
    end

    test "consumer checkpoint overrides compose with sanitization" do
      agent =
        CustomCheckpointAgent.new()
        |> Request.start_request("req_custom", "query", stream_to: {:pid, self()})

      {:ok, payload} = CustomCheckpointAgent.checkpoint(agent, %{})

      assert payload.custom_checkpoint == true
      assert request_record(payload, "req_custom").error == :stream_interrupted
      assert Checkpoint.runtime_handles(payload) == []
    end

    test "the scan is not vacuous - a sink left in a payload is detected" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_leak", "query", stream_to: {:pid, self()})

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})

      leaky = put_in(payload, [:state, :requests, "req_leak", :stream_to], {:pid, self()})

      assert [{path, :pid}] = Checkpoint.runtime_handles(leaky)
      assert path == [:state, :requests, "req_leak", :stream_to, {:elem, 1}]
    end
  end

  # ---------------------------------------------------------------------------
  # Acceptance criterion 3 - decodable in a fresh VM with [:safe]
  # ---------------------------------------------------------------------------

  describe "external term encoding" do
    test "a pid from a vanished node is exactly what [:safe] rejects" do
      # Reproduces the reported failure without a second VM: hand-build the
      # external representation of a pid living on a node this VM has never
      # seen. [:safe] refuses to create the node atom, which is how a checkpoint
      # written before a distribution change becomes {:error, :invalid_term}.
      # The node name must be unique per run - once the atom exists, [:safe]
      # would happily decode the same bytes.
      node_name = "gone#{System.unique_integer([:positive])}@nowhere"
      size = byte_size(node_name)
      encoded_pid = <<131, 88, 119, size, node_name::binary, 1::32, 0::32, 0::32>>

      assert_raise ArgumentError, fn -> :erlang.binary_to_term(encoded_pid, [:safe]) end

      # Same bytes decode once the atom exists, confirming the node atom - not
      # the pid itself - is what makes the payload unreadable.
      assert is_pid(:erlang.binary_to_term(encoded_pid))
      assert is_pid(:erlang.binary_to_term(encoded_pid, [:safe]))
    end

    test "tool callbacks use durable MFA tuples and stay in the payload" do
      agent = CheckpointAgent.new()
      tools = agent.state.__strategy__.config.reqllm_tools

      assert tools != []
      assert Enum.all?(tools, &(&1.callback == {ReqLLM.Tool, :new}))
      refute Enum.any?(Checkpoint.runtime_handles(agent.state), fn {_path, kind} -> kind == :function end)

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})

      assert payload.state.__strategy__.config.reqllm_tools == tools
      assert Checkpoint.runtime_handles(payload) == []
    end

    test "a checkpoint from a streamed request round-trips through [:safe]" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_active", "query", stream_to: {:pid, self()})
        |> Request.start_request("req_done", "query", stream_to: {:pid, self()})
        |> Request.complete_request("req_done", "answer")

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})

      # No pid means no foreign node atom, and no anonymous fun means nothing
      # [:safe] rejects unconditionally - together these are what make the
      # payload readable in a VM that never saw the writing node.
      assert Checkpoint.runtime_handles(payload) == []

      decoded = :erlang.binary_to_term(:erlang.term_to_binary(payload), [:safe])

      assert decoded == payload
      assert decoded.state.requests["req_active"].stream_interrupted == true
      assert decoded.state.requests["req_active"].status == :failed
      assert decoded.state.requests["req_active"].error == :stream_interrupted
      assert decoded.state.requests["req_done"].status == :completed
    end
  end

  # ---------------------------------------------------------------------------
  # Acceptance criterion 4 - restore behaviour is deterministic
  # ---------------------------------------------------------------------------

  describe "restore" do
    test "an interrupted streamed request fails, becomes unstreamable, and releases the strategy" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_active", "query", stream_to: {:pid, self()})
        |> mark_react_run_active("req_active")

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})
      {:ok, restored} = CheckpointAgent.restore(payload, %{})

      record = restored.state.requests["req_active"]

      assert record.status == :failed
      assert record.error == :stream_interrupted
      refute Map.has_key?(record, :stream_to)
      assert Checkpoint.interrupted_request?(record)
      assert Request.stream_sink(restored, "req_active") == nil
      assert restored.state.__strategy__.status == :idle
      assert restored.state.__strategy__.active_request_id == nil
      assert restored.state.__strategy__.react_worker_pid == nil
      assert restored.state.__strategy__.react_worker_status == :missing

      # Nothing is delivered to the original consumer after a thaw.
      assert Request.Stream.send_event(Request.stream_sink(restored, "req_active"), %{
               seq: 0,
               run_id: "req_active",
               request_id: "req_active",
               iteration: 0,
               kind: :request_completed,
               data: %{}
             }) == :ok

      refute_receive {_tag, %Jido.AI.Runtime.Event{}}, 50

      {next_agent, directives} =
        CheckpointAgent.cmd(
          restored,
          {:ai_react_start, %{query: "new query", request_id: "req_next"}}
        )

      refute Enum.any?(directives, &is_struct(&1, Jido.AI.Directive.EmitRequestError))
      assert next_agent.state.__strategy__.active_request_id == "req_next"

      pending_input_server = next_agent.state.__strategy__.pending_input_server

      if is_pid(pending_input_server) do
        Jido.AI.PendingInputServer.stop(pending_input_server)
      end
    end

    test "a completed request restores without an interrupted flag" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_done", "query", stream_to: {:pid, self()})
        |> Request.complete_request("req_done", "answer")

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})
      {:ok, restored} = CheckpointAgent.restore(payload, %{})

      record = restored.state.requests["req_done"]

      assert record.status == :completed
      assert record.result == "answer"
      refute Checkpoint.interrupted_request?(record)
    end

    test "a legacy payload that still carries a sink is scrubbed on restore" do
      # Checkpoints written before this fix may already be on disk. If they are
      # decodable at all, restore must not hand back a stale pid.
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_legacy", "query", stream_to: {:pid, self()})

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})

      legacy =
        payload
        |> put_in([:state, :requests, "req_legacy", :stream_to], {:pid, self()})
        |> put_in([:state, :requests, "req_legacy", :status], :pending)
        |> put_in([:state, :requests, "req_legacy", :error], nil)
        |> update_in([:state, :requests, "req_legacy"], &Map.delete(&1, :stream_interrupted))

      {:ok, restored} = CheckpointAgent.restore(legacy, %{})

      assert Request.stream_sink(restored, "req_legacy") == nil
      assert Checkpoint.interrupted_request?(restored.state.requests["req_legacy"])
      assert restored.state.requests["req_legacy"].status == :failed
      assert restored.state.requests["req_legacy"].error == :stream_interrupted
    end

    test "await/2 on an interrupted request returns its explicit failure" do
      agent =
        CheckpointAgent.new()
        |> Request.start_request("req_interrupted", "query", stream_to: {:pid, self()})

      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})

      suffix = System.unique_integer([:positive, :monotonic])
      {:ok, restored} = CheckpointAgent.restore(%{payload | id: "interrupted-agent-#{suffix}"}, %{})

      registry = Module.concat(__MODULE__, :"InterruptedRegistry#{suffix}")
      start_supervised!({Registry, keys: :unique, name: registry}, id: {:interrupted_registry, suffix})

      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: restored,
          agent_module: CheckpointAgent,
          registry: registry
        )

      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

      # The run backing this request died with the previous VM, so awaiting it
      # resolves immediately with the durable interruption error.
      handle = Request.Handle.new("req_interrupted", pid, "query")

      assert {:error, :stream_interrupted} = Request.await(handle, timeout: 5_000)
    end

    test "durable tool callbacks remain compatible and missing legacy tools are rebuilt" do
      agent = CheckpointAgent.new()
      {:ok, payload} = CheckpointAgent.checkpoint(agent, %{})

      payload_tools = payload.state.__strategy__.config.reqllm_tools
      assert payload_tools != []
      assert Enum.all?(payload_tools, &(&1.callback == {ReqLLM.Tool, :new}))

      {:ok, restored} = CheckpointAgent.restore(payload, %{})
      config = restored.state.__strategy__.config

      assert length(config.reqllm_tools) == length(config.tools)
      assert Enum.all?(config.reqllm_tools, &is_struct(&1, ReqLLM.Tool))
      assert Enum.sort(Enum.map(config.reqllm_tools, & &1.name)) == ["gate", "read"]

      legacy_payload = update_in(payload.state.__strategy__.config, &Map.delete(&1, :reqllm_tools))
      {:ok, restored_legacy} = CheckpointAgent.restore(legacy_payload, %{})
      assert Enum.sort(Enum.map(restored_legacy.state.__strategy__.config.reqllm_tools, & &1.name)) == ["gate", "read"]

      # A fresh, live task supervisor replaces the one dropped at checkpoint.
      assert is_pid(restored.state.__task_supervisor_skill__.supervisor)
      assert Process.alive?(restored.state.__task_supervisor_skill__.supervisor)
      assert restored.state.__strategy__.react_worker_pid == nil
      assert restored.state.__strategy__.react_worker_status == :missing
    end
  end

  # ---------------------------------------------------------------------------
  # Acceptance criterion 5 - streaming plus checkpoint/restore, end to end
  # ---------------------------------------------------------------------------

  describe "request streaming with checkpoint and restore" do
    test "a checkpoint taken mid-stream is pid-free while the request is in flight" do
      Process.register(self(), @gate_owner)
      on_exit(fn -> if Process.whereis(@gate_owner) == self(), do: Process.unregister(@gate_owner) end)

      token = "gate-#{System.unique_integer([:positive])}"

      script =
        expect_react do
          user("run the gate")
          call("gate", %{token: token})
          answer("gate released")
        end

      pid = start_agent()

      {:ok, %{request: request, events: events}} =
        CheckpointAgent.ask_stream(
          pid,
          "run the gate",
          react_opts(script) ++ [stream_event_timeout_ms: 15_000]
        )

      # The run is now suspended inside GateTool, so the request is genuinely
      # active with a live sink recorded in agent state.
      assert_receive {:gate_entered, ^token, tool_pid}, 10_000

      live = server_agent(pid)
      assert Request.stream_sink(live, request.id) == {:pid, self()}
      assert live.state.requests[request.id].status == :pending
      assert is_pid(live.state.__strategy__.react_worker_pid)

      {:ok, payload} = CheckpointAgent.checkpoint(live, %{})
      record = request_record(payload, request.id)

      assert record.status == :failed
      assert record.error == :stream_interrupted
      refute Map.has_key?(record, :stream_to)
      assert record.stream_interrupted == true
      assert payload.state.__strategy__.status == :idle
      assert payload.state.__strategy__.active_request_id == nil
      assert Checkpoint.runtime_handles(payload) == []
      assert :erlang.binary_to_term(:erlang.term_to_binary(payload), [:safe]) == payload

      send(tool_pid, {:gate_release, token})

      # The live run is unaffected by taking a checkpoint.
      kinds = events |> Enum.to_list() |> Enum.map(& &1.kind)
      assert :request_completed in kinds
      assert {:ok, "gate released"} = CheckpointAgent.await(request, timeout: 15_000)
    end

    test "a checkpoint after ask_stream/3 completes is pid-free and restores to a working agent" do
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

      kinds = events |> Enum.to_list() |> Enum.map(& &1.kind)
      assert :request_completed in kinds
      assert {:ok, "README says Hello."} = CheckpointAgent.await(request, timeout: 15_000)

      live = server_agent(pid)
      # The bug: agent state legitimately holds the sink until the terminal
      # transition, which now happens before any checkpoint is written.
      assert Request.stream_sink(live, request.id) == nil

      {:ok, payload} = CheckpointAgent.checkpoint(live, %{})

      assert Checkpoint.runtime_handles(payload) == []
      assert :erlang.binary_to_term(:erlang.term_to_binary(payload), [:safe]) == payload

      # Production thaw replaces the original agent; this test keeps it running,
      # so the revived copy takes a distinct id to avoid a registry collision on
      # the spawned ReAct worker.
      suffix = System.unique_integer([:positive, :monotonic])
      {:ok, restored} = CheckpointAgent.restore(%{payload | id: "restored-agent-#{suffix}"}, %{})

      assert restored.state.requests[request.id].status == :completed
      assert restored.state.requests[request.id].result == "README says Hello."

      # The restored agent is functional: rebuilt tools, fresh supervisor, and
      # it can serve a new streamed request.
      next_script =
        expect_react do
          user("second question")
          answer("second answer")
        end

      registry = Module.concat(__MODULE__, :"RestoredRegistry#{suffix}")
      start_supervised!({Registry, keys: :unique, name: registry}, id: {:restored_registry, suffix})

      {:ok, restored_pid} =
        Jido.AgentServer.start_link(
          agent: restored,
          agent_module: CheckpointAgent,
          registry: registry
        )

      on_exit(fn -> if Process.alive?(restored_pid), do: Process.exit(restored_pid, :kill) end)

      {:ok, %{request: next_request, events: next_events}} =
        CheckpointAgent.ask_stream(
          restored_pid,
          "second question",
          react_opts(next_script) ++ [stream_event_timeout_ms: 15_000]
        )

      next_kinds = next_events |> Enum.to_list() |> Enum.map(& &1.kind)
      assert :request_completed in next_kinds
      assert {:ok, "second answer"} = CheckpointAgent.await(next_request, timeout: 15_000)
    end
  end
end
