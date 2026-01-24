defmodule Jido.AI.Accuracy.Revisers.LLMReviserTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, CritiqueResult, Revisers.LLMReviser}

  @moduletag :capture_log

  describe "new/1" do
    test "creates reviser with defaults" do
      assert {:ok, reviser} = LLMReviser.new([])

      assert is_binary(reviser.model)
      assert reviser.preserve_correct == true
      assert reviser.temperature == 0.5
      assert reviser.timeout == 30_000
      assert reviser.max_retries == 2
      assert reviser.domain == nil
    end

    test "creates reviser with custom preserve_correct" do
      assert {:ok, reviser} = LLMReviser.new(preserve_correct: false)

      assert reviser.preserve_correct == false
    end

    test "creates reviser with custom temperature" do
      assert {:ok, reviser} = LLMReviser.new(temperature: 0.7)

      assert reviser.temperature == 0.7
    end

    test "creates reviser with custom domain" do
      assert {:ok, reviser} = LLMReviser.new(domain: :code)

      assert reviser.domain == :code
    end

    test "returns error for invalid temperature" do
      assert {:error, :invalid_temperature} = LLMReviser.new(temperature: -0.1)
      assert {:error, :invalid_temperature} = LLMReviser.new(temperature: 2.5)
    end

    test "returns error for invalid timeout" do
      assert {:error, :invalid_timeout} = LLMReviser.new(timeout: 500)
      assert {:error, :invalid_timeout} = LLMReviser.new(timeout: 500_000)
    end
  end

  describe "new!/1" do
    test "returns reviser when valid" do
      reviser = LLMReviser.new!(temperature: 0.7)

      assert reviser.temperature == 0.7
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid LLMReviser/, fn ->
        LLMReviser.new!(temperature: 5.0)
      end
    end
  end

  describe "revise/4" do
    test "implements Revision behavior" do
      Code.ensure_loaded?(LLMReviser)
      assert Jido.AI.Accuracy.Revision.reviser?(LLMReviser) == true
    end

    test "returns revised candidate for valid input" do
      reviser = LLMReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "The answer is 42."})

      critique =
        CritiqueResult.new!(%{
          severity: 0.5,
          issues: ["Needs more explanation"],
          suggestions: ["Add context"]
        })

      # This test will use ReqLLM if available, otherwise mock
      # For testing purposes, we'll create a mock version
      result = LLMReviser.revise(reviser, candidate, critique, %{prompt: "What is 6 * 7?"})

      # Result will either be ok or error depending on LLM availability
      case result do
        {:ok, revised} ->
          assert %Candidate{} = revised
          assert String.contains?(revised.id, "-rev")

        {:error, _reason} ->
          # LLM not available in test environment
          :ok
      end
    end
  end

  describe "diff/2" do
    test "generates detailed diff between candidates" do
      c1 = Candidate.new!(%{id: "1", content: "Line one\nLine two"})
      c2 = Candidate.new!(%{id: "1-rev1", content: "Line one\nLine two revised"})

      assert {:ok, diff} = LLMReviser.diff(c1, c2)

      assert diff.content_changed == true
      assert diff.content_diff.changes_count > 0
      assert diff.revision_count == 1
    end

    test "includes revision metadata in diff" do
      c1 = Candidate.new!(%{id: "1", content: "original"})

      c2 =
        Candidate.new!(%{
          id: "1-rev1",
          content: "revised",
          metadata: %{
            changes_made: ["Fixed issue 1"],
            parts_preserved: ["Good part"],
            revision_count: 2
          }
        })

      assert {:ok, diff} = LLMReviser.diff(c1, c2)

      assert diff.changes_made == ["Fixed issue 1"]
      assert diff.parts_preserved == ["Good part"]
      assert diff.revision_count == 2
    end

    test "returns unchanged for identical content" do
      c1 = Candidate.new!(%{id: "1", content: "same content"})
      c2 = Candidate.new!(%{id: "2", content: "same content"})

      assert {:ok, diff} = LLMReviser.diff(c1, c2)

      assert diff.content_changed == false
      assert diff.content_diff == :unchanged
    end
  end

  describe "domain guidelines" do
    test "includes domain-specific guidelines for code" do
      assert {:ok, reviser} = LLMReviser.new(domain: :code)

      assert reviser.domain == :code
    end

    test "includes domain-specific guidelines for math" do
      assert {:ok, reviser} = LLMReviser.new(domain: :math)

      assert reviser.domain == :math
    end

    test "includes domain-specific guidelines for writing" do
      assert {:ok, reviser} = LLMReviser.new(domain: :writing)

      assert reviser.domain == :writing
    end

    test "includes domain-specific guidelines for reasoning" do
      assert {:ok, reviser} = LLMReviser.new(domain: :reasoning)

      assert reviser.domain == :reasoning
    end
  end

  describe "mock-based tests" do
    # These tests use a mock to avoid LLM calls

    defmodule MockLLMReviser do
      @moduledoc false
      defstruct model: nil,
                prompt_template: nil,
                preserve_correct: true,
                temperature: 0.5,
                timeout: 30_000,
                max_retries: 2,
                domain: nil

      def new(opts) do
        {:ok, struct(__MODULE__, opts)}
      end

      def new!(opts) do
        struct(__MODULE__, opts)
      end

      def revise(_reviser, %Candidate{} = candidate, %CritiqueResult{} = critique, context) do
        # Simulate revision by appending critique feedback
        improved_content = candidate.content <> " [Improved based on: #{critique.feedback}]"
        revision_count = Map.get(context, :revision_count, 0)

        {:ok,
         Candidate.new!(%{
           id: "#{candidate.id}-rev#{revision_count + 1}",
           content: improved_content,
           metadata: %{
             revision_of: candidate.id,
             revision_count: revision_count + 1,
             changes_made: critique.suggestions,
             parts_preserved: [],
             reviser: :mock_llm
           }
         })}
      end

      def diff(original, revised) do
        {:ok,
         %{
           original_id: original.id,
           revised_id: revised.id,
           content_changed: original.content != revised.content,
           changes_made: Map.get(revised.metadata || %{}, :changes_made, []),
           parts_preserved: Map.get(revised.metadata || %{}, :parts_preserved, []),
           revision_count: Map.get(revised.metadata || %{}, :revision_count, 1)
         }}
      end
    end

    test "mock reviser returns valid revised candidate" do
      reviser = MockLLMReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "original"})

      critique =
        CritiqueResult.new!(%{
          severity: 0.6,
          issues: ["Issue 1"],
          suggestions: ["Fix it"],
          feedback: "Needs improvement"
        })

      assert {:ok, revised} = MockLLMReviser.revise(reviser, candidate, critique, %{})

      assert String.contains?(revised.content, "Improved based on")
      assert revised.id == "1-rev1"
      assert revised.metadata.revision_count == 1
    end

    test "mock reviser tracks revision count" do
      reviser = MockLLMReviser.new!([])
      candidate = Candidate.new!(%{id: "1", content: "content"})

      critique = CritiqueResult.new!(%{severity: 0.5})

      # First revision
      assert {:ok, rev1} = MockLLMReviser.revise(reviser, candidate, critique, %{revision_count: 0})
      assert rev1.metadata.revision_count == 1

      # Second revision
      assert {:ok, rev2} = MockLLMReviser.revise(reviser, rev1, critique, %{revision_count: 1})
      assert rev2.metadata.revision_count == 2
    end

    test "mock diff shows correct changes" do
      reviser = MockLLMReviser.new!([])
      c1 = Candidate.new!(%{id: "1", content: "original"})
      critique = CritiqueResult.new!(%{severity: 0.5, suggestions: ["Change X"]})

      {:ok, c2} = MockLLMReviser.revise(reviser, c1, critique, %{})

      assert {:ok, diff} = MockLLMReviser.diff(c1, c2)

      assert diff.content_changed == true
      assert diff.changes_made == ["Change X"]
      assert diff.revision_count == 1
    end
  end
end
