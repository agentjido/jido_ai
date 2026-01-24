defmodule Jido.AI.Accuracy.Revisers.TargetedReviserTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, CritiqueResult, Revisers.TargetedReviser}

  @moduletag :capture_log

  describe "new/1" do
    test "creates reviser with defaults" do
      assert {:ok, reviser} = TargetedReviser.new([])

      assert reviser.fix_syntax == true
      assert reviser.fix_formatting == true
      assert reviser.preserve_reasoning == true
    end

    test "creates reviser with custom options" do
      assert {:ok, reviser} = TargetedReviser.new(fix_syntax: false)

      assert reviser.fix_syntax == false
    end
  end

  describe "new!/1" do
    test "returns reviser when valid" do
      reviser = TargetedReviser.new!([])

      assert is_struct(reviser, TargetedReviser)
    end
  end

  describe "revise/4" do
    test "implements Revision behavior" do
      Code.ensure_loaded?(TargetedReviser)
      assert Jido.AI.Accuracy.Revision.reviser?(TargetedReviser) == true
    end

    test "routes code content to revise_code" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "def foo(): return 1"})

      critique = CritiqueResult.new!(%{severity: 0.5, suggestions: ["Add colon"]})

      assert {:ok, revised} = TargetedReviser.revise(reviser, candidate, critique, %{})

      assert revised.id =~ "code-rev"
      assert revised.metadata.revision_type == :code
    end

    test "routes reasoning content to revise_reasoning" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "Therefore, we can conclude that..."})

      critique = CritiqueResult.new!(%{severity: 0.5})

      assert {:ok, revised} = TargetedReviser.revise(reviser, candidate, critique, %{})

      assert revised.metadata.revision_type == :reasoning
    end

    test "uses explicit content_type from context" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "random text"})

      critique = CritiqueResult.new!(%{severity: 0.3})

      assert {:ok, revised} =
               TargetedReviser.revise(reviser, candidate, critique, %{content_type: :format})

      assert revised.metadata.revision_type == :format
    end
  end

  describe "revise_code/4" do
    test "tracks revision metadata for code" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "code-1", content: "def foo(): return 1"})

      critique = CritiqueResult.new!(%{severity: 0.6, suggestions: ["Fix syntax", "Add docstring"]})

      assert {:ok, revised} = TargetedReviser.revise_code(reviser, candidate, critique, %{})

      assert revised.metadata.revision_of == "code-1"
      assert revised.metadata.revision_type == :code
      assert revised.metadata.reviser == :targeted
    end

    test "preserves reasoning when configured" do
      reviser = TargetedReviser.new!(preserve_reasoning: true)
      candidate = Candidate.new!(%{id: "1", content: "code", reasoning: "explanation"})

      critique = CritiqueResult.new!(%{severity: 0.4})

      assert {:ok, revised} = TargetedReviser.revise_code(reviser, candidate, critique, %{})

      assert revised.reasoning == "explanation"
    end
  end

  describe "revise_reasoning/4" do
    test "improves logical flow" do
      reviser = TargetedReviser.new!([])

      candidate =
        Candidate.new!(%{
          id: "1",
          content: "The data shows trend X. The result is Y."
        })

      critique = CritiqueResult.new!(%{severity: 0.5})

      assert {:ok, revised} = TargetedReviser.revise_reasoning(reviser, candidate, critique, %{})

      assert revised.metadata.revision_type == :reasoning
    end

    test "tracks changes made" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "Reasoning text"})

      critique = CritiqueResult.new!(%{severity: 0.5, suggestions: ["Add conclusion"]})

      assert {:ok, revised} = TargetedReviser.revise_reasoning(reviser, candidate, critique, %{})

      assert revised.metadata.changes_made == ["Add conclusion"]
    end
  end

  describe "revise_format/4" do
    test "fixes trailing whitespace" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "Line one   \nLine two  "})

      critique = CritiqueResult.new!(%{severity: 0.3})

      assert {:ok, revised} = TargetedReviser.revise_format(reviser, candidate, critique, %{})

      # Should remove trailing whitespace
      refute revised.content =~ "  $"
    end

    test "normalizes line endings" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "Line one\r\nLine two\r\n"})

      critique = CritiqueResult.new!(%{severity: 0.2})

      assert {:ok, revised} = TargetedReviser.revise_format(reviser, candidate, critique, %{})

      # Should normalize to \n
      refute revised.content =~ "\r"
    end

    test "tracks format revision type" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "text"})

      critique = CritiqueResult.new!(%{severity: 0.2})

      assert {:ok, revised} = TargetedReviser.revise_format(reviser, candidate, critique, %{})

      assert revised.metadata.revision_type == :format
    end
  end

  describe "revision metadata" do
    test "includes parts_preserved in metadata" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "Keep this\nFix that"})

      critique = CritiqueResult.new!(%{severity: 0.5})

      {:ok, revised} = TargetedReviser.revise(reviser, candidate, critique, %{})

      assert is_list(revised.metadata.parts_preserved)
    end

    test "includes changes_made from critique" do
      reviser = TargetedReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "code"})

      critique = CritiqueResult.new!(%{severity: 0.5, suggestions: ["Fix 1", "Fix 2"]})

      {:ok, revised} = TargetedReviser.revise(reviser, candidate, critique, %{})

      assert revised.metadata.changes_made == ["Fix 1", "Fix 2"]
    end
  end
end
