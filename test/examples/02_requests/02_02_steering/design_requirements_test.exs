defmodule JidoAI.Examples.Steering.DesignRequirementsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Orchestration
  alias Jido.AI.Request
  alias JidoAI.Examples.Steering.Agent

  # Target assertions, not characterization. Failures are catalogued in the
  # owning design alignment file. Do not invert these assertions to get green.
  @moduletag :design_requirement

  defp messages(server) do
    {:ok, messages} = Jido.AI.Thread.Projection.messages(Server.agent(server).state.messages)
    Enum.map(messages, &Jido.AI.Query.summarize(&1.content))
  end

  @tag requirements: ["VAL-REQ-023", "SES-REQ-044"]
  test "VAL-REQ-023 pending input is evidence but not completed model conversation", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:wait, :pending, {:text, "Done"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Not completed yet", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :pending, _}, 2_000
    pending = messages(server)
    assert :ok = MockLLM.release(mock, :pending)
    assert {:ok, "Done"} = Request.await(request)
    assert_script_done(mock)
    assert messages(server) == ["Not completed yet", "Done"]
    assert pending == []
  end

  @tag requirements: ["VAL-REQ-023", "SES-REQ-045"]
  test "SES-REQ-045 failed input is absent from the next actual model request", %{jido: jido} do
    {mock, context} =
      native_mock([
        %{reply: {:text, "Saved answer"}},
        %{reply: {:error, 400, "Rejected"}},
        %{reply: {:text, "Continued"}}
      ])

    server = start_agent(jido, Agent.new!())
    {:ok, first} = Agent.ask(server, "Saved input", context: context)
    assert {:ok, "Saved answer"} = Request.await(first)
    {:ok, failed} = Agent.ask(server, "Failed input", context: context)
    assert {:error, _} = Request.await(failed)
    assert Server.agent(server).state.reply == "Saved answer"
    {:ok, next} = Agent.ask(server, "Continue", context: context)
    assert {:ok, "Continued"} = Request.await(next)
    assert_script_done(mock)
    wire = List.last(MockLLM.report(mock).requests).body["messages"]
    assert Enum.any?(wire, &(&1["content"] == "Saved answer"))
    refute Enum.any?(wire, &(&1["content"] == "Failed input"))
  end

  @tag requirements: ["SES-REQ-045"]
  test "SES-REQ-045 cancelled input is absent from completed conversation", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:wait, :cancelled, {:text, "Late"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Cancelled input", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :cancelled, worker}, 2_000
    monitor = Process.monitor(worker)
    assert :ok = Orchestration.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    MockLLM.release(mock, :cancelled)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert_script_done(mock)
    assert messages(server) == []
  end

  @tag requirements: ["SES-REQ-046", "SES-REQ-029"]
  test "SES-REQ-046 queued steering does not claim consumption", %{jido: jido} do
    {mock, context} =
      native_mock([
        %{reply: {:wait, :steering, {:text, "First answer"}}},
        %{reply: {:text, "Updated answer"}}
      ])

    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Work", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :steering, _}, 2_000
    assert {:ok, %{status: :queued}} = Orchestration.steer(request, "Correction")
    queued = messages(server)
    assert :ok = MockLLM.release(mock, :steering)
    assert {:ok, "Updated answer"} = Request.await(request)
    assert_script_done(mock)
    refute "Correction" in queued
    assert "Correction" in messages(server)
  end
end
