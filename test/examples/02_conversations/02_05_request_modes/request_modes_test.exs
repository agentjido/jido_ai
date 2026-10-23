defmodule JidoAI.Examples.RequestModesTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias Jido.Agent.Directive.Reply
  alias Jido.AgentServer
  alias JidoAI.Examples.RequestModes
  alias JidoAI.Examples.RequestModes.{Agent, Ask, Turn}

  @moduletag :example

  setup do
    jido = :"jido_ai_request_modes_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})

    {:ok, jido: jido}
  end

  test "the request-mode example owns its Agent contract and turn Action" do
    assert Agent.definition().name == "request_modes_example"
    assert Ask.type() == "examples.request_modes.ask"
    assert [%{handler: %{kind: :action, target: Turn}}] = Agent.definition().routes
  end

  test "AgentServer call and submit await commit complete Session turns", %{jido: jido} do
    stub(ReqLLM, :generate_text, fn model, context, _options ->
      question = context |> ReqLLM.Context.to_list() |> List.last() |> message_text()
      {:ok, object_response(model, context, %{"answer" => "Answer: #{question}"}, id: "request-mode-response")}
    end)

    {:ok, server} = RequestModes.start(jido, id: "request-modes-success")

    first = Ask.new!(%{question: "First"})
    assert {:ok, called, [%Reply{signal: first_reply}]} = AgentServer.call(server, first)
    assert_receive delivered_first, 1_000
    assert delivered_first.id == first_reply.id
    assert delivered_first.type == first_reply.type
    assert delivered_first.data == first_reply.data
    assert first_reply.type == "examples.request_modes.answered"
    assert first_reply.data == %{answer: "Answer: First"}
    assert called.state.session.thread.rev == 2

    second = Ask.new!(%{question: "Second"})
    pending = AgentServer.submit(server, second)
    assert %AgentServer.Pending{} = pending
    assert {:ok, submitted, [%Reply{signal: second_reply}]} = AgentServer.await(pending)
    assert_receive delivered_second, 1_000
    assert delivered_second.id == second_reply.id
    assert delivered_second.type == second_reply.type
    assert delivered_second.data == second_reply.data
    assert second_reply.data == %{answer: "Answer: Second"}
    assert submitted.state.session.thread.rev == 4
    assert submitted.state.session.metadata == %{example: "request_modes"}
    assert AgentServer.agent(server).state.session == submitted.state.session
  end

  test "AgentServer cancellation leaves no partial Session turn", %{jido: jido} do
    parent = self()

    stub(ReqLLM, :generate_text, fn model, context, _options ->
      send(parent, {:model_request_started, self()})

      receive do
        :finish_request ->
          {:ok, object_response(model, context, %{"answer" => "Too late"}, id: "request-mode-response")}
      end
    end)

    {:ok, server} = RequestModes.start(jido, id: "request-modes-cancel")
    request = Ask.new!(%{question: "Cancel this"})
    pending = AgentServer.submit(server, request)

    assert_receive {:model_request_started, _worker}, 1_000
    assert :ok = AgentServer.cancel(server)
    assert {:error, :cancelled} = AgentServer.await(pending)

    session = AgentServer.agent(server).state.session
    assert session.thread.rev == 0
    assert session.thread.signals == []
  end

  @tag capture_log: true
  test "an AgentServer provider failure does not commit Session state", %{jido: jido} do
    stub(ReqLLM, :generate_text, fn _model, _context, _options ->
      {:error, :provider_unavailable}
    end)

    {:ok, server} = RequestModes.start(jido, id: "request-modes-failure")
    request = Ask.new!(%{question: "Fail this"})

    assert {:error, _reason} = AgentServer.call(server, request)
    assert AgentServer.status(server).state_version == 0

    session = AgentServer.agent(server).state.session
    assert session.thread.rev == 0
    assert session.thread.signals == []
  end

  defp message_text(message), do: message.content |> List.first() |> Map.fetch!(:text)
end
