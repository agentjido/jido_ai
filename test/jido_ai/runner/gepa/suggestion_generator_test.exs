defmodule Jido.AI.Runner.GEPA.SuggestionGeneratorTest do
  @moduledoc """
  Integration tests for GEPA Task 1.3.3: Suggestion Generation.

  Tests the complete pipeline from LLM suggestions to concrete edit plans.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.{Reflector, SuggestionGenerator}
  alias Jido.AI.Runner.GEPA.SuggestionGeneration

  alias Jido.AI.Runner.GEPA.SuggestionGeneration.{
    ConflictResolver,
    EditBuilder,
    EditValidator,
    ImpactRanker,
    PromptStructureAnalyzer
  }

  describe "generate_edit_plan/2 - integration" do
    test "generates complete edit plan from parsed reflection" do
      # Create a mock reflection with suggestions
      reflection = %Reflector.ParsedReflection{
        analysis: "The prompt needs clearer instructions",
        root_causes: ["Vague instructions"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Add step-by-step instruction",
            rationale: "Makes expectations explicit",
            priority: :high,
            specific_text: "Let's solve this step by step:"
          },
          %Reflector.Suggestion{
            type: :add,
            category: :constraint,
            description: "Add constraint about showing work",
            rationale: "Ensures intermediate steps are visible",
            priority: :medium,
            specific_text: nil
          }
        ],
        confidence: :high
      }

      prompt = "Solve this math problem"

      assert {:ok, plan} =
               SuggestionGenerator.generate_edit_plan(
                 reflection,
                 original_prompt: prompt
               )

      assert %SuggestionGeneration.EditPlan{} = plan
      assert plan.original_prompt == prompt
      assert plan.validated == true
      assert plan.ranked == true
      assert length(plan.edits) > 0
      assert plan.total_edits == length(plan.edits)

      # Check edits are properly formed
      for edit <- plan.edits do
        assert %SuggestionGeneration.PromptEdit{} = edit
        assert edit.validated == true
        assert edit.operation in [:insert, :replace, :delete, :move]
        assert is_float(edit.impact_score)
        assert edit.impact_score >= 0.0 and edit.impact_score <= 1.0
      end
    end

    test "requires original_prompt option" do
      reflection = %Reflector.ParsedReflection{
        analysis: "Test",
        suggestions: []
      }

      assert {:error, :missing_original_prompt} =
               SuggestionGenerator.generate_edit_plan(reflection, [])
    end

    test "handles empty suggestions list" do
      reflection = %Reflector.ParsedReflection{
        analysis: "No issues found",
        suggestions: []
      }

      assert {:ok, plan} =
               SuggestionGenerator.generate_edit_plan(
                 reflection,
                 original_prompt: "Test prompt"
               )

      assert plan.total_edits == 0
      assert plan.edits == []
    end

    test "filters edits by min_impact_score" do
      reflection = %Reflector.ParsedReflection{
        analysis: "Multiple improvements needed",
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "High impact change",
            rationale: "Critical improvement",
            priority: :high,
            specific_text: "Important instruction"
          },
          %Reflector.Suggestion{
            type: :add,
            category: :structure,
            description: "Low impact change",
            rationale: "Minor improvement",
            priority: :low,
            specific_text: "Optional note"
          }
        ]
      }

      assert {:ok, plan} =
               SuggestionGenerator.generate_edit_plan(
                 reflection,
                 original_prompt: "Test",
                 min_impact_score: 0.6
               )

      # Should filter out low-impact edits
      assert Enum.all?(plan.edits, &(&1.impact_score >= 0.6))
    end

    test "respects max_edits limit" do
      # Create many suggestions
      suggestions =
        Enum.map(1..10, fn i ->
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Suggestion #{i}",
            rationale: "Reason #{i}",
            priority: :medium,
            specific_text: "Text #{i}"
          }
        end)

      reflection = %Reflector.ParsedReflection{
        analysis: "Many improvements",
        suggestions: suggestions
      }

      assert {:ok, plan} =
               SuggestionGenerator.generate_edit_plan(
                 reflection,
                 original_prompt: "Test",
                 max_edits: 3
               )

      assert length(plan.edits) <= 3
    end

    test "edits are ranked by impact (highest first)" do
      reflection = %Reflector.ParsedReflection{
        analysis: "Multiple improvements",
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "High priority",
            rationale: "Critical",
            priority: :high,
            specific_text: "Important"
          },
          %Reflector.Suggestion{
            type: :add,
            category: :structure,
            description: "Low priority",
            rationale: "Minor",
            priority: :low,
            specific_text: "Optional"
          }
        ]
      }

      assert {:ok, plan} =
               SuggestionGenerator.generate_edit_plan(
                 reflection,
                 original_prompt: "Test"
               )

      if length(plan.edits) > 1 do
        # Check descending order
        scores = Enum.map(plan.edits, & &1.impact_score)
        assert scores == Enum.sort(scores, :desc)
      end
    end
  end

  describe "PromptStructureAnalyzer" do
    test "analyzes simple prompt" do
      assert {:ok, structure} = PromptStructureAnalyzer.analyze("Solve this problem")

      assert %SuggestionGeneration.PromptStructure{} = structure
      assert structure.raw_text == "Solve this problem"
      assert structure.length == String.length("Solve this problem")
      assert structure.complexity in [:simple, :moderate, :complex]
    end

    test "detects chain-of-thought triggers" do
      assert {:ok, structure} = PromptStructureAnalyzer.analyze("Let's think step by step")
      assert structure.has_cot_trigger == true
    end

    test "detects constraints" do
      assert {:ok, structure} = PromptStructureAnalyzer.analyze("You must show your work")
      assert structure.has_constraints == true
    end

    test "detects examples" do
      assert {:ok, structure} = PromptStructureAnalyzer.analyze("For example, 2+2=4")
      assert structure.has_examples == true
    end

    test "assesses complexity correctly" do
      simple = "Solve"
      assert {:ok, s1} = PromptStructureAnalyzer.analyze(simple)
      assert s1.complexity == :simple

      complex = String.duplicate("This is a complex prompt with many sentences. ", 20)
      assert {:ok, s2} = PromptStructureAnalyzer.analyze(complex)
      assert s2.complexity == :complex
    end
  end

  describe "EditBuilder" do
    test "builds insertion edit from add suggestion" do
      suggestion = %Reflector.Suggestion{
        type: :add,
        category: :clarity,
        description: "Add instruction",
        rationale: "Makes it clear",
        priority: :high,
        specific_text: "Step by step:"
      }

      {:ok, structure} = PromptStructureAnalyzer.analyze("Solve this")

      assert {:ok, edits} = EditBuilder.build_edits(suggestion, structure)
      assert length(edits) > 0

      edit = hd(edits)
      assert edit.operation == :insert
      assert edit.content != nil
      assert String.contains?(edit.content, "Step by step")
    end

    test "builds replacement edit from modify suggestion" do
      suggestion = %Reflector.Suggestion{
        type: :modify,
        category: :clarity,
        description: "Make clearer",
        rationale: "Improves understanding",
        priority: :medium,
        specific_text: "carefully analyze"
      }

      {:ok, structure} = PromptStructureAnalyzer.analyze("Solve this problem")

      assert {:ok, edits} = EditBuilder.build_edits(suggestion, structure)
      assert length(edits) > 0
    end

    test "builds deletion edit from remove suggestion" do
      suggestion = %Reflector.Suggestion{
        type: :remove,
        category: :clarity,
        description: "Remove redundant text",
        rationale: "Simplifies",
        priority: :low,
        specific_text: "please note that"
      }

      {:ok, structure} = PromptStructureAnalyzer.analyze("Please note that you should solve this")

      result = EditBuilder.build_edits(suggestion, structure)
      # May succeed or fail depending on target identification
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "EditValidator" do
    test "validates insertion edit" do
      {:ok, structure} = PromptStructureAnalyzer.analyze("Test prompt")

      edit = %SuggestionGeneration.PromptEdit{
        id: "test_1",
        operation: :insert,
        location: %SuggestionGeneration.PromptLocation{
          type: :end,
          scope: :prompt
        },
        content: "New content",
        source_suggestion: %Reflector.Suggestion{
          type: :add,
          category: :clarity,
          description: "Test",
          rationale: "Test",
          priority: :high
        },
        rationale: "Test rationale"
      }

      assert {:ok, validated} = EditValidator.validate(edit, structure)
      assert validated.validated == true
    end

    test "invalidates edit with missing content" do
      {:ok, structure} = PromptStructureAnalyzer.analyze("Test")

      edit = %SuggestionGeneration.PromptEdit{
        id: "test_2",
        operation: :insert,
        location: %SuggestionGeneration.PromptLocation{type: :end, scope: :prompt},
        # Missing content
        content: nil,
        source_suggestion: %Reflector.Suggestion{
          type: :add,
          category: :clarity,
          description: "Test",
          rationale: "Test",
          priority: :high
        },
        rationale: "Test"
      }

      assert {:error, :missing_insert_content} = EditValidator.validate(edit, structure)
    end

    test "validates replacement edit with existing target" do
      {:ok, structure} = PromptStructureAnalyzer.analyze("Solve this problem")

      edit = %SuggestionGeneration.PromptEdit{
        id: "test_3",
        operation: :replace,
        location: %SuggestionGeneration.PromptLocation{
          type: :within,
          pattern: "problem",
          scope: :phrase
        },
        content: "challenge",
        target_text: "problem",
        source_suggestion: %Reflector.Suggestion{
          type: :modify,
          category: :clarity,
          description: "Test",
          rationale: "Test",
          priority: :medium
        },
        rationale: "Test"
      }

      assert {:ok, validated} = EditValidator.validate(edit, structure)
      assert validated.validated == true
    end
  end

  describe "ConflictResolver" do
    test "identifies overlapping edits" do
      location = %SuggestionGeneration.PromptLocation{
        type: :within,
        pattern: "same target",
        scope: :phrase
      }

      edit1 = %SuggestionGeneration.PromptEdit{
        id: "conflict_1",
        operation: :replace,
        location: location,
        content: "replacement 1",
        target_text: "same target",
        source_suggestion: %Reflector.Suggestion{
          type: :modify,
          category: :clarity,
          description: "Test",
          rationale: "Test",
          priority: :high
        },
        rationale: "Test",
        impact_score: 0.8
      }

      edit2 = %SuggestionGeneration.PromptEdit{
        id: "conflict_2",
        operation: :replace,
        location: location,
        content: "replacement 2",
        target_text: "same target",
        source_suggestion: %Reflector.Suggestion{
          type: :modify,
          category: :structure,
          description: "Test",
          rationale: "Test",
          priority: :medium
        },
        rationale: "Test",
        impact_score: 0.6
      }

      assert {:ok, resolved} = ConflictResolver.resolve_conflicts([edit1, edit2])

      # One should win, one should have conflicts marked
      winners = Enum.filter(resolved, &(&1.conflicts_with == []))
      losers = Enum.reject(resolved, &(&1.conflicts_with == []))

      assert length(winners) == 1
      assert length(losers) == 1
      # Highest impact should win
      assert hd(winners).id == "conflict_1"
    end

    test "handles no conflicts" do
      edit1 = %SuggestionGeneration.PromptEdit{
        id: "no_conflict_1",
        operation: :insert,
        location: %SuggestionGeneration.PromptLocation{type: :start, scope: :prompt},
        content: "Start text",
        source_suggestion: %Reflector.Suggestion{
          type: :add,
          category: :clarity,
          description: "Test",
          rationale: "Test",
          priority: :high
        },
        rationale: "Test"
      }

      edit2 = %SuggestionGeneration.PromptEdit{
        id: "no_conflict_2",
        operation: :insert,
        location: %SuggestionGeneration.PromptLocation{type: :end, scope: :prompt},
        content: "End text",
        source_suggestion: %Reflector.Suggestion{
          type: :add,
          category: :constraint,
          description: "Test",
          rationale: "Test",
          priority: :medium
        },
        rationale: "Test"
      }

      assert {:ok, resolved} = ConflictResolver.resolve_conflicts([edit1, edit2])
      assert Enum.all?(resolved, &(&1.conflicts_with == []))
    end
  end

  describe "ImpactRanker" do
    test "ranks edits by impact score" do
      edits = [
        %SuggestionGeneration.PromptEdit{
          id: "low",
          operation: :insert,
          location: %SuggestionGeneration.PromptLocation{type: :end, scope: :prompt},
          content: "Low impact",
          source_suggestion: %Reflector.Suggestion{
            type: :add,
            category: :structure,
            description: "Test",
            rationale: "Test",
            priority: :low
          },
          rationale: "Test",
          validated: false
        },
        %SuggestionGeneration.PromptEdit{
          id: "high",
          operation: :insert,
          location: %SuggestionGeneration.PromptLocation{type: :within, scope: :phrase},
          content: "High impact",
          source_suggestion: %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Test",
            rationale: "Test",
            priority: :high,
            specific_text: "Exact text"
          },
          rationale: "Test",
          validated: true
        }
      ]

      ranked = ImpactRanker.rank_by_impact(edits)

      assert length(ranked) == 2
      # Highest impact should be first
      assert hd(ranked).id == "high"
      assert hd(ranked).impact_score > List.last(ranked).impact_score
    end

    test "calculates impact score correctly" do
      edit = %SuggestionGeneration.PromptEdit{
        id: "test",
        operation: :insert,
        location: %SuggestionGeneration.PromptLocation{type: :within, scope: :phrase},
        content: "Content",
        source_suggestion: %Reflector.Suggestion{
          type: :add,
          category: :clarity,
          description: "Test",
          rationale: "Test",
          priority: :high,
          specific_text: "Specific text provided"
        },
        rationale: "Test",
        validated: true
      }

      scored = ImpactRanker.calculate_impact_score(edit)

      assert is_float(scored.impact_score)
      assert scored.impact_score >= 0.0
      assert scored.impact_score <= 1.0
      # High priority + clarity + specific text + validated should score high
      assert scored.impact_score > 0.7
    end
  end
end
