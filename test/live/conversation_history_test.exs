defmodule Jido.AI.Live.ConversationHistoryTest do
  use Jido.AI.Test.LiveCase, async: false

  alias Jido.Agent.Directive.Emit
  alias JidoAI.Examples.ConversationHistory
  alias JidoAI.Examples.ConversationHistory.{Agent, Ask}

  test "a real model uses the first committed turn in the second turn" do
    {:ok, agent} = ConversationHistory.new(id: "live-conversation")
    first_input = "Remember that the project code word is violet. Confirm briefly."
    first_request = Ask.new!(%{question: first_input})

    {first_result, _first_trace} =
      capture_live(agent, first_input, "conversation_history_first_turn", [], fn ->
        with {:ok, updated, [%Emit{signal: reply}]} <- Agent.cmd(agent, first_request) do
          send(self(), {:first_turn, updated})
          {:ok, reply.data}
        end
      end)

    assert {:ok, %{answer: first_answer}} = first_result
    assert is_binary(first_answer)
    assert_receive {:first_turn, agent}

    second_input = "What is the project code word?"
    second_request = Ask.new!(%{question: second_input})

    {second_result, _second_trace} =
      capture_live(agent, second_input, "conversation_history_second_turn", [], fn ->
        with {:ok, updated, [%Emit{signal: reply}]} <- Agent.cmd(agent, second_request) do
          send(self(), {:second_turn, updated})
          {:ok, reply.data}
        end
      end)

    assert {:ok, %{answer: second_answer}} = second_result
    assert String.contains?(String.downcase(second_answer), "violet")
    assert_receive {:second_turn, updated}
    assert updated.state.session.thread.rev == 4
  end
end
