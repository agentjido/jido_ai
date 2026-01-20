defmodule Jido.AI.Accuracy.RevisionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, CritiqueResult, Revision}

  @moduletag :capture_log

  # Mock reviser for testing
  defmodule MockReviser do
    @behaviour Revision

    @impl true
    def revise(%Candidate{content: content}, %CritiqueResult{} = _critique, _context) do
      # Simple mock: append " (improved)" to content
      {:ok,
       Candidate.new!(%{
         id: "revised-1",
         content: content <> " (improved)",
         metadata: %{revised: true}
       })}
    end
  end

  # Mock reviser with 4-arity (struct-based)
  defmodule StructReviser do
    @behaviour Revision

    defstruct []

    @impl true
    def revise(%__MODULE__{} = _reviser, %Candidate{} = candidate, %CritiqueResult{} = _critique, _context) do
      {:ok,
       Candidate.new!(%{
         id: "revised-struct",
         content: String.trim(candidate.content) <> " [STRUCT-REVISED]",
         metadata: %{struct_revised: true}
       })}
    end
  end

  describe "revise/3 callback" do
    test "MockReviser implements revise correctly" do
      candidate = Candidate.new!(%{id: "1", content: "original response"})

      critique =
        CritiqueResult.new!(%{
          severity: 0.5,
          issues: ["Issue 1"],
          suggestions: ["Fix it"]
        })

      assert {:ok, revised} = MockReviser.revise(candidate, critique, %{})

      assert revised.content =~ "improved"
      assert revised.metadata.revised == true
    end

    test "revision incorporates critique context" do
      defmodule ContextReviser do
        @behaviour Revision

        @impl true
        def revise(%Candidate{} = candidate, %CritiqueResult{} = critique, context) do
          preserve = Map.get(context, :preserve_correct, false)
          severity = critique.severity

          {:ok,
           Candidate.new!(%{
             id: "context-revised",
             content: "Preserve: #{preserve}, Severity: #{severity}, Original: #{candidate.content}",
             metadata: %{context_used: true}
           })}
        end
      end

      candidate = Candidate.new!(%{id: "1", content: "test"})

      critique = CritiqueResult.new!(%{severity: 0.7})

      assert {:ok, revised} = ContextReviser.revise(candidate, critique, %{preserve_correct: true})

      assert revised.content =~ "Preserve: true"
      assert revised.content =~ "Severity: 0.7"
    end
  end

  describe "diff/2" do
    test "returns unchanged when content is the same" do
      c1 = Candidate.new!(%{id: "1", content: "same content"})
      c2 = Candidate.new!(%{id: "2", content: "same content"})

      assert {:ok, diff} = Revision.diff(c1, c2)

      assert diff.content_changed == false
      assert diff.content_diff == :unchanged
    end

    test "returns unchanged when both empty" do
      c1 = Candidate.new!(%{id: "1", content: ""})
      c2 = Candidate.new!(%{id: "2", content: ""})

      assert {:ok, diff} = Revision.diff(c1, c2)

      assert diff.content_changed == false
      assert diff.content_diff == :unchanged
    end

    test "detects substantive content changes" do
      c1 = Candidate.new!(%{id: "1", content: "original words here"})
      c2 = Candidate.new!(%{id: "2", content: "revised words there"})

      assert {:ok, diff} = Revision.diff(c1, c2)

      assert diff.content_changed == true
      assert diff.content_diff.type == :substantive
      assert diff.content_diff.added_count > 0
      assert diff.content_diff.removed_count > 0
    end

    test "detects whitespace-only changes" do
      c1 = Candidate.new!(%{id: "1", content: "words here"})
      c2 = Candidate.new!(%{id: "2", content: "words  here  "})

      assert {:ok, diff} = Revision.diff(c1, c2)

      assert diff.content_changed == true
      assert elem(diff.content_diff, 0) == :whitespace_only
    end

    test "detects metadata changes" do
      c1 = Candidate.new!(%{id: "1", content: "same", metadata: %{key: "value"}})
      c2 = Candidate.new!(%{id: "2", content: "same", metadata: %{key: "new value"}})

      assert {:ok, diff} = Revision.diff(c1, c2)

      assert diff.metadata_changed == true
      assert diff.metadata_diff.changed_keys == [:key]
    end

    test "returns unchanged metadata when same" do
      c1 = Candidate.new!(%{id: "1", content: "same", metadata: %{key: "value"}})
      c2 = Candidate.new!(%{id: "2", content: "same", metadata: %{key: "value"}})

      assert {:ok, diff} = Revision.diff(c1, c2)

      assert diff.metadata_changed == false
      assert diff.metadata_diff == :unchanged
    end

    test "includes timestamps in diff" do
      c1 = Candidate.new!(%{id: "1", content: "a"})
      c2 = Candidate.new!(%{id: "2", content: "b"})

      assert {:ok, diff} = Revision.diff(c1, c2)

      assert is_integer(diff.timestamp)
      assert diff.timestamp > 0
    end
  end

  describe "reviser?/1" do
    test "returns true for modules implementing Revision behavior" do
      assert Revision.reviser?(MockReviser) == true
      assert Revision.reviser?(StructReviser) == true
    end

    test "returns true for struct-based revisers with 4-arity" do
      assert Revision.reviser?(StructReviser) == true
    end

    test "returns false for modules not implementing Revision behavior" do
      assert Revision.reviser?(List) == false
      assert Revision.reviser?(Map) == false
    end

    test "returns false for non-modules" do
      assert Revision.reviser?(nil) == false
      assert Revision.reviser?("string") == false
    end
  end

  describe "behaviour/0" do
    test "returns the Revision module" do
      assert Revision.behaviour() == Revision
    end
  end

  describe "custom diff implementations" do
    test "revisers can provide custom diff implementation" do
      defmodule CustomDiffReviser do
        @behaviour Revision

        @impl true
        def revise(_candidate, _critique, _context) do
          {:ok, Candidate.new!(%{id: "1", content: "revised"})}
        end

        @impl true
        def diff(original, revised) do
          {:ok, %{custom: true, from: original.id, to: revised.id}}
        end
      end

      c1 = Candidate.new!(%{id: "1", content: "original"})
      c2 = Candidate.new!(%{id: "2", content: "revised"})

      assert {:ok, diff} = CustomDiffReviser.diff(c1, c2)

      assert diff.custom == true
      assert diff.from == "1"
      assert diff.to == "2"
    end
  end

  describe "context handling" do
    test "revision receives context with preserve_correct option" do
      defmodule PreserveReviser do
        @behaviour Revision

        @impl true
        def revise(%Candidate{content: content}, _critique, context) do
          preserve = Map.get(context, :preserve_correct, false)

          if preserve do
            {:ok, Candidate.new!(%{id: "1", content: content, metadata: %{preserved: true}})}
          else
            {:ok, Candidate.new!(%{id: "1", content: content <> " [MODIFIED]"})}
          end
        end
      end

      candidate = Candidate.new!(%{id: "1", content: "original"})
      critique = CritiqueResult.new!(%{severity: 0.5})

      # Without preserve
      {:ok, revised1} = PreserveReviser.revise(candidate, critique, %{})
      assert revised1.content =~ "MODIFIED"

      # With preserve
      {:ok, revised2} = PreserveReviser.revise(candidate, critique, %{preserve_correct: true})
      assert revised2.metadata.preserved == true
    end
  end
end
