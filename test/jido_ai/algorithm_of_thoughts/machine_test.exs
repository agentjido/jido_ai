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

    test "normalizes options and generates distinct call identifiers" do
      machine = Machine.new(temperature: :invalid, examples: [" one ", "", 2])
      assert machine.temperature == 0.0
      assert machine.examples == ["one", "2"]
      assert Machine.new(examples: :invalid).examples == []
      assert String.starts_with?(Machine.generate_call_id(), "aot_")
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

    test "accepts matching content partials and ignores unrelated events" do
      {machine, _} = Machine.update(Machine.new(), {:start, "Solve", "call"})

      {machine, []} = Machine.update(machine, {:llm_partial, "call", "answer: ", :content})
      {machine, []} = Machine.update(machine, {:llm_partial, "call", "ignored", :thinking})
      {machine, []} = Machine.update(machine, {:llm_partial, "other", "ignored", :content})
      assert machine.streaming_text == "answer: "

      assert {^machine, []} = Machine.update(machine, {:llm_result, "other", {:ok, "no"}})
      assert {^machine, []} = Machine.update(machine, :unknown)
    end

    test "handles error envelopes with and without effects" do
      for result <- [{:error, :boom}, {:error, :boom, [:effect]}] do
        {machine, _} = Machine.update(Machine.new(), {:start, "Solve", "call"})
        {machine, []} = Machine.update(machine, {:llm_result, "call", result})

        assert machine.status == "error"
        assert machine.termination_reason == :error
        assert machine.result.diagnostics.error == ":boom"
      end

      machine = %{Machine.new() | status: "exploring", current_call_id: "call", started_at: nil}
      {machine, []} = Machine.update(machine, {:llm_result, "call", {:error, :boom}})
      assert machine.result.termination.duration_ms == 0
    end

    test "accepts common successful result shapes" do
      results = [
        "answer: binary",
        %{text: "answer: atom text", usage: %{input_tokens: 1, output_tokens: 2}},
        %{"text" => "answer: string text", "usage" => %{"total_tokens" => 4}},
        %{content: "answer: atom content", usage: :invalid},
        %{"content" => "answer: string content"}
      ]

      for result <- results do
        {machine, _} = Machine.update(Machine.new(), {:start, "Solve", "call"})
        {machine, []} = Machine.update(machine, {:llm_result, "call", {:ok, result, []}})
        assert machine.status == "completed"
        assert is_binary(machine.result.answer)
      end
    end

    test "uses streamed text when an unknown response has no text" do
      machine = %{
        Machine.new()
        | status: "exploring",
          current_call_id: "call",
          streaming_text: "answer: streamed",
          started_at: System.monotonic_time(:millisecond)
      }

      {machine, []} = Machine.update(machine, {:llm_result, "call", {:ok, :unknown}})
      assert machine.result.answer == "streamed"
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

    test "supports non-text input, optional final answers, and final-answer labels" do
      assert Machine.parse_response(:invalid, true).reason == :no_solution

      optional = Machine.parse_response("solution found", false)
      assert optional.success?
      assert optional.answer == nil

      assert Machine.extract_answer("final answer: 42") == "42"
      assert Machine.extract_answer(:invalid) == nil
    end

    test "round-trips maps with atom, string, and invalid statuses" do
      assert Machine.from_map(%{status: :completed}).status == "completed"
      assert Machine.from_map(%{status: "error"}).status == "error"
      assert Machine.from_map(%{status: 17}).status == "idle"

      machine = %{Machine.new() | status: :completed}
      assert Machine.to_map(machine).status == :completed
    end

    test "builds default prompts for each profile and custom examples" do
      for profile <- [:short, :standard, :long] do
        prompt = Machine.default_system_prompt(profile, :dfs)
        assert prompt =~ "Algorithm-of-Thoughts"
      end

      assert Machine.default_system_prompt(:standard, :bfs, ["custom example"]) =~
               "custom example"

      assert Machine.user_prompt("problem") =~ "Problem:\nproblem"
    end
  end
end
