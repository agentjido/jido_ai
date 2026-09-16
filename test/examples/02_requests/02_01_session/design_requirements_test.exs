defmodule JidoAI.Examples.Session.DesignRequirementsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request
  alias JidoAI.Examples.Session.Agent
  @moduletag :design_requirement

  @tag requirements: ["OBS-REQ-016"]
  test "OBS-REQ-016 tool keepalives carry no content and do not extend the request deadline", %{jido: jido} do
    profile = Jido.AI.Agent.profile(Agent, :assistant) |> Map.from_struct()

    profile = %{
      profile
      | requests: Map.put(profile.requests, :tool_heartbeat, 10),
        controls: Map.put(profile.controls, :timeout, 500),
        tools: [
          %{name: "hold", target: JidoAI.Examples.AIRuntime.WaitTool, forward_context: [:observer], timeout: 5_000}
        ]
    }

    base = %{
      name: "keepalive_example",
      schema: Agent.domain_schema(),
      routes: [{"ai.ask", Jido.AI.Authoring.ai(:assistant)}]
    }

    assert {:ok, definition} = Jido.AI.Authoring.lower(base, [profile])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    {mock, context} = native_mock([%{reply: {:tools, [%{id: "held", name: "hold", arguments: %{n: 1}}]}}])
    context = Map.put(context, :observer, self())
    assert {:ok, request} = Agent.ask(server, "Work", context: context, stream_to: self())
    assert_receive {:tool_waiting, worker, 1}, 2_000
    monitor = Process.monitor(worker)
    assert_receive {:jido_ai_request_event, %{kind: :keepalive, data: data}}, 2_000
    assert Map.keys(data) -- [:source] == []
    assert {:error, _} = Request.await(request, timeout: 2_000)
    assert Server.agent(server).state.requests[request.id].status == :failed
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert_script_done(mock)
  end

  @tag requirements: ["SES-REQ-022"]
  test "SES-REQ-022 the accepted request survives termination of its stream sink", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:wait, :sink, {:text, "Finished"}}}])
    sink = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end}, restart: :temporary)
    monitor = Process.monitor(sink)
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Work", context: context, stream_to: sink)
    assert_receive {:mock_llm_waiting, ^mock, :sink, _}, 2_000
    send(sink, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^sink, :normal}, 2_000
    assert :ok = MockLLM.release(mock, :sink)
    assert {:ok, "Finished"} = Request.await(request)
    assert Server.agent(server).state.reply == "Finished"
    assert_script_done(mock)
  end
end
