defmodule Jido.AI.Live.RequestContractTest do
  use Jido.AI.Test.LiveCase, async: false

  alias Jido.AI.{Event, Request, Result}
  alias JidoAI.Examples.BasicAgent.Agent, as: BasicAgent
  alias JidoAI.Examples.ToolFlow.Agent, as: ToolAgent

  test "a prepared request and real result keep one identity and event order" do
    input = "Reply with the word ready."

    options =
      live_options(
        max_tokens: 32,
        request_id: "live-request-contract",
        run_id: "live-request-contract-run",
        visible_tools: []
      )

    assert {:ok, prepared} = BasicAgent.preflight(input, options)
    assert prepared.request_id == "live-request-contract"
    assert prepared.run_id == "live-request-contract-run"
    assert Request.visible_tool_names(prepared) == []
    assert Enum.map(Request.messages(prepared), & &1.role) == [:system, :user]

    {result, _trace} =
      capture_live(BasicAgent, input, "request_contract", options, fn ->
        BasicAgent.run(input, options)
      end)

    assert {:ok, %Result{} = outcome} = result
    assert outcome.status == :completed
    assert is_binary(outcome.output)
    assert String.trim(outcome.output) != ""
    assert outcome.request_id == prepared.request_id
    assert outcome.run_id == prepared.run_id
    assert Result.validate(outcome) == :ok
    assert Enum.count(outcome.events, &Event.terminal?/1) == 1
  end

  test "a real model uses the selected Action and does not receive the hidden Flow" do
    {:ok, counter} = Elixir.Agent.start_link(fn -> 0 end)
    input = "Call multiply with left 8 and right 9. Return its product."

    options =
      live_options(
        max_tokens: 64,
        visible_tools: [:multiply],
        jido_context: %{counter: counter}
      )

    assert {:ok, prepared} = ToolAgent.preflight(input, options)
    assert Request.visible_tool_names(prepared) == ["multiply"]

    {result, _trace} =
      capture_live(ToolAgent, input, "visible_tool_selection", options, fn ->
        ToolAgent.reason(input, options)
      end)

    assert {:ok, outcome} = result
    assert String.contains?(outcome.output, "72")
    assert outcome.usage.tool_calls == 1
    assert hd(outcome.events).data.visible_tools == ["multiply"]
    assert Elixir.Agent.get(counter, & &1) == 1
  end
end
