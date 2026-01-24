defmodule Jido.AI.Accuracy.CalibrationGateTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{CalibrationGate, Candidate, ConfidenceEstimate, RoutingResult}

  @moduletag :capture_log

  describe "new/1" do
    test "creates gate with default values" do
      assert {:ok, gate} = CalibrationGate.new(%{})

      assert gate.high_threshold == 0.7
      assert gate.low_threshold == 0.4
      assert gate.medium_action == :with_verification
      assert gate.low_action == :abstain
      assert gate.emit_telemetry == true
    end

    test "creates gate with custom thresholds" do
      assert {:ok, gate} =
               CalibrationGate.new(%{
                 high_threshold: 0.8,
                 low_threshold: 0.5
               })

      assert gate.high_threshold == 0.8
      assert gate.low_threshold == 0.5
    end

    test "creates gate with custom actions" do
      assert {:ok, gate} =
               CalibrationGate.new(%{
                 medium_action: :with_citations,
                 low_action: :escalate
               })

      assert gate.medium_action == :with_citations
      assert gate.low_action == :escalate
    end

    test "creates gate with telemetry disabled" do
      assert {:ok, gate} = CalibrationGate.new(%{emit_telemetry: false})

      assert gate.emit_telemetry == false
    end

    test "returns error for invalid thresholds (high <= low)" do
      assert {:error, :invalid_thresholds} =
               CalibrationGate.new(%{
                 high_threshold: 0.3,
                 low_threshold: 0.5
               })

      assert {:error, :invalid_thresholds} =
               CalibrationGate.new(%{
                 high_threshold: 0.5,
                 low_threshold: 0.5
               })
    end

    test "returns error for invalid action" do
      assert {:error, :invalid_action} =
               CalibrationGate.new(%{
                 medium_action: :invalid_action
               })

      assert {:error, :invalid_action} =
               CalibrationGate.new(%{
                 low_action: :invalid_action
               })
    end
  end

  describe "new!/1" do
    test "creates gate with valid attributes" do
      gate = CalibrationGate.new!(%{})
      assert gate.high_threshold == 0.7
    end

    test "raises for invalid attributes" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        CalibrationGate.new!(%{
          high_threshold: 0.3,
          low_threshold: 0.5
        })
      end
    end
  end

  describe "route/3" do
    setup do
      gate = CalibrationGate.new!(%{})
      candidate = Candidate.new!(%{content: "The answer is 42"})
      {:ok, gate: gate, candidate: candidate}
    end

    test "routes high confidence to direct action", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.85, method: :attention})

      assert {:ok, result} = CalibrationGate.route(context.gate, context.candidate, estimate)

      assert result.action == :direct
      assert result.confidence_level == :high
      assert result.original_score == 0.85
      assert result.candidate.content == "The answer is 42"
      assert RoutingResult.direct?(result)
    end

    test "routes medium confidence to verification action", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :attention})

      assert {:ok, result} = CalibrationGate.route(context.gate, context.candidate, estimate)

      assert result.action == :with_verification
      assert result.confidence_level == :medium
      assert result.original_score == 0.5
      assert RoutingResult.with_verification?(result)
    end

    test "routes low confidence to abstain action", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.3, method: :attention})

      assert {:ok, result} = CalibrationGate.route(context.gate, context.candidate, estimate)

      assert result.action == :abstain
      assert result.confidence_level == :low
      assert result.original_score == 0.3
      assert RoutingResult.abstained?(result)
    end

    test "adds verification suffix for medium confidence", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :attention})

      assert {:ok, result} = CalibrationGate.route(context.gate, context.candidate, estimate)

      assert String.contains?(
               result.candidate.content,
               "[Confidence: Medium] Please verify this information"
             )
    end

    test "generates abstention message for low confidence", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.2, method: :attention})

      assert {:ok, result} = CalibrationGate.route(context.gate, context.candidate, estimate)

      assert String.contains?(result.candidate.content, "not confident enough")
      assert String.contains?(result.candidate.content, "definitive answer")
      assert result.candidate.metadata.abstained == true
    end

    test "includes reasoning in result", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.85, method: :attention})

      assert {:ok, result} = CalibrationGate.route(context.gate, context.candidate, estimate)

      assert is_binary(result.reasoning)
      assert String.contains?(result.reasoning, "High confidence")
    end

    test "includes metadata with thresholds", context do
      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :attention})

      assert {:ok, result} = CalibrationGate.route(context.gate, context.candidate, estimate)

      assert result.metadata.high_threshold == 0.7
      assert result.metadata.low_threshold == 0.4
    end
  end

  describe "route/3 with custom thresholds" do
    test "respects custom high threshold" do
      gate = CalibrationGate.new!(%{high_threshold: 0.8})
      candidate = Candidate.new!(%{content: "Test"})

      # 0.75 is normally high, but with threshold 0.8 it's medium
      estimate = ConfidenceEstimate.new!(%{score: 0.75, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert result.action == :with_verification
      assert result.confidence_level == :medium
    end

    test "respects custom low threshold" do
      gate = CalibrationGate.new!(%{low_threshold: 0.5})
      candidate = Candidate.new!(%{content: "Test"})

      # 0.45 is normally medium, but with threshold 0.5 it's low
      estimate = ConfidenceEstimate.new!(%{score: 0.45, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert result.action == :abstain
      assert result.confidence_level == :low
    end
  end

  describe "route/3 with custom actions" do
    test "uses custom medium action" do
      gate = CalibrationGate.new!(%{medium_action: :with_citations})
      candidate = Candidate.new!(%{content: "Test"})

      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert result.action == :with_citations

      assert String.contains?(
               result.candidate.content,
               "[Confidence: Medium] Consider verifying"
             )
    end

    test "uses custom low action" do
      gate = CalibrationGate.new!(%{low_action: :escalate})
      candidate = Candidate.new!(%{content: "Test"})

      estimate = ConfidenceEstimate.new!(%{score: 0.3, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert result.action == :escalate
      assert String.contains?(result.candidate.content, "escalated")
      assert result.candidate.metadata.escalated == true
    end
  end

  describe "route/3 with with_citations action" do
    test "adds citation suffix" do
      gate = CalibrationGate.new!(%{medium_action: :with_citations})
      candidate = Candidate.new!(%{content: "Test content"})

      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert String.contains?(
               result.candidate.content,
               "[Confidence: Medium] Consider verifying"
             )
    end
  end

  describe "route/3 with escalate action" do
    test "generates escalation message" do
      gate = CalibrationGate.new!(%{low_action: :escalate})
      candidate = Candidate.new!(%{content: "Test"})

      estimate = ConfidenceEstimate.new!(%{score: 0.2, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert String.contains?(result.candidate.content, "escalated")
      assert result.candidate.metadata.escalated == true
    end
  end

  describe "route/3 with nil content" do
    test "handles candidate with nil content" do
      gate = CalibrationGate.new!(%{})
      candidate = %Candidate{content: nil}

      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      # Should not crash, candidate remains unchanged
      assert result.candidate.content == nil
    end
  end

  describe "should_route?/2" do
    setup do
      {:ok, gate: CalibrationGate.new!(%{})}
    end

    test "returns :direct for high confidence", context do
      assert {:ok, :direct} = CalibrationGate.should_route?(context.gate, 0.8)
      assert {:ok, :direct} = CalibrationGate.should_route?(context.gate, 0.7)
    end

    test "returns medium action for medium confidence", context do
      assert {:ok, :with_verification} = CalibrationGate.should_route?(context.gate, 0.5)
      assert {:ok, :with_verification} = CalibrationGate.should_route?(context.gate, 0.4)
    end

    test "returns low action for low confidence", context do
      assert {:ok, :abstain} = CalibrationGate.should_route?(context.gate, 0.3)
      assert {:ok, :abstain} = CalibrationGate.should_route?(context.gate, 0.0)
    end

    test "respects custom thresholds" do
      gate = CalibrationGate.new!(%{high_threshold: 0.8, low_threshold: 0.5})

      assert {:ok, :direct} = CalibrationGate.should_route?(gate, 0.85)
      assert {:ok, :with_verification} = CalibrationGate.should_route?(gate, 0.7)
      assert {:ok, :abstain} = CalibrationGate.should_route?(gate, 0.3)
    end
  end

  describe "confidence_level/2" do
    setup do
      {:ok, gate: CalibrationGate.new!(%{})}
    end

    test "returns :high for high confidence", %{gate: gate} do
      assert :high = CalibrationGate.confidence_level(gate, 0.8)
      assert :high = CalibrationGate.confidence_level(gate, 0.7)
    end

    test "returns :medium for medium confidence", %{gate: gate} do
      assert :medium = CalibrationGate.confidence_level(gate, 0.5)
      assert :medium = CalibrationGate.confidence_level(gate, 0.4)
    end

    test "returns :low for low confidence", %{gate: gate} do
      assert :low = CalibrationGate.confidence_level(gate, 0.3)
      assert :low = CalibrationGate.confidence_level(gate, 0.0)
    end

    test "respects custom thresholds" do
      gate = CalibrationGate.new!(%{high_threshold: 0.8, low_threshold: 0.5})

      assert :high = CalibrationGate.confidence_level(gate, 0.85)
      assert :medium = CalibrationGate.confidence_level(gate, 0.7)
      assert :low = CalibrationGate.confidence_level(gate, 0.3)
    end
  end

  describe "boundary conditions" do
    test "exactly at high threshold is high confidence" do
      gate = CalibrationGate.new!(%{})
      candidate = Candidate.new!(%{content: "Test"})

      estimate = ConfidenceEstimate.new!(%{score: 0.7, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert result.confidence_level == :high
      assert result.action == :direct
    end

    test "exactly at low threshold is medium confidence" do
      gate = CalibrationGate.new!(%{})
      candidate = Candidate.new!(%{content: "Test"})

      estimate = ConfidenceEstimate.new!(%{score: 0.4, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert result.confidence_level == :medium
      assert result.action == :with_verification
    end

    test "just below high threshold is medium confidence" do
      gate = CalibrationGate.new!(%{})
      candidate = Candidate.new!(%{content: "Test"})

      estimate = ConfidenceEstimate.new!(%{score: 0.699, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert result.confidence_level == :medium
    end

    test "just below low threshold is low confidence" do
      gate = CalibrationGate.new!(%{})
      candidate = Candidate.new!(%{content: "Test"})

      estimate = ConfidenceEstimate.new!(%{score: 0.399, method: :test})

      assert {:ok, result} = CalibrationGate.route(gate, candidate, estimate)

      assert result.confidence_level == :low
    end
  end

  describe "telemetry" do
    test "emits telemetry event when routing" do
      gate = CalibrationGate.new!(%{})
      candidate = Candidate.new!(%{content: "Test"})
      estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})

      # Attach a handler to capture the event
      handler_id =
        :telemetry.attach(
          "test-calibration-gate",
          [:jido, :accuracy, :calibration, :route],
          fn event, measurements, metadata, _ ->
            send(self(), {:telemetry_event, event, measurements, metadata})
          end,
          nil
        )

      # Ensure handler is detached after test
      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, _result} = CalibrationGate.route(gate, candidate, estimate)

      assert_receive {:telemetry_event, [:jido, :accuracy, :calibration, :route], measurements, metadata}

      assert is_number(measurements.duration)
      assert metadata.action == :direct
      assert metadata.confidence_level == :high
      assert metadata.score == 0.8
    end

    test "does not emit telemetry when disabled" do
      gate = CalibrationGate.new!(%{emit_telemetry: false})
      candidate = Candidate.new!(%{content: "Test"})
      estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})

      # Attach a handler
      handler_id =
        :telemetry.attach(
          "test-calibration-gate-disabled",
          [:jido, :accuracy, :calibration, :route],
          fn _, _, _, _ -> send(self(), :should_not_receive) end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, _result} = CalibrationGate.route(gate, candidate, estimate)

      refute_receive _
    end
  end
end
