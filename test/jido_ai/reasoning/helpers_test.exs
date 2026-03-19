defmodule Jido.AI.Reasoning.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.Helpers

  defmodule FailingAction do
    use Jido.Action,
      name: "failing_action",
      description: "Always fails",
      schema: []

    @impl true
    def run(_params, _context), do: {:error, :something_broke}
  end

  describe "execute_action_instruction/3" do
    test "error details include the failure reason" do
      agent = %Jido.Agent{id: "test-agent", name: "test", state: %{}}

      instruction = %Jido.Instruction{
        action: FailingAction,
        params: %{},
        context: %{}
      }

      {_agent, [%Jido.Agent.Directive.Error{error: error}]} =
        Helpers.execute_action_instruction(agent, instruction)

      assert error.message == "Instruction failed"
      assert %{reason: _} = error.details
      assert error.details != %{}
    end
  end
end
