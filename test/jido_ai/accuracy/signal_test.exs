defmodule Jido.AI.Accuracy.SignalTest do
  @moduledoc """
  Tests for the Accuracy Signals.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Signal

  describe "Signal.Result" do
    test "creates a new result signal" do
      signal = Signal.Result.new!(%{
        call_id: "call_123",
        query: "What is 2+2?",
        answer: "4",
        confidence: 0.95
      })

      assert signal.data.call_id == "call_123"
      assert signal.data.query == "What is 2+2?"
      assert signal.data.answer == "4"
      assert signal.data.confidence == 0.95
    end

    test "creates result signal from pipeline result" do
      result = %{
        answer: "4",
        confidence: 0.95,
        metadata: %{
          num_candidates: 3,
          input_tokens: 100,
          output_tokens: 50,
          verification_score: 0.9,
          calibration_action: :direct,
          calibration_level: :high
        }
      }

      signal = Signal.Result.from_pipeline_result("call_123", "What is 2+2?", :fast, {:ok, result})

      assert signal.data.call_id == "call_123"
      assert signal.data.query == "What is 2+2?"
      assert signal.data.preset == :fast
      assert signal.data.answer == "4"
      assert signal.data.confidence == 0.95
      assert signal.data.candidates == 3

      assert signal.data.metadata.input_tokens == 100
      assert signal.data.metadata.output_tokens == 50
      assert signal.data.metadata.total_tokens == 150
      assert signal.data.metadata.verification_score == 0.9
      assert signal.data.metadata.calibration_action == :direct
      assert signal.data.metadata.calibration_level == :high
    end

    test "creates result signal with duration" do
      result = %{answer: "4", confidence: 0.95}
      start_time = System.monotonic_time(:millisecond) - 500

      Process.sleep(10)
      signal = Signal.Result.from_pipeline_result("call_123", "What is 2+2?", :fast, {:ok, result}, start_time)

      assert signal.data.duration_ms >= 500
    end

    test "creates error signal from pipeline error" do
      error_result = {:error, :timeout}

      signal = Signal.Result.from_pipeline_result("call_123", "What is 2+2?", :fast, error_result)

      assert signal.type == "accuracy.error"
      assert signal.data.call_id == "call_123"
      assert signal.data.query == "What is 2+2?"
      assert signal.data.preset == :fast
      assert signal.data.error == :timeout
    end

    test "handles result without metadata" do
      result = %{answer: "4"}

      signal = Signal.Result.from_pipeline_result("call_123", "What is 2+2?", :balanced, {:ok, result})

      assert signal.data.answer == "4"
      assert signal.data.metadata == %{}
    end

    test "handles result with partial metadata" do
      result = %{
        answer: "4",
        metadata: %{num_candidates: 3}
      }

      signal = Signal.Result.from_pipeline_result("call_123", "What is 2+2?", :balanced, {:ok, result})

      assert signal.data.metadata.num_candidates == 3
      refute Map.has_key?(signal.data.metadata, :input_tokens)
    end
  end

  describe "Signal.Error" do
    test "creates a new error signal" do
      signal = Signal.Error.new!(%{
        call_id: "call_123",
        query: "What is 2+2?",
        error: :timeout
      })

      assert signal.data.call_id == "call_123"
      assert signal.data.query == "What is 2+2?"
      assert signal.data.error == :timeout
    end

    test "creates error signal with stage" do
      signal = Signal.Error.new!(%{
        call_id: "call_123",
        query: "What is 2+2?",
        error: :generation_failed,
        stage: :generation
      })

      assert signal.data.stage == :generation
    end

    test "creates error signal with message" do
      signal = Signal.Error.new!(%{
        call_id: "call_123",
        query: "What is 2+2?",
        error: :timeout,
        message: "Pipeline timed out after 30s"
      })

      assert signal.data.message == "Pipeline timed out after 30s"
    end

    test "creates error signal from exception tuple" do
      exception = {%RuntimeError{message: "Test error"}, []}

      signal = Signal.Error.from_exception("call_123", "What is 2+2?", :balanced, exception, :generation)

      assert signal.data.call_id == "call_123"
      assert signal.data.query == "What is 2+2?"
      assert signal.data.preset == :balanced
      assert signal.data.stage == :generation
      assert signal.data.message == "Test error"
    end

    test "creates error signal from atom reason" do
      signal = Signal.Error.from_exception("call_123", "What is 2+2?", :fast, :timeout)

      assert signal.data.error == :timeout
      assert signal.data.message == ":timeout"
    end

    test "creates error signal from string reason" do
      signal = Signal.Error.from_exception("call_123", "What is 2+2?", :fast, "custom error")

      assert signal.data.error == "custom error"
      assert signal.data.message == "custom error"
    end

    test "creates error signal from complex reason" do
      reason = {:error, :generator_failed, [:context1, :context2]}

      signal = Signal.Error.from_exception("call_123", "What is 2+2?", :fast, reason)

      assert signal.data.error == reason
      assert is_binary(signal.data.message)
      assert signal.data.message =~ "{:error"
    end
  end

  describe "Signal Types" do
    test "result signal has correct type" do
      signal = Signal.Result.new!(%{
        call_id: "call_123",
        query: "What is 2+2?"
      })

      assert signal.type == "accuracy.result"
    end

    test "error signal has correct type" do
      signal = Signal.Error.new!(%{
        call_id: "call_123",
        query: "What is 2+2?",
        error: :timeout
      })

      assert signal.type == "accuracy.error"
    end
  end
end
