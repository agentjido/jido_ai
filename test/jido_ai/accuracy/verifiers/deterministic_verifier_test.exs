defmodule Jido.AI.Accuracy.Verifiers.DeterministicVerifierTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Verifiers.DeterministicVerifier
  alias Jido.AI.Accuracy.{Candidate, VerificationResult}

  @moduletag :capture_log

  describe "new/1" do
    test "creates verifier with default values" do
      assert {:ok, verifier} = DeterministicVerifier.new(ground_truth: "42")

      assert verifier.ground_truth == "42"
      assert verifier.comparison_type == :exact
      assert verifier.tolerance == nil
      assert verifier.case_sensitive == false
      assert verifier.normalize_whitespace == true
    end

    test "creates verifier with numerical comparison type" do
      assert {:ok, verifier} =
               DeterministicVerifier.new(ground_truth: 3.14, comparison_type: :numerical, tolerance: 0.01)

      assert verifier.ground_truth == 3.14
      assert verifier.comparison_type == :numerical
      assert verifier.tolerance == 0.01
    end

    test "creates verifier with regex comparison type" do
      assert {:ok, verifier} =
               DeterministicVerifier.new(ground_truth: ~r/\d{3}-\d{2}-\d{4}/, comparison_type: :regex)

      assert verifier.comparison_type == :regex
      assert is_struct(verifier.ground_truth, Regex)
    end

    test "creates verifier with case_sensitive enabled" do
      assert {:ok, verifier} =
               DeterministicVerifier.new(ground_truth: "Hello", case_sensitive: true)

      assert verifier.case_sensitive == true
    end

    test "creates verifier with normalize_whitespace disabled" do
      assert {:ok, verifier} =
               DeterministicVerifier.new(ground_truth: "test", normalize_whitespace: false)

      assert verifier.normalize_whitespace == false
    end

    test "returns error for invalid comparison type" do
      assert {:error, :invalid_comparison_type} =
               DeterministicVerifier.new(ground_truth: "42", comparison_type: :invalid)
    end

    test "returns error when numerical comparison without tolerance" do
      assert {:error, :tolerance_required_for_numerical} =
               DeterministicVerifier.new(ground_truth: 42, comparison_type: :numerical)
    end

    test "returns error for numerical with negative tolerance" do
      assert {:error, :invalid_tolerance} =
               DeterministicVerifier.new(
                 ground_truth: 42,
                 comparison_type: :numerical,
                 tolerance: -0.1
               )
    end

    test "returns error for numerical with nil tolerance explicitly" do
      assert {:error, :tolerance_required_for_numerical} =
               DeterministicVerifier.new(
                 ground_truth: 42,
                 comparison_type: :numerical,
                 tolerance: nil
               )
    end

    test "accepts numerical with valid tolerance" do
      assert {:ok, verifier} =
               DeterministicVerifier.new(
                 ground_truth: 42,
                 comparison_type: :numerical,
                 tolerance: 0.01
               )

      assert verifier.tolerance == 0.01
    end

    test "accepts zero tolerance for numerical comparison" do
      assert {:ok, verifier} =
               DeterministicVerifier.new(
                 ground_truth: 42,
                 comparison_type: :numerical,
                 tolerance: 0
               )

      assert verifier.tolerance == 0
    end
  end

  describe "new!/1" do
    test "returns verifier when valid" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      assert verifier.ground_truth == "42"
    end

    test "raises when invalid comparison type" do
      assert_raise ArgumentError, ~r/Invalid deterministic verifier/, fn ->
        DeterministicVerifier.new!(ground_truth: "42", comparison_type: :invalid_type)
      end
    end

    test "raises when numerical without tolerance" do
      assert_raise ArgumentError, ~r/Invalid deterministic verifier/, fn ->
        DeterministicVerifier.new!(ground_truth: 42, comparison_type: :numerical)
      end
    end
  end

  describe "verify/2 - exact comparison" do
    setup do
      {:ok,
       verifier: DeterministicVerifier.new!(ground_truth: "42", comparison_type: :exact, normalize_whitespace: true)}
    end

    test "returns score 1.0 for exact match", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
      assert result.confidence == 1.0
      assert result.candidate_id == candidate.id
      assert String.contains?(result.reasoning, "exact")
    end

    test "returns score 0.0 for non-matching answer", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "43"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
      assert result.confidence == 1.0
      assert String.contains?(result.reasoning, "No match")
    end

    test "normalizes whitespace by default", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "4  2"})

      assert {:ok, _result} = DeterministicVerifier.verify(verifier, candidate, %{})
      # "4  2" -> "4 2" after whitespace normalization, but "42" != "4 2"
      # Let's test with proper whitespace matching
      verifier2 = DeterministicVerifier.new!(ground_truth: "the answer is 42")
      candidate2 = Candidate.new!(%{content: "the    answer   is   42"})

      assert {:ok, result2} = DeterministicVerifier.verify(verifier2, candidate2, %{})
      assert result2.score == 1.0
    end

    test "respects normalize_whitespace: false", %{verifier: _verifier} do
      verifier = DeterministicVerifier.new!(ground_truth: "42", normalize_whitespace: false)
      candidate = Candidate.new!(%{content: "4 2"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
    end

    test "is case-insensitive by default", %{verifier: _verifier} do
      verifier = DeterministicVerifier.new!(ground_truth: "hello", case_sensitive: false)
      candidate = Candidate.new!(%{content: "HELLO"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "respects case_sensitive: true", %{verifier: _verifier} do
      verifier =
        DeterministicVerifier.new!(ground_truth: "hello", case_sensitive: true, normalize_whitespace: false)

      candidate = Candidate.new!(%{content: "HELLO"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
    end

    test "handles number ground_truth with string content", %{verifier: _verifier} do
      verifier = DeterministicVerifier.new!(ground_truth: 42)
      candidate = Candidate.new!(%{content: "42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "handles quoted answer extraction", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "The answer is \"42\""})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end
  end

  describe "verify/2 - numerical comparison" do
    setup do
      {:ok,
       verifier:
         DeterministicVerifier.new!(
           ground_truth: 3.14159,
           comparison_type: :numerical,
           tolerance: 0.001
         )}
    end

    test "returns score 1.0 for exact match", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "3.14159"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "returns score 1.0 for value within tolerance", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "3.142"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "returns score 0.0 for value outside tolerance", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "3.15"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
    end

    test "handles integer ground truth", %{verifier: _verifier} do
      verifier =
        DeterministicVerifier.new!(
          ground_truth: 100,
          comparison_type: :numerical,
          tolerance: 1
        )

      candidate = Candidate.new!(%{content: "99.5"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "extracts number from text", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "The answer is 3.142"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "extracts quoted number", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "Result: \"3.142\""})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "returns 0.0 for non-numeric content", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "I don't know"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
    end

    test "handles zero tolerance", %{verifier: _verifier} do
      verifier =
        DeterministicVerifier.new!(
          ground_truth: 5.0,
          comparison_type: :numerical,
          tolerance: 0
        )

      candidate = Candidate.new!(%{content: "5.0"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "returns 0.0 when zero tolerance and small difference", %{verifier: _verifier} do
      verifier =
        DeterministicVerifier.new!(
          ground_truth: 5.0,
          comparison_type: :numerical,
          tolerance: 0
        )

      candidate = Candidate.new!(%{content: "5.0001"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
    end

    test "handles negative numbers", %{verifier: _verifier} do
      verifier =
        DeterministicVerifier.new!(
          ground_truth: -42.5,
          comparison_type: :numerical,
          tolerance: 0.1
        )

      candidate = Candidate.new!(%{content: "-42.45"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end
  end

  describe "verify/2 - regex comparison" do
    setup do
      {:ok,
       verifier:
         DeterministicVerifier.new!(
           ground_truth: ~r/\d{3}-\d{2}-\d{4}/,
           comparison_type: :regex
         )}
    end

    test "returns score 1.0 for matching pattern", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "123-45-6789"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "returns score 0.0 for non-matching pattern", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "not-a-ssn"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
    end

    test "extracts answer from quoted content", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "The SSN is \"123-45-6789\""})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "handles complex regex patterns", %{verifier: _verifier} do
      verifier =
        DeterministicVerifier.new!(
          ground_truth: ~r/^[A-Z]{2}\d{4}$/,
          comparison_type: :regex
        )

      candidate = Candidate.new!(%{content: "AB1234"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "handles case-sensitive regex", %{verifier: _verifier} do
      verifier =
        DeterministicVerifier.new!(
          ground_truth: ~r/[A-Z]+/,
          comparison_type: :regex,
          normalize_whitespace: false
        )

      candidate = Candidate.new!(%{content: "abc"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0

      candidate2 = Candidate.new!(%{content: "ABC"})

      assert {:ok, result2} = DeterministicVerifier.verify(verifier, candidate2, %{})
      assert result2.score == 1.0
    end

    test "matches pattern within longer text", %{verifier: _verifier} do
      verifier =
        DeterministicVerifier.new!(ground_truth: ~r/\b\d{4}\b/, comparison_type: :regex)

      candidate = Candidate.new!(%{content: "The year 2024 is important"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end
  end

  describe "verify/2 - answer extraction" do
    test "extracts from 'Answer:' pattern" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "Let me think...\nAnswer: 42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "extracts from 'Therefore:' pattern" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "2 + 2 = 4\nTherefore: 42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "extracts from 'Thus:' pattern" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "Calculating...\nThus: 42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "extracts from 'Result:' pattern" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "Step 1 done\nResult: 42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "extracts from 'The answer is:' pattern" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "The answer is: 42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "falls back to last line for multi-line content" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "Step 1\nStep 2\n42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "uses full content for single line" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "extracts from double-quoted string" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: ~s(The value is "42" in the answer)})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "quoted answer takes precedence over patterns" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: ~s(Answer: 100\nThe correct answer is "42")})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end
  end

  describe "verify_batch/2" do
    test "verifies multiple candidates" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")

      candidates = [
        Candidate.new!(%{id: "1", content: "42"}),
        Candidate.new!(%{id: "2", content: "43"}),
        Candidate.new!(%{id: "3", content: "41"})
      ]

      assert {:ok, results} = DeterministicVerifier.verify_batch(verifier, candidates, %{})
      assert length(results) == 3

      assert Enum.at(results, 0).score == 1.0
      assert Enum.at(results, 1).score == 0.0
      assert Enum.at(results, 2).score == 0.0
    end

    test "returns results in same order as candidates" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")

      candidates = [
        Candidate.new!(%{id: "a", content: "42"}),
        Candidate.new!(%{id: "b", content: "42"}),
        Candidate.new!(%{id: "c", content: "42"})
      ]

      assert {:ok, results} = DeterministicVerifier.verify_batch(verifier, candidates, %{})

      assert Enum.at(results, 0).candidate_id == "a"
      assert Enum.at(results, 1).candidate_id == "b"
      assert Enum.at(results, 2).candidate_id == "c"
    end

    test "handles empty candidate list" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")

      assert {:ok, results} = DeterministicVerifier.verify_batch(verifier, [], %{})
      assert results == []
    end

    test "handles single candidate" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")

      candidates = [Candidate.new!(%{id: "1", content: "42"})]

      assert {:ok, results} = DeterministicVerifier.verify_batch(verifier, candidates, %{})
      assert length(results) == 1
      assert hd(results).score == 1.0
    end

    test "works with numerical comparison" do
      verifier =
        DeterministicVerifier.new!(
          ground_truth: 100,
          comparison_type: :numerical,
          tolerance: 5
        )

      candidates = [
        Candidate.new!(%{id: "1", content: "98"}),
        Candidate.new!(%{id: "2", content: "105"}),
        Candidate.new!(%{id: "3", content: "200"})
      ]

      assert {:ok, results} = DeterministicVerifier.verify_batch(verifier, candidates, %{})

      assert Enum.at(results, 0).score == 1.0
      assert Enum.at(results, 1).score == 1.0
      assert Enum.at(results, 2).score == 0.0
    end

    test "works with regex comparison" do
      verifier =
        DeterministicVerifier.new!(ground_truth: ~r/\d{4}/, comparison_type: :regex)

      candidates = [
        Candidate.new!(%{id: "1", content: "1234"}),
        Candidate.new!(%{id: "2", content: "abc"}),
        Candidate.new!(%{id: "3", content: "5678"})
      ]

      assert {:ok, results} = DeterministicVerifier.verify_batch(verifier, candidates, %{})

      assert Enum.at(results, 0).score == 1.0
      assert Enum.at(results, 1).score == 0.0
      assert Enum.at(results, 2).score == 1.0
    end
  end

  describe "supports_streaming?/0" do
    test "returns false for deterministic verifier" do
      refute DeterministicVerifier.supports_streaming?()
    end
  end

  describe "edge cases" do
    test "handles nil content" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: nil})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
    end

    test "handles empty string content" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: ""})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
    end

    test "handles whitespace-only content" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "   "})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 0.0
    end

    test "handles candidate with special characters in content" do
      verifier = DeterministicVerifier.new!(ground_truth: "42!@#")
      candidate = Candidate.new!(%{content: "42!@#"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "handles unicode content" do
      verifier = DeterministicVerifier.new!(ground_truth: "café")
      candidate = Candidate.new!(%{content: "café"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.score == 1.0
    end

    test "preserves candidate_id in result" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{id: "custom-id-123", content: "42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      assert result.candidate_id == "custom-id-123"
    end
  end

  describe "integration with VerificationResult" do
    test "result can be checked with pass?" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})

      assert VerificationResult.pass?(result, 0.5) == true
      assert result.score == 1.0
      assert result.confidence == 1.0
    end

    test "result with score 0.0 fails pass? check" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "43"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})

      assert VerificationResult.pass?(result, 0.5) == false
    end
  end
end
