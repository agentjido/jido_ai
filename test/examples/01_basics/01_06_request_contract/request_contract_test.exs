defmodule JidoAI.Examples.RequestContractTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias Jido.AI.{Event, Request, Result}
  alias JidoAI.Examples.RequestContract.Agent

  @moduletag :example

  test "preflight selects declared tools without model work" do
    assert {:ok, request} =
             Agent.preflight("Look up status",
               request_id: "example-request",
               run_id: "example-run",
               visible_tools: [:lookup]
             )

    assert Request.visible_tool_names(request) == ["lookup"]
    assert Enum.map(Request.messages(request), & &1.role) == [:system, :user]
    assert request.controls.max_tool_calls == 2
  end

  test "run returns one correlated ordered event sequence" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      refute Keyword.has_key?(options, :tools)

      {:ok, text_response(model, context, "Ready", id: "request-contract-response")}
    end)

    assert {:ok, %Result{} = result} =
             Agent.run("Reply with Ready",
               request_id: "example-request",
               run_id: "example-run",
               visible_tools: []
             )

    assert result.status == :completed
    assert result.commit == :not_requested
    assert result.output == "Ready"

    assert Enum.map(result.events, & &1.type) == [
             :request_started,
             :model_completed,
             :request_completed
           ]

    assert Enum.map(result.events, & &1.sequence) == [1, 2, 3]
    assert Enum.all?(result.events, &(&1.request_id == "example-request"))
    assert Enum.all?(result.events, &(&1.run_id == "example-run"))
    assert Enum.count(result.events, &Event.terminal?/1) == 1
    assert Result.validate(result) == :ok
  end
end
