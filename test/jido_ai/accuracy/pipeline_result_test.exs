defmodule Jido.AI.Accuracy.PipelineResultTest do
  @moduledoc """
  Tests for PipelineResult.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.PipelineResult

  describe "new/1" do
    test "creates result with valid attributes" do
      assert {:ok, result} =
               PipelineResult.new(%{
                 answer: "42",
                 confidence: 0.9,
                 action: :direct
               })

      assert result.answer == "42"
      assert result.confidence == 0.9
      assert result.action == :direct
    end

    test "creates result with default confidence" do
      assert {:ok, result} =
               PipelineResult.new(%{
                 answer: "42",
                 action: :direct
               })

      assert result.confidence == 0.5
    end

    test "creates result with default action" do
      assert {:ok, result} =
               PipelineResult.new(%{
                 answer: "42",
                 confidence: 0.8
               })

      assert result.action == :direct
    end

    test "creates result with empty trace and metadata" do
      assert {:ok, result} =
               PipelineResult.new(%{
                 answer: "42",
                 confidence: 0.8,
                 action: :direct
               })

      assert result.trace == []
      assert result.metadata == %{}
    end

    test "returns error for invalid confidence" do
      assert {:error, :invalid_confidence} =
               PipelineResult.new(%{
                 answer: "42",
                 confidence: 1.5,
                 action: :direct
               })

      assert {:error, :invalid_confidence} =
               PipelineResult.new(%{
                 answer: "42",
                 confidence: -0.1,
                 action: :direct
               })
    end

    test "returns error for invalid action" do
      assert {:error, :invalid_action} =
               PipelineResult.new(%{
                 answer: "42",
                 confidence: 0.8,
                 action: :invalid_action
               })
    end
  end

  describe "new!/1" do
    test "creates result or raises" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct
        })

      assert result.answer == "42"

      assert_raise ArgumentError, ~r/Invalid PipelineResult/, fn ->
        PipelineResult.new!(%{confidence: 2.0, action: :direct})
      end
    end
  end

  describe "success?/1" do
    test "returns true for successful result with answer" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct
        })

      assert PipelineResult.success?(result)
    end

    test "returns true for abstained result" do
      result =
        PipelineResult.new!(%{
          answer: nil,
          confidence: 0.2,
          action: :abstain
        })

      assert PipelineResult.success?(result)
    end

    test "returns false for result without answer and not abstained" do
      result =
        PipelineResult.new!(%{
          answer: nil,
          confidence: 0.5,
          action: :direct
        })

      refute PipelineResult.success?(result)
    end
  end

  describe "abstained?/1" do
    test "returns true when action is abstain" do
      result =
        PipelineResult.new!(%{
          answer: nil,
          confidence: 0.2,
          action: :abstain
        })

      assert PipelineResult.abstained?(result)
    end

    test "returns false for other actions" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct
        })

      refute PipelineResult.abstained?(result)
    end
  end

  describe "direct?/1" do
    test "returns true when action is direct" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct
        })

      assert PipelineResult.direct?(result)
    end

    test "returns false for other actions" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.5,
          action: :with_verification
        })

      refute PipelineResult.direct?(result)
    end
  end

  describe "total_duration_ms/1" do
    test "calculates total duration from trace entries" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct,
          trace: [
            PipelineResult.trace_entry(:stage1, :ok, 100, %{}),
            PipelineResult.trace_entry(:stage2, :ok, 200, %{}),
            PipelineResult.trace_entry(:stage3, :ok, 50, %{})
          ]
        })

      assert PipelineResult.total_duration_ms(result) == 350
    end

    test "handles empty trace" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct,
          trace: []
        })

      assert PipelineResult.total_duration_ms(result) == 0
    end

    test "handles trace entries without duration_ms" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct,
          trace: [
            %{stage: :stage1, status: :ok},
            PipelineResult.trace_entry(:stage2, :ok, 100, %{})
          ]
        })

      assert PipelineResult.total_duration_ms(result) == 100
    end
  end

  describe "stage_trace/2" do
    test "returns trace entry for specific stage" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct,
          trace: [
            PipelineResult.trace_entry(:stage1, :ok, 100, %{data: 1}),
            PipelineResult.trace_entry(:stage2, :ok, 200, %{data: 2})
          ]
        })

      trace = PipelineResult.stage_trace(result, :stage1)
      assert trace.stage == :stage1
      assert trace.result.data == 1
    end

    test "returns nil for non-existent stage" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct,
          trace: [
            PipelineResult.trace_entry(:stage1, :ok, 100, %{})
          ]
        })

      refute PipelineResult.stage_trace(result, :stage2)
    end
  end

  describe "error_traces/1" do
    test "returns only error trace entries" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct,
          trace: [
            PipelineResult.trace_entry(:stage1, :ok, 100, %{}),
            PipelineResult.trace_entry(:stage2, :error, 50, :error_reason),
            PipelineResult.trace_entry(:stage3, :ok, 75, %{}),
            PipelineResult.trace_entry(:stage4, :error, 25, :another_error)
          ]
        })

      errors = PipelineResult.error_traces(result)
      assert length(errors) == 2
      assert Enum.all?(errors, &(&1.status == :error))
    end

    test "returns empty list when no errors" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct,
          trace: [
            PipelineResult.trace_entry(:stage1, :ok, 100, %{}),
            PipelineResult.trace_entry(:stage2, :ok, 200, %{})
          ]
        })

      assert PipelineResult.error_traces(result) == []
    end
  end

  describe "add_trace/2" do
    test "adds trace entry to result" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct
        })

      entry = PipelineResult.trace_entry(:new_stage, :ok, 50, %{})
      updated = PipelineResult.add_trace(result, entry)

      assert length(updated.trace) == 1
      assert List.last(updated.trace) == entry
    end
  end

  describe "put_metadata/3" do
    test "adds metadata key-value" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct
        })

      updated = PipelineResult.put_metadata(result, :custom_key, :custom_value)
      assert updated.metadata.custom_key == :custom_value
    end
  end

  describe "merge_metadata/2" do
    test "merges metadata map" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct,
          metadata: %{existing: :value}
        })

      updated = PipelineResult.merge_metadata(result, %{new: :value, existing: :updated})
      assert updated.metadata.existing == :updated
      assert updated.metadata.new == :value
    end
  end

  describe "trace_entry/4" do
    test "creates ok trace entry with result" do
      entry = PipelineResult.trace_entry(:test_stage, :ok, 100, %{data: "test"})

      assert entry.stage == :test_stage
      assert entry.status == :ok
      assert entry.duration_ms == 100
      assert entry.result.data == "test"
      assert entry.error == nil
    end

    test "creates error trace entry with reason" do
      entry = PipelineResult.trace_entry(:test_stage, :error, 50, :error_reason)

      assert entry.stage == :test_stage
      assert entry.status == :error
      assert entry.duration_ms == 50
      assert entry.result == nil
      assert entry.error == :error_reason
    end

    test "creates skipped trace entry" do
      entry = PipelineResult.trace_entry(:test_stage, :skipped, 0, :not_needed)

      assert entry.stage == :test_stage
      assert entry.status == :skipped
      assert entry.duration_ms == 0
      assert entry.result == nil
      assert entry.error == nil
    end
  end

  describe "to_map/1" do
    test "converts result to map" do
      result =
        PipelineResult.new!(%{
          answer: "42",
          confidence: 0.8,
          action: :direct,
          trace: [PipelineResult.trace_entry(:stage1, :ok, 100, %{})]
        })

      map = PipelineResult.to_map(result)

      assert map.answer == "42"
      assert map.confidence == 0.8
      assert map.action == :direct
      assert map.success? == true
      assert map.abstained? == false
      assert is_integer(map.total_duration_ms)
    end
  end
end
