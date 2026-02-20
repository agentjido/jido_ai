defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.MachineTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.AlgorithmOfThoughts.Machine

  describe "new/1" do
    test "uses expected defaults" do
      machine = Machine.new()

      assert machine.status == "idle"
      assert machine.profile == :standard
      assert machine.search_style == :dfs
      assert machine.temperature == 0.0
      assert machine.max_tokens == 2048
      assert machine.require_explicit_answer == true
    end
  end

  describe "update/3" do
    test "start moves to exploring and emits single llm directive" do
      machine = Machine.new()
      {machine, directives} = Machine.update(machine, {:start, "Solve this", "aot_start_1"}, %{})

      state = Machine.to_map(machine)
      assert state[:status] == :exploring
      assert state[:prompt] == "Solve this"
      assert state[:current_call_id] == "aot_start_1"

      assert [{:call_llm_stream, "aot_start_1", context}] = directives
      assert is_list(context)
      assert Enum.any?(context, &(&1[:role] == :system))
      assert Enum.any?(context, &(&1[:role] == :user))
    end

    test "start while exploring emits busy request_error" do
      machine = Machine.new()
      {machine, _} = Machine.update(machine, {:start, "first", "aot_call_1"}, %{})

      {machine, directives} = Machine.update(machine, {:start, "second", "aot_call_2"}, %{})

      assert machine.status == "exploring"
      assert [{:request_error, "aot_call_2", :busy, _message}] = directives
    end

    test "successful llm result completes with structured output" do
      machine = Machine.new()
      {machine, _} = Machine.update(machine, {:start, "Solve", "aot_call_1"}, %{})

      result_text = """
      Trying a promising first operation:
      1. 8 - 6 : (4,4,2)
      - 4 + 2 : (6,4) 24 = 6 * 4 -> found it!
      Backtracking the solution:
      Step 1: 8 - 6 = 2
      Step 2: 4 + 2 = 6
      Step 3: 6 * 4 = 24
      answer: (4 + (8 - 6)) * 4 = 24
      """

      {machine, []} =
        Machine.update(
          machine,
          {:llm_result, "aot_call_1", {:ok, %{text: result_text, usage: %{input_tokens: 11, output_tokens: 17}}}},
          %{}
        )

      state = Machine.to_map(machine)
      assert state[:status] == :completed
      assert state[:termination_reason] == :success
      assert state[:result][:answer] == "(4 + (8 - 6)) * 4 = 24"
      assert state[:result][:found_solution?] == true
      assert state[:result][:first_operations_considered] == 1
      assert state[:result][:backtracking_steps] == 3
      assert state[:result][:usage][:total_tokens] == 28
      assert state[:result][:termination][:reason] == :success
      assert state[:result][:termination][:status] == :completed
    end

    test "non-finalized result fails when explicit answer is required" do
      machine = Machine.new(require_explicit_answer: true)
      {machine, _} = Machine.update(machine, {:start, "Solve", "aot_call_1"}, %{})

      result_text = """
      Trying a promising first operation:
      1. 8 - 6 : (4,4,2)
      - 4 + 2 : (6,4) 24 = 6 * 4 -> found it!
      Backtracking the solution:
      Step 1: 8 - 6 = 2
      """

      {machine, []} = Machine.update(machine, {:llm_result, "aot_call_1", {:ok, %{text: result_text}}}, %{})
      state = Machine.to_map(machine)

      assert state[:status] == :error
      assert state[:termination_reason] == :missing_explicit_answer
      assert state[:result][:answer] == nil
      assert state[:result][:found_solution?] == true
      assert state[:result][:diagnostics][:non_finalization_detected] == true
    end

    test "non-finalized result can pass when explicit answer is not required" do
      machine = Machine.new(require_explicit_answer: false)
      {machine, _} = Machine.update(machine, {:start, "Solve", "aot_call_1"}, %{})

      {machine, []} =
        Machine.update(
          machine,
          {:llm_result, "aot_call_1", {:ok, %{text: "Trying a promising first operation:\n1. ...\nfound it"}}},
          %{}
        )

      state = Machine.to_map(machine)
      assert state[:status] == :completed
      assert state[:termination_reason] == :success
      assert state[:result][:found_solution?] == true
    end
  end

  describe "parse helpers" do
    test "parse_response extracts metrics" do
      text = """
      Trying a promising first operation:
      1. 11 - 3 : (8,5,4)
      Trying another promising first operation:
      2. 11 * 3 : (33,5,4)
      Backtracking the solution:
      Step 1: 11 * 3 = 33
      Step 2: 33 - 5 = 28
      Step 3: 28 - 4 = 24
      answer: ((11 * 3) - 5) - 4 = 24
      """

      parsed = Machine.parse_response(text, true)

      assert parsed.answer == "((11 * 3) - 5) - 4 = 24"
      assert parsed.first_operations_considered == 2
      assert parsed.backtracking_steps == 3
      assert parsed.success? == true
    end
  end
end
