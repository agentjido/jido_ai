defmodule Jido.AI.Reasoning.ReAct.WorkerStrategyTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ReAct.Config
  alias Jido.AI.Reasoning.ReAct.Worker.Strategy
  alias ReqLLM.Message.ContentPart

  setup :set_mimic_from_context

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
