defmodule Jido.AI.Accuracy.CritiqueResultTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{CritiqueResult, VerificationResult}

  @moduletag :capture_log

  describe "new/1" do
    test "creates result with defaults" do
      assert {:ok, result} = CritiqueResult.new(%{severity: 0.5})

      assert result.severity == 0.5
      assert result.issues == []
      assert result.suggestions == []
      assert result.feedback == nil
      assert is_boolean(result.actionable)
    end

    test "creates result with custom issues" do
      assert {:ok, result} = CritiqueResult.new(%{severity: 0.5, issues: ["error1", "error2"]})

      assert result.issues == ["error1", "error2"]
    end

    test "creates result with custom suggestions" do
      assert {:ok, result} = CritiqueResult.new(%{severity: 0.5, suggestions: ["fix it"]})

      assert result.suggestions == ["fix it"]
    end

    test "creates result with custom feedback" do
      assert {:ok, result} = CritiqueResult.new(%{severity: 0.5, feedback: "Needs work"})

      assert result.feedback == "Needs work"
    end

    test "creates result with custom metadata" do
      assert {:ok, result} = CritiqueResult.new(%{severity: 0.5, metadata: %{key: "value"}})

      assert result.metadata.key == "value"
    end

    test "returns error for invalid severity" do
      assert {:error, :invalid_severity} = CritiqueResult.new(%{severity: 1.5})
      assert {:error, :invalid_severity} = CritiqueResult.new(%{severity: -0.1})
      assert {:error, :invalid_severity} = CritiqueResult.new(%{severity: "invalid"})
    end

    test "returns error for invalid issues" do
      assert {:error, :invalid_issues} = CritiqueResult.new(%{severity: 0.5, issues: "not a list"})
    end

    test "requires severity field" do
      assert {:error, :invalid_severity} = CritiqueResult.new(%{issues: []})
    end

    test "computes actionable based on issues and severity" do
      # High severity with no issues is still actionable
      assert {:ok, result} = CritiqueResult.new(%{severity: 0.8, issues: []})
      assert result.actionable == true

      # Low severity with no issues is not actionable
      assert {:ok, result} = CritiqueResult.new(%{severity: 0.2, issues: []})
      assert result.actionable == false

      # Any issues makes it actionable
      assert {:ok, result} = CritiqueResult.new(%{severity: 0.1, issues: ["error"]})
      assert result.actionable == true
    end
  end

  describe "new!/1" do
    test "returns result when valid" do
      result = CritiqueResult.new!(%{severity: 0.5})

      assert result.severity == 0.5
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid CritiqueResult/, fn ->
        CritiqueResult.new!(%{severity: 1.5})
      end
    end
  end

  describe "has_issues?/1" do
    test "returns true when issues are present" do
      result = CritiqueResult.new!(%{severity: 0.5, issues: ["error1"]})

      assert CritiqueResult.has_issues?(result) == true
    end

    test "returns false when issues list is empty" do
      result = CritiqueResult.new!(%{severity: 0.5, issues: []})

      assert CritiqueResult.has_issues?(result) == false
    end

    test "returns false when no issues field" do
      result = CritiqueResult.new!(%{severity: 0.0})

      assert CritiqueResult.has_issues?(result) == false
    end
  end

  describe "should_refine?/2" do
    test "returns true when severity above default threshold" do
      result = CritiqueResult.new!(%{severity: 0.5, issues: []})

      assert CritiqueResult.should_refine?(result) == true
    end

    test "returns false when severity below default threshold" do
      result = CritiqueResult.new!(%{severity: 0.2, issues: []})

      assert CritiqueResult.should_refine?(result) == false
    end

    test "returns false when severity equals threshold" do
      result = CritiqueResult.new!(%{severity: 0.3, issues: []})

      assert CritiqueResult.should_refine?(result) == false
    end

    test "uses custom threshold" do
      result = CritiqueResult.new!(%{severity: 0.5, issues: []})

      assert CritiqueResult.should_refine?(result, threshold: 0.6) == false
      assert CritiqueResult.should_refine?(result, threshold: 0.4) == true
    end

    test "returns true for high severity even without issues" do
      result = CritiqueResult.new!(%{severity: 0.8, issues: []})

      assert CritiqueResult.should_refine?(result) == true
    end
  end

  describe "add_issue/2" do
    test "adds issue to existing list" do
      result = CritiqueResult.new!(%{severity: 0.5, issues: ["error1"]})
      updated = CritiqueResult.add_issue(result, "error2")

      assert updated.issues == ["error1", "error2"]
    end

    test "adds issue to empty list" do
      result = CritiqueResult.new!(%{severity: 0.5, issues: []})
      updated = CritiqueResult.add_issue(result, "new error")

      assert updated.issues == ["new error"]
    end

    test "adds issue as map" do
      result = CritiqueResult.new!(%{severity: 0.5, issues: []})
      updated = CritiqueResult.add_issue(result, %{type: "error", message: "test"})

      assert updated.issues == [%{type: "error", message: "test"}]
    end
  end

  describe "severity_level/1" do
    test "returns :low for severity < 0.3" do
      result = CritiqueResult.new!(%{severity: 0.0, issues: []})
      assert CritiqueResult.severity_level(result) == :low

      result = CritiqueResult.new!(%{severity: 0.2, issues: []})
      assert CritiqueResult.severity_level(result) == :low
    end

    test "returns :medium for severity 0.3 to 0.7" do
      result = CritiqueResult.new!(%{severity: 0.3, issues: []})
      assert CritiqueResult.severity_level(result) == :medium

      result = CritiqueResult.new!(%{severity: 0.5, issues: []})
      assert CritiqueResult.severity_level(result) == :medium

      result = CritiqueResult.new!(%{severity: 0.69, issues: []})
      assert CritiqueResult.severity_level(result) == :medium
    end

    test "returns :high for severity >= 0.7" do
      result = CritiqueResult.new!(%{severity: 0.7, issues: []})
      assert CritiqueResult.severity_level(result) == :high

      result = CritiqueResult.new!(%{severity: 1.0, issues: []})
      assert CritiqueResult.severity_level(result) == :high
    end
  end

  describe "merge/2" do
    test "merges issues from both results" do
      r1 = CritiqueResult.new!(%{severity: 0.5, issues: ["a"]})
      r2 = CritiqueResult.new!(%{severity: 0.3, issues: ["b"]})

      merged = CritiqueResult.merge(r1, r2)

      assert merged.issues == ["a", "b"]
    end

    test "merges suggestions from both results" do
      r1 = CritiqueResult.new!(%{severity: 0.5, suggestions: ["fix a"]})
      r2 = CritiqueResult.new!(%{severity: 0.3, suggestions: ["fix b"]})

      merged = CritiqueResult.merge(r1, r2)

      assert merged.suggestions == ["fix a", "fix b"]
    end

    test "uses maximum severity" do
      r1 = CritiqueResult.new!(%{severity: 0.5, issues: []})
      r2 = CritiqueResult.new!(%{severity: 0.8, issues: []})

      merged = CritiqueResult.merge(r1, r2)

      assert merged.severity == 0.8
    end

    test "merges feedback from both results" do
      r1 = CritiqueResult.new!(%{severity: 0.5, feedback: "First issue"})
      r2 = CritiqueResult.new!(%{severity: 0.3, feedback: "Second issue"})

      merged = CritiqueResult.merge(r1, r2)

      assert merged.feedback == "First issue\nSecond issue"
    end

    test "handles nil feedback" do
      r1 = CritiqueResult.new!(%{severity: 0.5, feedback: nil})
      r2 = CritiqueResult.new!(%{severity: 0.3, feedback: "Has feedback"})

      merged = CritiqueResult.merge(r1, r2)

      assert merged.feedback == "Has feedback"
    end

    test "merges metadata" do
      r1 = CritiqueResult.new!(%{severity: 0.5, metadata: %{a: 1}})
      r2 = CritiqueResult.new!(%{severity: 0.3, metadata: %{b: 2}})

      merged = CritiqueResult.merge(r1, r2)

      assert merged.metadata == %{a: 1, b: 2}
    end

    test "computes actionable correctly" do
      r1 = CritiqueResult.new!(%{severity: 0.2, issues: []})
      r2 = CritiqueResult.new!(%{severity: 0.3, issues: []})

      merged = CritiqueResult.merge(r1, r2)

      assert merged.actionable == false
    end
  end

  describe "no_issues/0" do
    test "creates result with no issues" do
      result = CritiqueResult.no_issues()

      assert result.severity == 0.0
      assert result.issues == []
      assert result.suggestions == []
      assert result.feedback == "No issues found"
      assert result.actionable == false
    end
  end

  describe "from_verification_result/1" do
    test "converts low score to high severity" do
      vr = %VerificationResult{score: 0.3, reasoning: "Poor response"}

      result = CritiqueResult.from_verification_result(vr)

      assert result.severity == 0.7
      assert result.feedback == "Poor response"
      assert result.actionable == true
    end

    test "converts high score to low severity" do
      vr = %VerificationResult{score: 0.9, reasoning: "Good response"}

      result = CritiqueResult.from_verification_result(vr)

      assert_in_delta result.severity, 0.1, 0.01
      assert result.feedback == "Good response"
      assert result.actionable == false
    end

    test "handles nil score" do
      vr = %VerificationResult{score: nil, reasoning: "Unknown"}

      result = CritiqueResult.from_verification_result(vr)

      assert result.severity == 0.5
    end

    test "includes verification metadata" do
      vr = %VerificationResult{score: 0.5, reasoning: "Okay"}

      result = CritiqueResult.from_verification_result(vr)

      assert result.metadata.verification_result == true
    end
  end

  describe "defaults/0" do
    test "returns default fields" do
      defaults = CritiqueResult.defaults()

      assert defaults.issues == []
      assert defaults.suggestions == []
      assert defaults.severity == 0.0
      assert defaults.feedback == nil
      assert defaults.actionable == false
      assert defaults.metadata == %{}
    end
  end
end
