defmodule JidoAI.Examples.RequestLessonsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request

  test "the authored completion Agent commits its portable receipt and answer", %{jido: jido} do
    alias JidoAI.Examples.Completion.Agent

    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "receipt", name: "record_receipt", arguments: %{entry: "case-42"}}]}},
        %{reply: {:text, "Recorded"}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Record case-42", context: context, model: MockLLM.model())
    assert {:ok, "Recorded"} = Request.await(request)
    assert Server.agent(server).state.receipt_count == 1
    assert Server.agent(server).state.reply == "Recorded"
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end
end
