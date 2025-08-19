defmodule Jido.Runner.InstructionDirectiveTest do
  use JidoTest.Case, async: true
  alias Jido.Runner.Simple
  alias Jido.Instruction
  alias JidoTest.TestAgents.FullFeaturedAgent
  alias JidoTest.TestActions.{ReturnInstructionAction, ReturnInstructionListAction}

  @moduletag :capture_log

  describe "instruction directive handling" do
    test "handles single instruction returned as directive" do
      instruction = %Instruction{
        action: ReturnInstructionAction,
        params: %{},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Simple.run(agent)
      assert updated_agent.result == %{}
      # The returned instruction should be added to the queue
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, next_instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert next_instruction.action == ReturnInstructionAction
      assert next_instruction.params == %{value: 42}
    end

    test "handles list of instructions returned as directive" do
      instruction = %Instruction{
        action: ReturnInstructionListAction,
        params: %{},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Simple.run(agent)
      assert updated_agent.result == %{}
      # Both returned instructions should be added to the queue
      assert :queue.len(updated_agent.pending_instructions) == 2

      # Verify first instruction
      {{:value, first}, queue} = :queue.out(updated_agent.pending_instructions)
      assert first.action == ReturnInstructionAction
      assert first.params == %{value: 1}

      # Verify second instruction
      {{:value, second}, _} = :queue.out(queue)
      assert second.action == ReturnInstructionAction
      assert second.params == %{value: 2}
    end
  end
end
