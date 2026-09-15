defmodule Jido.AI.Runtime.CheckpointTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Runtime.Checkpoint

  defmodule Format do
    @behaviour Checkpoint
    def verify(%{checkpoint: data}, _), do: Checkpoint.validate_data(data)
    def pack(_native, data, _binding), do: {:ok, %{checkpoint: data}}
    def fingerprint(_, _, _), do: %{}
    def issue(value, _), do: value
  end

  defp native do
    %{
      profile: %{memory: %{history: :conversation}, effect_policy: %{}, reasoning: %{effect_policy: %{}}},
      options: [callback: fn x -> x end],
      effect_plan:
        Jido.AI.Effects.Candidate.new(%{
          conversation: Jido.Session.new(),
          requests: %{},
          messages: "domain field",
          answer: "done"
        }),
      deadline: System.monotonic_time(:millisecond) + 10_000,
      messages: ReqLLM.Context.new([]),
      history_delta: [],
      iterations: 0,
      model_calls: 0,
      tool_calls: 0,
      repairs: 0,
      usage: %{}
    }
  end

  defp context(checkpoint \\ nil) do
    %{
      jido_ai_checkpoint: %{
        adapter: Format,
        result_key: :saved,
        config: %{},
        state: %{checkpoint: checkpoint, request_id: "request", run_id: "run"}
      }
    }
  end

  test "ordinary requests do not allocate checkpoint state" do
    state = native()
    refute Checkpoint.enabled?(%{})
    refute Checkpoint.resumed?(%{})
    assert :ok = Checkpoint.admission(%{}, "request", "run")
    assert {:ok, ^state} = Checkpoint.pause(state, :after_llm, %{})
    assert {:ok, ^state} = Checkpoint.restore(state, %{})
    assert {:ok, %{}} = Checkpoint.terminal(state, %{}, %{})
  end

  test "capture excludes the selected Session and live collaborators without depending on ReAct" do
    assert {:ok, %{saved: data}} = Checkpoint.terminal(native(), %{}, context())
    assert data.domain == %{messages: "domain field", answer: "done"}
    assert data.effects == []
    assert :ok = Checkpoint.validate_data(data)
    refute Map.has_key?(data.runtime, :profile)
    refute Map.has_key?(data.runtime, :options)
    refute Map.has_key?(data.runtime, :effect_plan)
    assert data.remaining_ms <= 10_000
  end

  test "restore keeps fresh runtime policy and cannot extend the caller deadline" do
    state = native()
    assert {:ok, %{saved: data}} = Checkpoint.terminal(state, %{}, context())
    assert {:ok, restored} = Checkpoint.restore(state, context(data))
    assert restored.profile == state.profile
    assert restored.options == state.options
    assert restored.effect_plan == state.effect_plan
    assert restored.deadline <= state.deadline
    assert restored.checkpoint_phase == :terminal

    assert {:error, :checkpoint_deadline_exhausted} =
             Checkpoint.restore(state, context(%{data | remaining_ms: 0}))
  end

  test "invalid snapshot fields and request identities fail before resume" do
    assert {:ok, %{saved: data}} = Checkpoint.terminal(native(), %{}, context())

    assert {:error, :invalid_runtime_checkpoint} =
             Checkpoint.validate_data(%{data | runtime: Map.put(data.runtime, :worker, self())})

    assert {:error, :invalid_runtime_checkpoint} = Checkpoint.validate_data(%{data | phase: :unknown})
    assert {:error, :invalid_checkpoint_binding} = Checkpoint.admission(context(data), "other", "run")
  end
end
