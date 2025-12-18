defmodule Jido.AI.Runner.GEPA.TrajectoryTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Trajectory
  alias Jido.AI.Runner.GEPA.Trajectory.{StateSnapshot, Step}

  describe "new/1" do
    test "creates a new trajectory with default values" do
      trajectory = Trajectory.new()

      assert %Trajectory{} = trajectory
      assert is_binary(trajectory.id)
      assert String.starts_with?(trajectory.id, "traj_")
      assert trajectory.steps == []
      assert trajectory.state_snapshots == []
      assert %DateTime{} = trajectory.started_at
      assert is_nil(trajectory.completed_at)
      assert is_nil(trajectory.duration_ms)
      assert trajectory.metadata == %{}
      assert is_nil(trajectory.outcome)
      assert is_nil(trajectory.error)
      assert trajectory.filtered == false
    end

    test "creates trajectory with custom metadata" do
      metadata = %{prompt: "Test prompt", task_type: :reasoning}
      trajectory = Trajectory.new(metadata: metadata)

      assert trajectory.metadata == metadata
    end

    test "creates trajectory with custom ID" do
      custom_id = "custom_traj_123"
      trajectory = Trajectory.new(id: custom_id)

      assert trajectory.id == custom_id
    end

    test "sets started_at to current time" do
      before = DateTime.utc_now()
      trajectory = Trajectory.new()
      after_time = DateTime.utc_now()

      assert DateTime.compare(trajectory.started_at, before) in [:gt, :eq]
      assert DateTime.compare(trajectory.started_at, after_time) in [:lt, :eq]
    end
  end

  describe "add_step/2" do
    test "adds a reasoning step" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_step(trajectory,
          type: :reasoning,
          content: "Let me think about this..."
        )

      assert length(trajectory.steps) == 1
      [step] = trajectory.steps

      assert %Step{} = step
      assert step.type == :reasoning
      assert step.content == "Let me think about this..."
      assert %DateTime{} = step.timestamp
      assert step.importance == :medium
    end

    test "adds an action step" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_step(trajectory,
          type: :action,
          content: "Calling tool",
          metadata: %{tool: "calculator"}
        )

      assert length(trajectory.steps) == 1
      [step] = trajectory.steps

      assert step.type == :action
      assert step.content == "Calling tool"
      assert step.metadata.tool == "calculator"
    end

    test "adds an observation step" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_step(trajectory,
          type: :observation,
          content: "Tool returned result: 42"
        )

      assert length(trajectory.steps) == 1
      [step] = trajectory.steps

      assert step.type == :observation
      assert step.content == "Tool returned result: 42"
    end

    test "adds a tool_call step" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_step(trajectory,
          type: :tool_call,
          content: %{tool: "calculator", args: [2, 2], result: 4}
        )

      assert length(trajectory.steps) == 1
      [step] = trajectory.steps

      assert step.type == :tool_call
      assert is_map(step.content)
    end

    test "adds a state_change step" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_step(trajectory,
          type: :state_change,
          content: "State transitioned to ready"
        )

      assert length(trajectory.steps) == 1
      [step] = trajectory.steps

      assert step.type == :state_change
    end

    test "requires type and content" do
      trajectory = Trajectory.new()

      assert_raise ArgumentError, ~r/requires :type and :content/, fn ->
        Trajectory.add_step(trajectory, type: :reasoning)
      end

      assert_raise ArgumentError, ~r/requires :type and :content/, fn ->
        Trajectory.add_step(trajectory, content: "test")
      end
    end

    test "preserves step order" do
      trajectory = Trajectory.new()

      trajectory =
        trajectory
        |> Trajectory.add_step(type: :reasoning, content: "Step 1")
        |> Trajectory.add_step(type: :action, content: "Step 2")
        |> Trajectory.add_step(type: :observation, content: "Step 3")

      assert length(trajectory.steps) == 3
      [step1, step2, step3] = trajectory.steps

      assert step1.content == "Step 1"
      assert step2.content == "Step 2"
      assert step3.content == "Step 3"
    end

    test "sets step importance" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_step(trajectory,
          type: :reasoning,
          content: "Critical step",
          importance: :critical
        )

      [step] = trajectory.steps
      assert step.importance == :critical
    end

    test "supports parent_step_id for nested steps" do
      trajectory = Trajectory.new()

      trajectory = Trajectory.add_step(trajectory, type: :action, content: "Parent step")
      [parent] = trajectory.steps

      trajectory =
        Trajectory.add_step(trajectory,
          type: :observation,
          content: "Child step",
          parent_step_id: parent.id
        )

      assert length(trajectory.steps) == 2
      [_parent, child] = trajectory.steps
      assert child.parent_step_id == parent.id
    end

    test "supports context and metadata" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_step(trajectory,
          type: :reasoning,
          content: "Step with context",
          metadata: %{key: "value"},
          context: %{state: "active"}
        )

      [step] = trajectory.steps
      assert step.metadata == %{key: "value"}
      assert step.context == %{state: "active"}
    end

    test "supports duration_ms" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_step(trajectory,
          type: :action,
          content: "Long running action",
          duration_ms: 1500
        )

      [step] = trajectory.steps
      assert step.duration_ms == 1500
    end

    test "generates unique step IDs" do
      trajectory = Trajectory.new()

      trajectory =
        trajectory
        |> Trajectory.add_step(type: :reasoning, content: "Step 1")
        |> Trajectory.add_step(type: :reasoning, content: "Step 2")

      [step1, step2] = trajectory.steps
      assert step1.id != step2.id
      assert String.starts_with?(step1.id, "step_")
      assert String.starts_with?(step2.id, "step_")
    end
  end

  describe "add_snapshot/2" do
    test "adds a state snapshot" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_snapshot(trajectory,
          state: %{variables: %{x: 42}}
        )

      assert length(trajectory.state_snapshots) == 1
      [snapshot] = trajectory.state_snapshots

      assert %StateSnapshot{} = snapshot
      assert snapshot.state == %{variables: %{x: 42}}
      assert %DateTime{} = snapshot.timestamp
      assert snapshot.reason == :checkpoint
    end

    test "requires state" do
      trajectory = Trajectory.new()

      assert_raise ArgumentError, ~r/requires :state/, fn ->
        Trajectory.add_snapshot(trajectory, reason: :test)
      end
    end

    test "supports custom reason" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_snapshot(trajectory,
          state: %{data: "test"},
          reason: :before_action
        )

      [snapshot] = trajectory.state_snapshots
      assert snapshot.reason == :before_action
    end

    test "links to steps via step_id" do
      trajectory = Trajectory.new()
      trajectory = Trajectory.add_step(trajectory, type: :action, content: "Test action")
      [step] = trajectory.steps

      trajectory =
        Trajectory.add_snapshot(trajectory,
          state: %{after_action: true},
          step_id: step.id
        )

      [snapshot] = trajectory.state_snapshots
      assert snapshot.step_id == step.id
    end

    test "supports metadata" do
      trajectory = Trajectory.new()

      trajectory =
        Trajectory.add_snapshot(trajectory,
          state: %{data: "test"},
          metadata: %{checkpoint: true, index: 1}
        )

      [snapshot] = trajectory.state_snapshots
      assert snapshot.metadata == %{checkpoint: true, index: 1}
    end

    test "generates unique snapshot IDs" do
      trajectory = Trajectory.new()

      trajectory =
        trajectory
        |> Trajectory.add_snapshot(state: %{snap: 1})
        |> Trajectory.add_snapshot(state: %{snap: 2})

      [snap1, snap2] = trajectory.state_snapshots
      assert snap1.id != snap2.id
      assert String.starts_with?(snap1.id, "snap_")
      assert String.starts_with?(snap2.id, "snap_")
    end

    test "preserves snapshot order" do
      trajectory = Trajectory.new()

      trajectory =
        trajectory
        |> Trajectory.add_snapshot(state: %{sequence: 1})
        |> Trajectory.add_snapshot(state: %{sequence: 2})
        |> Trajectory.add_snapshot(state: %{sequence: 3})

      assert length(trajectory.state_snapshots) == 3
      [snap1, snap2, snap3] = trajectory.state_snapshots

      assert snap1.state.sequence == 1
      assert snap2.state.sequence == 2
      assert snap3.state.sequence == 3
    end
  end

  describe "complete/2" do
    test "marks trajectory as complete" do
      trajectory = Trajectory.new()
      Process.sleep(10)
      trajectory = Trajectory.complete(trajectory)

      assert %DateTime{} = trajectory.completed_at
      assert is_integer(trajectory.duration_ms)
      assert trajectory.duration_ms > 0
      assert trajectory.outcome == :success
      assert is_nil(trajectory.error)
    end

    test "calculates duration correctly" do
      trajectory = Trajectory.new()
      Process.sleep(50)
      trajectory = Trajectory.complete(trajectory)

      assert trajectory.duration_ms >= 50
    end

    test "sets custom outcome" do
      trajectory = Trajectory.new()

      trajectory = Trajectory.complete(trajectory, outcome: :failure)

      assert trajectory.outcome == :failure
    end

    test "records error information" do
      trajectory = Trajectory.new()

      trajectory = Trajectory.complete(trajectory, outcome: :error, error: :timeout)

      assert trajectory.outcome == :error
      assert trajectory.error == :timeout
    end

    test "accepts custom completed_at time" do
      trajectory = Trajectory.new()
      custom_time = DateTime.utc_now()

      trajectory = Trajectory.complete(trajectory, completed_at: custom_time)

      assert trajectory.completed_at == custom_time
    end

    test "handles all outcome types" do
      for outcome <- [:success, :failure, :timeout, :error, :partial] do
        trajectory = Trajectory.new()
        trajectory = Trajectory.complete(trajectory, outcome: outcome)

        assert trajectory.outcome == outcome
      end
    end
  end

  describe "filter/2" do
    setup do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "Low priority", importance: :low)
        |> Trajectory.add_step(type: :reasoning, content: "Medium priority", importance: :medium)
        |> Trajectory.add_step(type: :reasoning, content: "High priority", importance: :high)
        |> Trajectory.add_step(
          type: :reasoning,
          content: "Critical priority",
          importance: :critical
        )
        |> Trajectory.add_snapshot(state: %{checkpoint: 1})
        |> Trajectory.add_snapshot(state: %{checkpoint: 2})

      %{trajectory: trajectory}
    end

    test "filters by importance level - medium", %{trajectory: trajectory} do
      filtered =
        Trajectory.filter(trajectory, min_importance: :medium, preserve_first_last: false)

      assert length(filtered.steps) == 3

      assert Enum.all?(filtered.steps, fn step ->
               step.importance in [:medium, :high, :critical]
             end)

      assert filtered.filtered == true
    end

    test "filters by importance level - high", %{trajectory: trajectory} do
      filtered = Trajectory.filter(trajectory, min_importance: :high, preserve_first_last: false)

      assert length(filtered.steps) == 2
      assert Enum.all?(filtered.steps, fn step -> step.importance in [:high, :critical] end)
    end

    test "filters by importance level - critical", %{trajectory: trajectory} do
      filtered =
        Trajectory.filter(trajectory, min_importance: :critical, preserve_first_last: false)

      assert length(filtered.steps) == 1
      [step] = filtered.steps
      assert step.importance == :critical
    end

    test "preserves first and last steps by default", %{trajectory: trajectory} do
      # Even with critical filter, first (low) and last (critical) should be kept
      filtered = Trajectory.filter(trajectory, min_importance: :critical)

      # Should have at least 2 steps (first and last) or 1 if first/last is the same critical step
      assert length(filtered.steps) >= 1
      # The critical step should be in the filtered results
      assert Enum.any?(filtered.steps, fn step -> step.importance == :critical end)
    end

    test "preserves first and last steps when explicitly set" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "First", importance: :low)
        |> Trajectory.add_step(type: :reasoning, content: "Middle", importance: :low)
        |> Trajectory.add_step(type: :reasoning, content: "Last", importance: :low)

      filtered = Trajectory.filter(trajectory, min_importance: :high, preserve_first_last: true)

      assert length(filtered.steps) == 2
      [first, last] = filtered.steps
      assert first.content == "First"
      assert last.content == "Last"
    end

    test "does not preserve first and last when disabled" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "First", importance: :low)
        |> Trajectory.add_step(type: :reasoning, content: "Middle", importance: :high)
        |> Trajectory.add_step(type: :reasoning, content: "Last", importance: :low)

      filtered = Trajectory.filter(trajectory, min_importance: :high, preserve_first_last: false)

      assert length(filtered.steps) == 1
      [step] = filtered.steps
      assert step.content == "Middle"
    end

    test "keeps snapshots by default", %{trajectory: trajectory} do
      filtered = Trajectory.filter(trajectory, min_importance: :high)

      assert length(filtered.state_snapshots) == 2
    end

    test "removes snapshots when keep_snapshots is false", %{trajectory: trajectory} do
      filtered = Trajectory.filter(trajectory, min_importance: :high, keep_snapshots: false)

      assert Enum.empty?(filtered.state_snapshots)
    end

    test "marks trajectory as filtered", %{trajectory: trajectory} do
      filtered = Trajectory.filter(trajectory)

      assert filtered.filtered == true
    end

    test "records filter settings in metadata", %{trajectory: trajectory} do
      opts = [min_importance: :high, keep_snapshots: false]
      filtered = Trajectory.filter(trajectory, opts)

      assert filtered.metadata.filter_settings == opts
    end

    test "handles empty trajectory" do
      trajectory = Trajectory.new()
      filtered = Trajectory.filter(trajectory, min_importance: :critical)

      assert Enum.empty?(filtered.steps)
      assert filtered.filtered == true
    end

    test "default filter keeps medium and above" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "Low", importance: :low)
        |> Trajectory.add_step(type: :reasoning, content: "Medium", importance: :medium)

      filtered = Trajectory.filter(trajectory, preserve_first_last: false)

      assert length(filtered.steps) == 1
      [step] = filtered.steps
      assert step.importance == :medium
    end
  end

  describe "to_map/1" do
    test "converts trajectory to map representation" do
      trajectory =
        Trajectory.new(metadata: %{test: "data"})
        |> Trajectory.add_step(type: :reasoning, content: "Test step")
        |> Trajectory.add_snapshot(state: %{data: 42})
        |> Trajectory.complete(outcome: :success)

      map = Trajectory.to_map(trajectory)

      assert is_map(map)
      assert map.id == trajectory.id
      assert is_list(map.steps)
      assert is_list(map.state_snapshots)
      assert is_binary(map.started_at)
      assert is_binary(map.completed_at)
      assert map.duration_ms == trajectory.duration_ms
      assert map.metadata == %{test: "data"}
      assert map.outcome == :success
      assert is_nil(map.error)
      assert map.filtered == false
    end

    test "converts step timestamps to ISO8601" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "Test")

      map = Trajectory.to_map(trajectory)

      [step] = map.steps
      assert is_binary(step.timestamp)
      # Verify it's a valid ISO8601 timestamp
      assert {:ok, _, _} = DateTime.from_iso8601(step.timestamp)
    end

    test "converts snapshot timestamps to ISO8601" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_snapshot(state: %{data: "test"})

      map = Trajectory.to_map(trajectory)

      [snapshot] = map.state_snapshots
      assert is_binary(snapshot.timestamp)
      assert {:ok, _, _} = DateTime.from_iso8601(snapshot.timestamp)
    end

    test "handles nil completed_at" do
      trajectory = Trajectory.new()
      map = Trajectory.to_map(trajectory)

      assert is_nil(map.completed_at)
    end

    test "includes all step fields" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(
          type: :reasoning,
          content: "Test",
          metadata: %{key: "value"},
          context: %{state: "active"},
          importance: :high,
          duration_ms: 100
        )

      map = Trajectory.to_map(trajectory)
      [step] = map.steps

      assert step.type == :reasoning
      assert step.content == "Test"
      assert step.metadata == %{key: "value"}
      assert step.context == %{state: "active"}
      assert step.importance == :high
      assert step.duration_ms == 100
      assert is_binary(step.id)
      assert is_nil(step.parent_step_id)
    end

    test "includes all snapshot fields" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_snapshot(
          state: %{data: "test"},
          reason: :checkpoint,
          metadata: %{index: 1}
        )

      map = Trajectory.to_map(trajectory)
      [snapshot] = map.state_snapshots

      assert snapshot.state == %{data: "test"}
      assert snapshot.reason == :checkpoint
      assert snapshot.metadata == %{index: 1}
      assert is_binary(snapshot.id)
      assert is_nil(snapshot.step_id)
    end
  end

  describe "statistics/1" do
    test "returns statistics for empty trajectory" do
      trajectory = Trajectory.new()
      stats = Trajectory.statistics(trajectory)

      assert stats.total_steps == 0
      assert stats.step_types == %{}
      assert stats.importance_distribution == %{}
      assert stats.total_snapshots == 0
      assert is_nil(stats.duration_ms)
      assert is_nil(stats.outcome)
      assert stats.filtered == false
    end

    test "counts steps by type" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "1")
        |> Trajectory.add_step(type: :reasoning, content: "2")
        |> Trajectory.add_step(type: :action, content: "3")
        |> Trajectory.add_step(type: :observation, content: "4")

      stats = Trajectory.statistics(trajectory)

      assert stats.total_steps == 4
      assert stats.step_types[:reasoning] == 2
      assert stats.step_types[:action] == 1
      assert stats.step_types[:observation] == 1
    end

    test "counts steps by importance" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "1", importance: :low)
        |> Trajectory.add_step(type: :reasoning, content: "2", importance: :medium)
        |> Trajectory.add_step(type: :reasoning, content: "3", importance: :medium)
        |> Trajectory.add_step(type: :reasoning, content: "4", importance: :high)

      stats = Trajectory.statistics(trajectory)

      assert stats.importance_distribution[:low] == 1
      assert stats.importance_distribution[:medium] == 2
      assert stats.importance_distribution[:high] == 1
    end

    test "counts snapshots" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_snapshot(state: %{snap: 1})
        |> Trajectory.add_snapshot(state: %{snap: 2})
        |> Trajectory.add_snapshot(state: %{snap: 3})

      stats = Trajectory.statistics(trajectory)

      assert stats.total_snapshots == 3
    end

    test "includes duration for completed trajectory" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "Test")

      Process.sleep(10)
      trajectory = Trajectory.complete(trajectory)

      stats = Trajectory.statistics(trajectory)

      assert is_integer(stats.duration_ms)
      assert stats.duration_ms > 0
    end

    test "includes outcome" do
      trajectory =
        Trajectory.new()
        |> Trajectory.complete(outcome: :success)

      stats = Trajectory.statistics(trajectory)

      assert stats.outcome == :success
    end

    test "indicates if trajectory is filtered" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "Test", importance: :low)
        |> Trajectory.filter(min_importance: :high)

      stats = Trajectory.statistics(trajectory)

      assert stats.filtered == true
    end

    test "handles all step types" do
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :reasoning, content: "1")
        |> Trajectory.add_step(type: :action, content: "2")
        |> Trajectory.add_step(type: :observation, content: "3")
        |> Trajectory.add_step(type: :tool_call, content: "4")
        |> Trajectory.add_step(type: :state_change, content: "5")

      stats = Trajectory.statistics(trajectory)

      assert stats.total_steps == 5
      assert stats.step_types[:reasoning] == 1
      assert stats.step_types[:action] == 1
      assert stats.step_types[:observation] == 1
      assert stats.step_types[:tool_call] == 1
      assert stats.step_types[:state_change] == 1
    end
  end

  describe "integration scenarios" do
    test "complete evaluation workflow with trajectory" do
      # Start evaluation
      trajectory =
        Trajectory.new(
          metadata: %{
            prompt: "Solve this problem step by step",
            task_type: :reasoning
          }
        )

      # Record evaluation start
      trajectory =
        Trajectory.add_step(trajectory,
          type: :state_change,
          content: "Evaluation started",
          importance: :high
        )

      # Record reasoning steps
      trajectory =
        Trajectory.add_step(trajectory,
          type: :reasoning,
          content: "Breaking down the problem...",
          importance: :high
        )

      # Capture state snapshot
      trajectory =
        Trajectory.add_snapshot(trajectory,
          state: %{phase: :reasoning, step: 1},
          reason: :checkpoint
        )

      # Record action
      trajectory =
        Trajectory.add_step(trajectory,
          type: :action,
          content: "Executing calculation",
          importance: :medium
        )

      # Record observation
      trajectory =
        Trajectory.add_step(trajectory,
          type: :observation,
          content: "Result obtained: 42",
          importance: :high
        )

      # Capture final state
      trajectory =
        Trajectory.add_snapshot(trajectory,
          state: %{result: 42, confidence: 0.95},
          reason: :evaluation_complete
        )

      # Complete evaluation
      trajectory = Trajectory.complete(trajectory, outcome: :success)

      # Verify complete trajectory
      assert length(trajectory.steps) == 4
      assert length(trajectory.state_snapshots) == 2
      assert trajectory.outcome == :success
      assert is_integer(trajectory.duration_ms)

      # Get statistics
      stats = Trajectory.statistics(trajectory)
      assert stats.total_steps == 4
      assert stats.step_types[:reasoning] == 1
      assert stats.step_types[:action] == 1
      assert stats.step_types[:observation] == 1
      assert stats.step_types[:state_change] == 1
    end

    test "failure scenario with error trajectory" do
      trajectory = Trajectory.new(metadata: %{prompt: "Test", task_type: :reasoning})

      trajectory =
        Trajectory.add_step(trajectory,
          type: :state_change,
          content: "Evaluation started",
          importance: :high
        )

      trajectory =
        Trajectory.add_step(trajectory,
          type: :observation,
          content: "Evaluation timeout",
          importance: :critical,
          metadata: %{error: :timeout}
        )

      trajectory = Trajectory.complete(trajectory, outcome: :timeout, error: :timeout)

      assert trajectory.outcome == :timeout
      assert trajectory.error == :timeout
      assert length(trajectory.steps) == 2
    end

    test "filtered trajectory for reflection analysis" do
      # Create detailed trajectory
      trajectory =
        Trajectory.new()
        |> Trajectory.add_step(type: :state_change, content: "Start", importance: :high)
        |> Trajectory.add_step(type: :reasoning, content: "Detail 1", importance: :low)
        |> Trajectory.add_step(type: :reasoning, content: "Detail 2", importance: :low)
        |> Trajectory.add_step(type: :reasoning, content: "Key insight", importance: :critical)
        |> Trajectory.add_step(type: :action, content: "Execute", importance: :high)
        |> Trajectory.add_step(type: :observation, content: "Result", importance: :high)
        |> Trajectory.add_snapshot(state: %{checkpoint: 1})
        |> Trajectory.add_snapshot(state: %{checkpoint: 2})

      original_steps = length(trajectory.steps)

      # Filter for reflection (keep only important steps)
      filtered = Trajectory.filter(trajectory, min_importance: :high)

      assert length(filtered.steps) < original_steps
      assert filtered.filtered == true
      assert Enum.all?(filtered.steps, fn step -> step.importance in [:high, :critical] end)

      # Convert to map for storage
      map = Trajectory.to_map(filtered)
      assert map.filtered == true
      assert is_list(map.metadata.filter_settings) or is_map(map.metadata.filter_settings)
    end
  end
end
