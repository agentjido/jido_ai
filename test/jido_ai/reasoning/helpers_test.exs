defmodule Jido.AI.Reasoning.HelpersTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Reasoning.Helpers

  setup :set_mimic_from_context

  setup do
    Mimic.copy(Jido.Exec)
    :ok
  end

  defmodule FailingAction do
    use Jido.Action,
      name: "failing_action",
      description: "Always fails",
      schema: Zoi.object(%{})

    @impl true
    def run(_params, _context), do: {:error, :something_broke}
  end

  describe "execute_action_instruction/3" do
    test "error details include the failure reason" do
      agent = %Jido.Agent{
        id: "test-agent",
        name: "test",
        state: %{},
        schema: Zoi.object(%{}),
        module: Jido.Agent
      }

      instruction = %Jido.Instruction{target: FailingAction, params: %{}, context: %{}}

      {_agent, [%Jido.Agent.Directive.Error{error: error}]} =
        Helpers.execute_action_instruction(agent, instruction)

      assert error.message == "Instruction failed"
      assert %{reason: _} = error.details
      assert error.details != %{}
    end

    test "uses explicit execution options from context" do
      expect_exec_opts(fn opts ->
        assert opts == [log_level: :warning, telemetry: :silent]
      end)

      Helpers.execute_action_instruction(test_agent(), test_instruction(), %{
        exec_opts: [log_level: :warning, telemetry: :silent]
      })
    end

    test "does not use instruction options as Exec options" do
      expect_exec_opts(fn opts ->
        assert opts == []
      end)

      instruction =
        test_instruction()
        |> Map.put(:opts, log_level: :error, telemetry: :full, retry: false)

      Helpers.execute_action_instruction(test_agent(), instruction)
    end

    test "ignores unrelated context when no execution options are present" do
      expect_exec_opts(fn opts ->
        assert opts == []
      end)

      Helpers.execute_action_instruction(test_agent(), test_instruction(), %{observability: %{log_level: :debug}})
    end

    test "applies successful two- and three-tuple results" do
      for result <- [{:ok, %{}}, {:ok, %{}, []}] do
        expect(Jido.Exec, :run, fn _instruction, %{}, %{}, [] -> result end)
        {agent, directives} = Helpers.execute_action_instruction(test_agent(), test_instruction())
        assert agent.state == %{}
        assert directives == []
      end
    end

    test "normalizes three-tuple errors and invalid state proposals" do
      expect(Jido.Exec, :run, fn _instruction, %{}, %{}, [] -> {:error, :three_tuple, []} end)

      {_agent, [%Jido.Agent.Directive.Error{error: error}]} =
        Helpers.execute_action_instruction(test_agent(), test_instruction())

      assert error.details.reason == :three_tuple

      expect(Jido.Exec, :run, fn _instruction, %{}, %{}, [] -> {:ok, %{unknown: true}} end)

      {_agent, [%Jido.Agent.Directive.Error{}]} =
        Helpers.execute_action_instruction(test_agent(), test_instruction())
    end

    test "conditionally executes only resolvable targets" do
      expect(Jido.Exec, :run, fn _instruction, %{}, %{}, [] -> {:error, :expected} end)

      assert {_agent, [%Jido.Agent.Directive.Error{}]} =
               Helpers.maybe_execute_action_instruction(test_agent(), test_instruction())

      instruction = %Jido.Instruction{target: :not_an_executable, params: %{}, context: %{}}
      assert :noop = Helpers.maybe_execute_action_instruction(test_agent(), instruction)
    end

    test "builds the complete Action context" do
      agent = test_agent()

      assert Helpers.action_context(agent, %{caller: :test}) == %{
               caller: :test,
               state: %{},
               agent_state: %{},
               agent_id: "test-agent"
             }
    end
  end

  defp expect_exec_opts(assertion) do
    Mimic.expect(Jido.Exec, :run, fn %Jido.Instruction{}, %{}, %{}, opts ->
      assertion.(opts)
      {:error, :something_broke}
    end)
  end

  defp test_agent,
    do: %Jido.Agent{
      id: "test-agent",
      name: "test",
      state: %{},
      schema: Zoi.object(%{}),
      module: Jido.Agent
    }

  defp test_instruction do
    %Jido.Instruction{target: FailingAction, params: %{}, context: %{}}
  end
end
