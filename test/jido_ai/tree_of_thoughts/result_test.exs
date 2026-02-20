defmodule Jido.AI.Reasoning.TreeOfThoughts.ResultTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.TreeOfThoughts.{Machine, Result}

  test "build/2 returns structured result with ranked candidates" do
    machine = %Machine{
      status: "completed",
      nodes: %{
        "root" => %{id: "root", parent_id: nil, content: "Problem", score: nil, children: ["a", "b"], depth: 0},
        "a" => %{id: "a", parent_id: "root", content: "Option A", score: 0.7, children: [], depth: 1},
        "b" => %{id: "b", parent_id: "root", content: "Option B", score: 0.9, children: [], depth: 1}
      },
      root_id: "root",
      frontier: [],
      top_k: 2,
      max_depth: 3,
      branching_factor: 3,
      traversal_strategy: :best_first,
      usage: %{input_tokens: 10, output_tokens: 5},
      started_at: System.monotonic_time(:millisecond) - 5,
      termination_reason: :max_depth
    }

    result = Result.build(machine, top_k: 2)

    assert is_map(result.best)
    assert result.best.content == "Option B"
    assert length(result.candidates) == 2
    assert result.tree.node_count == 3
    assert result.termination.reason == :max_depth
    assert result.usage.input_tokens == 10
  end

  test "best_answer/1 and top_candidates/2 handle nil safely" do
    assert Result.best_answer(nil) == nil
    assert Result.top_candidates(nil, 3) == []
  end

  test "best_answer/1 and top_candidates/2 extract from structured result payload" do
    result = %{
      best: %{content: "Take Option B"},
      candidates: [
        %{content: "Take Option B", score: 0.9},
        %{content: "Take Option A", score: 0.7},
        %{content: "Take Option C", score: 0.5}
      ]
    }

    assert Result.best_answer(result) == "Take Option B"
    assert Enum.map(Result.top_candidates(result, 2), & &1.content) == ["Take Option B", "Take Option A"]
    assert length(Result.top_candidates(result, 10)) == 3
  end
end
