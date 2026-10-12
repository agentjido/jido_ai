defmodule Jido.AI.Reasoning.ReAct.WorkerStrategyTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ReAct.Config
  alias Jido.AI.Reasoning.ReAct.Worker.Strategy
  alias ReqLLM.Message.ContentPart

  setup :set_mimic_from_context

  test "stream exhaustion without a terminal event fails the parent once" do
    alias Jido.AgentServer.ParentRef
    alias Jido.AI.Reasoning.ReAct.Worker

    worker = Worker.Agent.new(state: %{__parent__: ParentRef.new!(%{pid: self(), id: "parent", tag: :react_worker})})
    state = StratState.get(worker)
    worker = StratState.put(worker, %{state | status: :running, active_request_id: "request", run_id: "run", seq: 7})
    done = %Jido.Instruction{action: :react_worker_runtime_done, params: %{request_id: "request"}}

    {worker, [%Worker.EmitEvent{signal: signal}]} = Strategy.cmd(worker, [done], %{})

    assert %{
             request_id: "request",
             event: %{
               kind: :request_failed,
               seq: 8,
               run_id: "run",
               data: %{error: :missing_terminal_event, error_type: :worker_task}
             }
           } = signal.data

    state = StratState.get(worker)
    assert state.active_request_id == nil
    assert state.runtime_task == nil
    assert state.last_error == :missing_terminal_event
    assert {^worker, []} = Strategy.cmd(worker, [done], %{})
  end

  test "done after a terminal event does not send a second failure" do
    alias Jido.AI.Reasoning.ReAct.Worker
    alias Jido.AI.Runtime.Event

    worker = Worker.Agent.new()
    state = StratState.get(worker)
    worker = StratState.put(worker, %{state | status: :running, active_request_id: "request", run_id: "run"})

    event =
      Event.new(%{
        kind: :request_failed,
        request_id: "request",
        run_id: "run",
        seq: 1,
        iteration: 1,
        data: %{error: :stream_timeout}
      })

    instruction = %Jido.Instruction{
      action: :react_worker_runtime_event,
      params: %{request_id: "request", event: Map.from_struct(event)}
    }

    {worker, []} = Strategy.cmd(worker, [instruction], %{})
    done = %Jido.Instruction{action: :react_worker_runtime_done, params: %{request_id: "request"}}
    assert {^worker, []} = Strategy.cmd(worker, [done], %{})
  end

  test "starts delegated runtime for multimodal query lists" do
    parent = self()

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, messages, _opts ->
      send(parent, {:req_llm_messages, messages})
      {:ok, resolved_model} = ReqLLM.model(model)
      {:ok, metadata_handle} = ReqLLM.StreamResponse.MetadataHandle.start_link(fn -> %{finish_reason: :stop} end)

      {:ok,
       %ReqLLM.StreamResponse{
         stream: [ReqLLM.StreamChunk.text("Done")],
         metadata_handle: metadata_handle,
         model: resolved_model,
         context: ReqLLM.Context.new([]),
         cancel: fn -> :ok end
       }}
    end)

    query = [
      ContentPart.text("Summarize this document."),
      ContentPart.file_id("file_123")
    ]

    agent =
      %Jido.Agent{id: "worker-test", name: "worker", state: %{}}
      |> then(fn agent ->
        {agent, []} = Strategy.init(agent, %{})
        agent
      end)

    start =
      %Jido.Instruction{
        action: :react_worker_start,
        params: %{
          request_id: "req_file",
          run_id: "req_file",
          query: query,
          config: Config.new(%{model: :capable, tools: %{}})
        }
      }

    {agent, []} = Strategy.cmd(agent, [start], %{})

    state = StratState.get(agent, %{})
    assert state.status == :running
    assert state.active_request_id == "req_file"

    assert_receive {:req_llm_messages, [%{role: :user, content: ^query}]}, 200
  end
end
