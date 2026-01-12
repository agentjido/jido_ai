defmodule Jido.AI.Accuracy.CritiqueTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Critique, CritiqueResult}

  @moduletag :capture_log

  # Mock critiquer for testing
  defmodule MockCritiquer do
    @behaviour Critique

    @impl true
    def critique(%Candidate{content: content}, _context) do
      {:ok,
       CritiqueResult.new!(%{
         severity: 0.5,
         issues: ["Sample issue for: #{content}"],
         suggestions: ["Fix it"]
       })}
    end
  end

  # Mock critiquer with batch support
  defmodule BatchCritiquer do
    @behaviour Critique

    @impl true
    def critique(%Candidate{} = candidate, _context) do
      {:ok,
       CritiqueResult.new!(%{
         severity: 0.3,
         issues: ["Batch issue"],
         suggestions: []
       })}
    end

    @impl true
    def critique_batch(candidates, _context) do
      results =
        Enum.map(candidates, fn _candidate ->
          {:ok,
           CritiqueResult.new!(%{
             severity: 0.4,
             issues: ["Batch optimized issue"],
             suggestions: []
           })}
        end)

      {:ok, Enum.map(results, fn {:ok, r} -> r end)}
    end
  end

  # Mock critiquer that can fail
  defmodule FailingCritiquer do
    @behaviour Critique

    @impl true
    def critique(_candidate, _context) do
      {:error, :critique_failed}
    end
  end

  describe "critique/2 callback" do
    test "MockCritiquer implements critique correctly" do
      candidate = Candidate.new!(%{id: "1", content: "test response"})

      assert {:ok, result} = MockCritiquer.critique(candidate, %{})

      assert result.severity == 0.5
      assert length(result.issues) > 0
    end

    test "critique includes content in issues" do
      candidate = Candidate.new!(%{id: "1", content: "specific content"})

      assert {:ok, result} = MockCritiquer.critique(candidate, %{})

      assert Enum.any?(result.issues, fn issue ->
        String.contains?(issue, "specific content")
      end)
    end
  end

  describe "critique_batch/3 default implementation" do
    test "calls critique for each candidate" do
      candidates = [
        Candidate.new!(%{id: "1", content: "response 1"}),
        Candidate.new!(%{id: "2", content: "response 2"})
      ]

      assert {:ok, results} = Critique.critique_batch(candidates, %{}, MockCritiquer)

      assert length(results) == 2
      assert Enum.all?(results, fn r -> r.severity == 0.5 end)
    end

    test "returns error when any critique fails" do
      candidates = [
        Candidate.new!(%{id: "1", content: "ok"}),
        Candidate.new!(%{id: "2", content: "bad"})
      ]

      result = Critique.critique_batch(candidates, %{}, FailingCritiquer)

      assert {:error, :batch_critique_failed} = result
    end

    test "handles empty candidate list" do
      assert {:ok, results} = Critique.critique_batch([], %{}, MockCritiquer)

      assert results == []
    end
  end

  describe "custom critique_batch implementation" do
    test "uses custom batch implementation when available" do
      candidates = [
        Candidate.new!(%{id: "1", content: "response 1"}),
        Candidate.new!(%{id: "2", content: "response 2"})
      ]

      assert {:ok, results} = BatchCritiquer.critique_batch(candidates, %{})

      assert length(results) == 2
      # Custom batch returns 0.4, default would return 0.3
      assert Enum.all?(results, fn r -> r.severity == 0.4 end)
    end
  end

  describe "critiquer?/1" do
    test "returns true for modules implementing Critique behavior" do
      assert Critique.critiquer?(MockCritiquer) == true
      assert Critique.critiquer?(BatchCritiquer) == true
    end

    test "returns false for modules not implementing Critique behavior" do
      assert Critique.critiquer?(List) == false
      assert Critique.critiquer?(Map) == false
    end

    test "returns false for non-modules" do
      assert Critique.critiquer?(nil) == false
      assert Critique.critiquer?("string") == false
    end
  end

  describe "behaviour/0" do
    test "returns the Critique module" do
      assert Critique.behaviour() == Critique
    end
  end

  describe "context handling" do
    test "critique receives context map" do
      defmodule ContextCritiquer do
        @behaviour Critique

        @impl true
        def critique(_candidate, context) do
          domain = Map.get(context, :domain, :general)
          {:ok, CritiqueResult.new!(%{severity: 0.2, issues: ["#{domain} issue"]})}
        end
      end

      candidate = Candidate.new!(%{id: "1", content: "test"})

      assert {:ok, result} = ContextCritiquer.critique(candidate, %{domain: :math})
      assert Enum.any?(result.issues, &String.contains?(&1, "math"))
    end

    test "works with empty context" do
      candidate = Candidate.new!(%{id: "1", content: "test"})

      assert {:ok, _result} = MockCritiquer.critique(candidate, %{})
    end
  end
end
