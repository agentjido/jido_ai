defmodule Jido.AI.Reasoning.TreeOfThoughts.MachineTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.TreeOfThoughts.Machine

  describe "new/1" do
    test "initializes with structured ToT defaults" do
      machine = Machine.new()

      assert machine.status == "idle"
      assert machine.top_k == 3
      assert machine.min_depth == 2
      assert machine.max_nodes == 100
      assert machine.convergence_window == 2
      assert machine.min_score_improvement == 0.02
      assert machine.max_parse_retries == 1
    end

    test "accepts flexibility controls" do
      machine =
        Machine.new(
          top_k: 5,
          min_depth: 1,
          max_nodes: 250,
          max_duration_ms: 50_000,
          beam_width: 4,
          early_success_threshold: 0.9,
          convergence_window: 3,
          min_score_improvement: 0.01,
          max_parse_retries: 2
        )

      assert machine.top_k == 5
      assert machine.min_depth == 1
      assert machine.max_nodes == 250
      assert machine.max_duration_ms == 50_000
      assert machine.beam_width == 4
      assert machine.early_success_threshold == 0.9
      assert machine.convergence_window == 3
      assert machine.min_score_improvement == 0.01
      assert machine.max_parse_retries == 2
    end
  end

  describe "update/3 lifecycle" do
    test "starts in generating state and emits generation directive" do
      machine = Machine.new(branching_factor: 3)

      {machine, directives} = Machine.update(machine, {:start, "Plan a weekend", "tot_start_1"}, %{})

      assert machine.status == "generating"
      assert machine.prompt == "Plan a weekend"
      assert machine.root_id
      assert [{:generate_thoughts, "tot_start_1", context, 3}] = directives
      assert is_list(context)
      assert length(context) == 2
    end

    test "normalizes pending thoughts with stable ids" do
      machine =
        %Machine{
          status: "generating",
          current_call_id: "tot_123",
          nodes: %{"root" => %{id: "root", parent_id: nil, content: "Problem", score: nil, children: [], depth: 0}},
          root_id: "root",
          current_node_id: "root",
          started_at: System.monotonic_time(:millisecond)
        }

      {machine, directives} =
        Machine.update(machine, {:thoughts_generated, "tot_123", ["Approach A", "Approach B", "Approach C"]}, %{})

      assert machine.status == "evaluating"
      assert [%{id: "t1", content: "Approach A"}, %{id: "t2"}, %{id: "t3"}] = machine.pending_thoughts
      assert [{:evaluate_thoughts, _call_id, entries}] = directives
      assert Enum.all?(entries, &is_map/1)
      assert Enum.map(entries, & &1.id) == ["t1", "t2", "t3"]
    end
  end

  describe "deterministic stopping policy" do
    test "honors min_depth before threshold completion" do
      machine = evaluating_machine(min_depth: 2, max_depth: 3)
      scores = %{"t1" => 1.0, "t2" => 0.6, "t3" => 0.4}

      {machine, directives} = Machine.update(machine, {:thoughts_evaluated, "tot_eval_1", scores}, %{})

      assert machine.status == "generating"
      assert machine.termination_reason == nil
      assert [{:generate_thoughts, _call_id, _context, 3}] = directives
    end

    test "completes on threshold when min_depth is met" do
      machine = evaluating_machine(min_depth: 1, max_depth: 3)
      scores = %{"t1" => 1.0, "t2" => 0.6, "t3" => 0.4}

      {machine, []} = Machine.update(machine, {:thoughts_evaluated, "tot_eval_1", scores}, %{})

      assert machine.status == "completed"
      assert machine.termination_reason == :threshold
      assert is_map(machine.result)
      assert machine.result.best.content == "Approach A"
    end

    test "stops on max_nodes budget before depth fallback" do
      machine = evaluating_machine(max_nodes: 2, max_depth: 5)
      scores = %{"t1" => 0.9, "t2" => 0.7, "t3" => 0.2}

      {machine, []} = Machine.update(machine, {:thoughts_evaluated, "tot_eval_1", scores}, %{})

      assert machine.status == "completed"
      assert machine.termination_reason == :max_nodes
      assert is_map(machine.result)
      assert machine.result.termination.reason == :max_nodes
    end

    test "stops on max_duration budget before depth fallback" do
      machine =
        evaluating_machine(
          max_duration_ms: 1,
          started_at: System.monotonic_time(:millisecond) - 100
        )

      scores = %{"t1" => 0.9, "t2" => 0.7, "t3" => 0.2}
      {machine, []} = Machine.update(machine, {:thoughts_evaluated, "tot_eval_1", scores}, %{})

      assert machine.status == "completed"
      assert machine.termination_reason == :max_duration
      assert machine.result.termination.reason == :max_duration
    end

    test "falls back to max_depth with structured result" do
      machine = evaluating_machine(max_depth: 1)
      scores = %{"t1" => 0.8, "t2" => 0.9, "t3" => 0.3}

      {machine, []} = Machine.update(machine, {:thoughts_evaluated, "tot_eval_1", scores}, %{})

      assert machine.status == "completed"
      assert machine.termination_reason == :max_depth
      assert machine.result.best.content == "Approach B"
      assert machine.result.candidates != []
      assert machine.result.tree.node_count >= 4
    end
  end

  describe "JSON-first parser with fallback" do
    test "parse_thoughts/1 prefers JSON payloads" do
      text = ~s({"thoughts":[{"id":"t1","content":"Alpha"},{"id":"t2","content":"Beta"}]})

      {thoughts, mode} = Machine.parse_thoughts(text)

      assert mode == :json
      assert thoughts == ["Alpha", "Beta"]
    end

    test "parse_thoughts/1 falls back to regex" do
      text = "1. Alpha\n2. Beta\n3. Gamma"

      {thoughts, mode} = Machine.parse_thoughts(text)

      assert mode == :regex
      assert thoughts == ["Alpha", "Beta", "Gamma"]
    end

    test "parse_scores/2 prefers JSON scores keyed by thought id" do
      text = ~s({"scores":{"t1":0.91,"t2":0.52}})
      thoughts = [%{id: "t1", content: "Alpha"}, %{id: "t2", content: "Beta"}]

      {scores, mode} = Machine.parse_scores(text, thoughts)

      assert mode == :json
      assert scores["t1"] == 0.91
      assert scores["t2"] == 0.52
    end

    test "parse_scores/2 falls back to regex" do
      text = "1: 0.7\n2: 0.4"
      thoughts = [%{id: "t1", content: "Alpha"}, %{id: "t2", content: "Beta"}]

      {scores, mode} = Machine.parse_scores(text, thoughts)

      assert mode == :regex
      assert scores["t1"] == 0.7
      assert scores["t2"] == 0.4
    end
  end

  describe "parse retry behavior" do
    test "retries once then fails with structured diagnostics" do
      machine =
        %Machine{
          status: "generating",
          current_call_id: "tot_gen_1",
          nodes: %{"root" => %{id: "root", parent_id: nil, content: "Problem", score: nil, children: [], depth: 0}},
          root_id: "root",
          current_node_id: "root",
          started_at: System.monotonic_time(:millisecond),
          max_parse_retries: 1
        }

      # First failure -> repair retry directive
      {machine, [{:call_llm_stream, retry_call_id, _repair_context}]} =
        Machine.update(machine, {:llm_result, "tot_gen_1", {:ok, %{text: "not parseable"}}}, %{})

      assert machine.status == "generating"
      assert retry_call_id == machine.current_call_id
      assert machine.parse_retries.generation == 1

      # Second failure -> terminal parse error
      {machine, []} = Machine.update(machine, {:llm_result, retry_call_id, {:ok, %{text: "still invalid"}}}, %{})

      assert machine.status == "error"
      assert machine.termination_reason == :error
      assert machine.result.termination.reason == :error
      assert machine.result.diagnostics.error =~ "parse_failed"
      assert :generation_parse_retry in machine.parser_errors
      assert :thoughts_parse_failed in machine.parser_errors
    end
  end

  describe "to_map/from_map" do
    test "round-trips structured fields" do
      machine =
        Machine.new(
          top_k: 4,
          min_depth: 1,
          max_nodes: 77,
          max_duration_ms: 999,
          beam_width: 5,
          max_parse_retries: 2
        )

      map = Machine.to_map(machine)
      restored = Machine.from_map(map)

      assert restored.status == "idle"
      assert restored.top_k == 4
      assert restored.min_depth == 1
      assert restored.max_nodes == 77
      assert restored.max_duration_ms == 999
      assert restored.beam_width == 5
      assert restored.max_parse_retries == 2
    end
  end

  defp evaluating_machine(overrides) do
    base = %Machine{
      status: "evaluating",
      current_call_id: "tot_eval_1",
      nodes: %{
        "root" => %{id: "root", parent_id: nil, content: "Problem", score: nil, children: [], depth: 0}
      },
      root_id: "root",
      current_node_id: "root",
      pending_thoughts: [
        %{id: "t1", content: "Approach A"},
        %{id: "t2", content: "Approach B"},
        %{id: "t3", content: "Approach C"}
      ],
      branching_factor: 3,
      max_depth: 3,
      traversal_strategy: :best_first,
      frontier: [],
      top_k: 3,
      min_depth: 2,
      max_nodes: 100,
      early_success_threshold: 1.0,
      convergence_window: 2,
      min_score_improvement: 0.02,
      started_at: System.monotonic_time(:millisecond)
    }

    Enum.reduce(overrides, base, fn {key, value}, acc -> Map.put(acc, key, value) end)
  end
end
