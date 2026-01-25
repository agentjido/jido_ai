defmodule Jido.AI.Accuracy.VerifierTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, VerificationResult, Verifier}

  # Mock verifier implementation for testing
  defmodule MockVerifier do
    @behaviour Verifier

    @impl true
    def verify(candidate, _context) do
      score = String.length(candidate.content || "") / 100.0

      result =
        VerificationResult.new!(%{
          candidate_id: candidate.id,
          score: score,
          confidence: 0.9
        })

      {:ok, result}
    end

    @impl true
    def verify_batch(candidates, context) do
      results =
        Enum.map(candidates, fn candidate ->
          {:ok, result} = verify(candidate, context)
          result
        end)

      {:ok, results}
    end

    @impl true
    def supports_streaming?, do: true
  end

  # Minimal mock verifier (only required callbacks)
  defmodule MinimalVerifier do
    @behaviour Verifier

    @impl true
    def verify(candidate, _context) do
      result =
        VerificationResult.new!(%{
          candidate_id: candidate.id,
          score: 0.5
        })

      {:ok, result}
    end

    @impl true
    def verify_batch(candidates, context) do
      results =
        Enum.map(candidates, fn c ->
          {:ok, r} = verify(c, context)
          r
        end)

      {:ok, results}
    end
  end

  # Error-raising mock verifier
  defmodule ErrorVerifier do
    @behaviour Verifier

    @impl true
    def verify(_candidate, _context) do
      {:error, :verification_failed}
    end

    @impl true
    def verify_batch(_candidates, _context) do
      {:error, :batch_failed}
    end
  end

  describe "behavior compliance" do
    test "MockVerifier implements all required callbacks" do
      # Verify module exports required functions
      assert function_exported?(MockVerifier, :verify, 2)
      assert function_exported?(MockVerifier, :verify_batch, 2)
    end

    test "MockVerifier implements optional callback" do
      assert function_exported?(MockVerifier, :supports_streaming?, 0)
    end

    test "MinimalVerifier implements only required callbacks" do
      assert function_exported?(MinimalVerifier, :verify, 2)
      assert function_exported?(MinimalVerifier, :verify_batch, 2)

      # Optional callback not implemented
      refute function_exported?(MinimalVerifier, :supports_streaming?, 0)
    end
  end

  describe "verify/2" do
    test "returns VerificationResult for valid candidate" do
      candidate = Candidate.new!(%{content: "Hello world"})

      assert {:ok, result} = MockVerifier.verify(candidate, %{})

      assert %VerificationResult{} = result
      assert is_number(result.score)
      assert result.candidate_id == candidate.id
    end

    test "returns VerificationResult with score based on content length" do
      candidate = Candidate.new!(%{content: "Test"})

      assert {:ok, result} = MockVerifier.verify(candidate, %{})

      # "Test" has 4 characters, score should be 0.04
      assert_in_delta result.score, 0.04, 0.01
    end

    test "handles candidate with nil content" do
      candidate = Candidate.new!(%{content: nil})

      assert {:ok, result} = MockVerifier.verify(candidate, %{})

      assert result.score == 0.0
    end

    test "handles candidate with empty content" do
      candidate = Candidate.new!(%{content: ""})

      assert {:ok, result} = MockVerifier.verify(candidate, %{})

      assert result.score == 0.0
    end

    test "passes context to verify function" do
      candidate = Candidate.new!(%{content: "Test"})

      # Context should be available in verify function
      # (Our mock doesn't use it, but we verify it's accepted)
      assert {:ok, _result} = MockVerifier.verify(candidate, %{threshold: 0.5})
    end

    test "returns error when verification fails" do
      candidate = Candidate.new!(%{content: "Test"})

      assert {:error, :verification_failed} = ErrorVerifier.verify(candidate, %{})
    end

    test "MinimalVerifier returns valid result" do
      candidate = Candidate.new!(%{content: "Test"})

      assert {:ok, result} = MinimalVerifier.verify(candidate, %{})

      assert result.score == 0.5
      assert result.candidate_id == candidate.id
    end
  end

  describe "verify_batch/2" do
    test "returns list of results for multiple candidates" do
      candidates = [
        Candidate.new!(%{id: "1", content: "A"}),
        Candidate.new!(%{id: "2", content: "BB"}),
        Candidate.new!(%{id: "3", content: "CCC"})
      ]

      assert {:ok, results} = MockVerifier.verify_batch(candidates, %{})

      assert length(results) == 3

      Enum.each(results, fn result ->
        assert %VerificationResult{} = result
      end)
    end

    test "returns results in same order as candidates" do
      candidates = [
        Candidate.new!(%{id: "1", content: "AA"}),
        Candidate.new!(%{id: "2", content: "BBB"})
      ]

      assert {:ok, results} = MockVerifier.verify_batch(candidates, %{})

      assert Enum.at(results, 0).candidate_id == "1"
      assert Enum.at(results, 1).candidate_id == "2"
    end

    test "handles empty candidate list" do
      assert {:ok, results} = MockVerifier.verify_batch([], %{})

      assert results == []
    end

    test "handles single candidate in batch" do
      candidates = [Candidate.new!(%{id: "1", content: "Test"})]

      assert {:ok, results} = MockVerifier.verify_batch(candidates, %{})

      assert length(results) == 1
      assert hd(results).candidate_id == "1"
    end

    test "returns error when batch verification fails" do
      candidates = [Candidate.new!(%{content: "Test"})]

      assert {:error, :batch_failed} = ErrorVerifier.verify_batch(candidates, %{})
    end

    test "passes context to verify_batch function" do
      candidates = [Candidate.new!(%{content: "Test"})]

      # Context should be available
      assert {:ok, _results} =
               MockVerifier.verify_batch(candidates, %{
                 threshold: 0.5
               })
    end
  end

  describe "supports_streaming?/0" do
    test "MockVerifier returns true for streaming support" do
      assert MockVerifier.supports_streaming?() == true
    end

    test "MinimalVerifier does not implement streaming check" do
      # The function is not exported, so we can't call it directly
      # This is expected behavior for optional callbacks
      refute function_exported?(MinimalVerifier, :supports_streaming?, 0)
    end
  end

  describe "integration with VerificationResult" do
    test "verify result can be checked with pass?" do
      candidate = Candidate.new!(%{content: "Long content for higher score"})

      assert {:ok, result} = MockVerifier.verify(candidate, %{})

      # Should pass with low threshold due to longer content
      assert VerificationResult.pass?(result, 0.1) == true
    end

    test "verify result can be serialized" do
      candidate = Candidate.new!(%{content: "Test content"})

      assert {:ok, result} = MockVerifier.verify(candidate, %{})

      map = VerificationResult.to_map(result)
      assert Map.has_key?(map, "score")
      assert Map.has_key?(map, "confidence")
    end
  end
end
