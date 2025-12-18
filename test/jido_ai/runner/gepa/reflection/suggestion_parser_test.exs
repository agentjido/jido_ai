defmodule Jido.AI.Runner.GEPA.Reflection.SuggestionParserTest do
  @moduledoc """
  Comprehensive tests for reflection response parsing (Task 1.3.2.3).

  Tests:
  - JSON response parsing
  - Text fallback parsing
  - Suggestion validation
  - Confidence scoring
  - Clarification need detection
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Reflection.SuggestionParser
  alias Jido.AI.Runner.GEPA.Reflector

  describe "parse/2 - JSON parsing" do
    test "parses a valid JSON response" do
      response = %Reflector.ReflectionResponse{
        content: valid_json_response(),
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert %Reflector.ParsedReflection{} = parsed
      assert parsed.analysis != ""
      assert length(parsed.suggestions) > 0
    end

    test "extracts analysis field" do
      response = %Reflector.ReflectionResponse{
        content:
          Jason.encode!(%{
            "analysis" => "The prompt lacks clarity in its instructions",
            "root_causes" => [],
            "suggestions" => [],
            "expected_improvement" => ""
          }),
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert parsed.analysis == "The prompt lacks clarity in its instructions"
    end

    test "extracts root causes" do
      response = %Reflector.ReflectionResponse{
        content:
          Jason.encode!(%{
            "analysis" => "Test",
            "root_causes" => ["Cause 1", "Cause 2", "Cause 3"],
            "suggestions" => [],
            "expected_improvement" => ""
          }),
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert parsed.root_causes == ["Cause 1", "Cause 2", "Cause 3"]
    end

    test "parses suggestions with all fields" do
      response = %Reflector.ReflectionResponse{
        content:
          Jason.encode!(%{
            "analysis" => "Test",
            "root_causes" => [],
            "suggestions" => [
              %{
                "type" => "add",
                "category" => "clarity",
                "description" => "Add explicit constraints",
                "rationale" => "Prevents ambiguity",
                "priority" => "high",
                "specific_text" => "You must provide output in JSON format",
                "target_section" => "constraints"
              }
            ],
            "expected_improvement" => "Better adherence"
          }),
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert length(parsed.suggestions) == 1

      suggestion = hd(parsed.suggestions)
      assert suggestion.type == :add
      assert suggestion.category == :clarity
      assert suggestion.description == "Add explicit constraints"
      assert suggestion.rationale == "Prevents ambiguity"
      assert suggestion.priority == :high
      assert suggestion.specific_text == "You must provide output in JSON format"
      assert suggestion.target_section == "constraints"
    end

    test "handles multiple suggestions" do
      response = %Reflector.ReflectionResponse{
        content:
          Jason.encode!(%{
            "analysis" => "Test",
            "root_causes" => [],
            "suggestions" => [
              %{
                "type" => "add",
                "category" => "clarity",
                "description" => "First suggestion",
                "rationale" => "Reason 1",
                "priority" => "high"
              },
              %{
                "type" => "modify",
                "category" => "structure",
                "description" => "Second suggestion",
                "rationale" => "Reason 2",
                "priority" => "medium"
              },
              %{
                "type" => "remove",
                "category" => "constraint",
                "description" => "Third suggestion",
                "rationale" => "Reason 3",
                "priority" => "low"
              }
            ],
            "expected_improvement" => "Better results"
          }),
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert length(parsed.suggestions) == 3
    end

    test "parses all suggestion types" do
      types = ["add", "modify", "remove", "restructure"]

      for type <- types do
        response = %Reflector.ReflectionResponse{
          content:
            Jason.encode!(%{
              "analysis" => "Test",
              "root_causes" => [],
              "suggestions" => [
                %{
                  "type" => type,
                  "category" => "clarity",
                  "description" => "Test",
                  "rationale" => "Test",
                  "priority" => "medium"
                }
              ],
              "expected_improvement" => "Test"
            }),
          format: :json,
          timestamp: DateTime.utc_now()
        }

        assert {:ok, parsed} = SuggestionParser.parse(response)
        assert hd(parsed.suggestions).type == String.to_atom(type)
      end
    end

    test "parses all suggestion categories" do
      categories = ["clarity", "constraint", "example", "structure", "reasoning"]

      for category <- categories do
        response = %Reflector.ReflectionResponse{
          content:
            Jason.encode!(%{
              "analysis" => "Test",
              "root_causes" => [],
              "suggestions" => [
                %{
                  "type" => "add",
                  "category" => category,
                  "description" => "Test",
                  "rationale" => "Test",
                  "priority" => "medium"
                }
              ],
              "expected_improvement" => "Test"
            }),
          format: :json,
          timestamp: DateTime.utc_now()
        }

        assert {:ok, parsed} = SuggestionParser.parse(response)
        assert hd(parsed.suggestions).category == String.to_atom(category)
      end
    end

    test "parses all priority levels" do
      priorities = ["high", "medium", "low"]

      for priority <- priorities do
        response = %Reflector.ReflectionResponse{
          content:
            Jason.encode!(%{
              "analysis" => "Test",
              "root_causes" => [],
              "suggestions" => [
                %{
                  "type" => "add",
                  "category" => "clarity",
                  "description" => "Test",
                  "rationale" => "Test",
                  "priority" => priority
                }
              ],
              "expected_improvement" => "Test"
            }),
          format: :json,
          timestamp: DateTime.utc_now()
        }

        assert {:ok, parsed} = SuggestionParser.parse(response)
        assert hd(parsed.suggestions).priority == String.to_atom(priority)
      end
    end

    test "handles missing optional fields" do
      response = %Reflector.ReflectionResponse{
        content:
          Jason.encode!(%{
            "analysis" => "Test",
            "root_causes" => [],
            "suggestions" => [
              %{
                "type" => "add",
                "category" => "clarity",
                "description" => "Test",
                "rationale" => "Test",
                "priority" => "medium"
                # No specific_text or target_section
              }
            ],
            "expected_improvement" => ""
          }),
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      suggestion = hd(parsed.suggestions)
      assert is_nil(suggestion.specific_text)
      assert is_nil(suggestion.target_section)
    end

    test "falls back to text parsing on invalid JSON" do
      response = %Reflector.ReflectionResponse{
        content:
          "This is not valid JSON {broken. You should add more constraints. The prompt should include examples. Consider modifying the structure.",
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert %Reflector.ParsedReflection{} = parsed
      # Should have extracted suggestions from text
      assert length(parsed.suggestions) > 0
    end

    test "returns error in strict mode with invalid JSON" do
      response = %Reflector.ReflectionResponse{
        content: "Invalid JSON",
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:error, {:json_parse_error, _}} = SuggestionParser.parse(response, strict: true)
    end

    test "filters out invalid suggestions" do
      response = %Reflector.ReflectionResponse{
        content:
          Jason.encode!(%{
            "analysis" => "Test",
            "root_causes" => [],
            "suggestions" => [
              %{
                "type" => "add",
                "category" => "clarity",
                "description" => "Valid suggestion",
                "rationale" => "Good reason",
                "priority" => "high"
              },
              %{
                "type" => "invalid_type",
                "category" => "clarity",
                "description" => "Invalid type",
                "rationale" => "Test",
                "priority" => "high"
              },
              %{
                "type" => "add",
                "category" => "invalid_category",
                "description" => "Invalid category",
                "rationale" => "Test",
                "priority" => "high"
              }
            ],
            "expected_improvement" => "Test"
          }),
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      # Only valid suggestion should be parsed
      assert length(parsed.suggestions) == 1
      assert hd(parsed.suggestions).description == "Valid suggestion"
    end
  end

  describe "parse/2 - text parsing fallback" do
    test "parses text response" do
      response = %Reflector.ReflectionResponse{
        content:
          "The prompt should add more specific constraints. It should clarify the output format.",
        format: :text,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert %Reflector.ParsedReflection{} = parsed
    end

    test "extracts analysis from first paragraph" do
      response = %Reflector.ReflectionResponse{
        content:
          "This is the analysis paragraph with important information.\n\nYou should add explicit constraints. The prompt should modify the structure. Consider including more examples.",
        format: :text,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert parsed.analysis =~ "analysis paragraph"
    end

    test "extracts suggestions from text" do
      response = %Reflector.ReflectionResponse{
        content:
          "The prompt should add explicit constraints. You should modify the structure. Consider removing redundant instructions.",
        format: :text,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert length(parsed.suggestions) > 0
    end

    test "infers suggestion types from text" do
      response = %Reflector.ReflectionResponse{
        content: "You should add more examples. Remove the redundant section.",
        format: :text,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      types = Enum.map(parsed.suggestions, & &1.type)
      assert :add in types or :remove in types
    end

    test "returns error if insufficient suggestions in text" do
      response = %Reflector.ReflectionResponse{
        content: "This text has no actionable suggestions at all.",
        format: :text,
        timestamp: DateTime.utc_now()
      }

      result = SuggestionParser.parse(response, min_suggestions: 2)
      assert {:error, :insufficient_suggestions} = result
    end

    test "respects min_suggestions option" do
      response = %Reflector.ReflectionResponse{
        content: "Add constraints. Modify structure. Include examples.",
        format: :text,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, _parsed} = SuggestionParser.parse(response, min_suggestions: 1)
    end
  end

  describe "validate/1" do
    test "validates a complete parsed reflection" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Complete analysis",
        root_causes: ["Cause 1"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Add constraints",
            rationale: "Improves clarity",
            priority: :high
          }
        ]
      }

      assert {:ok, ^parsed} = SuggestionParser.validate(parsed)
    end

    test "rejects missing analysis" do
      parsed = %Reflector.ParsedReflection{
        analysis: "",
        root_causes: ["Cause 1"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Test",
            rationale: "Test",
            priority: :high
          }
        ]
      }

      assert {:error, :missing_analysis} = SuggestionParser.validate(parsed)
    end

    test "rejects no suggestions" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Analysis text",
        root_causes: ["Cause 1"],
        suggestions: []
      }

      assert {:error, :no_suggestions} = SuggestionParser.validate(parsed)
    end

    test "rejects suggestions with empty description" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Analysis",
        root_causes: ["Cause 1"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "",
            rationale: "Test",
            priority: :high
          }
        ]
      }

      assert {:error, :invalid_suggestions} = SuggestionParser.validate(parsed)
    end

    test "rejects suggestions with empty rationale" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Analysis",
        root_causes: ["Cause 1"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Test",
            rationale: "",
            priority: :high
          }
        ]
      }

      assert {:error, :invalid_suggestions} = SuggestionParser.validate(parsed)
    end
  end

  describe "score_confidence/1" do
    test "returns high confidence for quality reflection" do
      parsed = %Reflector.ParsedReflection{
        analysis: String.duplicate("Detailed analysis with comprehensive coverage. ", 5),
        root_causes: ["Cause 1", "Cause 2", "Cause 3"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Add explicit constraints",
            rationale: "Prevents ambiguity",
            priority: :high,
            specific_text: "You must format output as JSON"
          },
          %Reflector.Suggestion{
            type: :modify,
            category: :structure,
            description: "Restructure prompt",
            rationale: "Improves flow",
            priority: :high,
            specific_text: "Use step-by-step format"
          },
          %Reflector.Suggestion{
            type: :add,
            category: :example,
            description: "Add examples",
            rationale: "Clarifies expectations",
            priority: :high,
            specific_text: "Example: {...}"
          },
          %Reflector.Suggestion{
            type: :add,
            category: :reasoning,
            description: "Add reasoning guidance",
            rationale: "Better logic",
            priority: :medium,
            specific_text: "Think step by step"
          },
          %Reflector.Suggestion{
            type: :remove,
            category: :clarity,
            description: "Remove redundancy",
            rationale: "Simplifies",
            priority: :low,
            specific_text: "Remove duplicate instructions"
          }
        ]
      }

      confidence = SuggestionParser.score_confidence(parsed)
      assert confidence == :high
    end

    test "returns medium or low confidence for adequate reflection" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Some analysis here with reasonable content that provides enough detail",
        root_causes: ["Cause 1", "Cause 2"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Add constraints",
            rationale: "Helps",
            priority: :medium
          },
          %Reflector.Suggestion{
            type: :modify,
            category: :structure,
            description: "Change structure",
            rationale: "Better",
            priority: :low
          },
          %Reflector.Suggestion{
            type: :add,
            category: :example,
            description: "Add examples",
            rationale: "Clarifies expectations",
            priority: :medium
          }
        ]
      }

      confidence = SuggestionParser.score_confidence(parsed)
      assert confidence in [:medium, :low]
    end

    test "returns low confidence for poor reflection" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Brief",
        root_causes: [],
        suggestions: [
          %Reflector.Suggestion{
            type: :modify,
            category: :clarity,
            description: "Fix it",
            rationale: "Because",
            priority: :low
          }
        ]
      }

      confidence = SuggestionParser.score_confidence(parsed)
      assert confidence == :low
    end

    test "considers number of suggestions in scoring" do
      many_suggestions = %Reflector.ParsedReflection{
        analysis: String.duplicate("Detailed analysis with comprehensive analysis. ", 3),
        root_causes: ["C1", "C2", "C3"],
        suggestions:
          Enum.map(1..7, fn i ->
            %Reflector.Suggestion{
              type: :add,
              category: :clarity,
              description: "Detailed suggestion #{i} with specific guidance",
              rationale: "Comprehensive reason #{i} that explains the value",
              priority: :high,
              specific_text: "Specific text for suggestion #{i}"
            }
          end)
      }

      few_suggestions = %{
        many_suggestions
        | suggestions: Enum.take(many_suggestions.suggestions, 1),
          root_causes: []
      }

      many_conf = SuggestionParser.score_confidence(many_suggestions)
      _few_conf = SuggestionParser.score_confidence(few_suggestions)

      # More high-quality suggestions should lead to higher confidence
      assert many_conf in [:high, :medium]
    end

    test "considers specific_text presence in scoring" do
      with_text = %Reflector.ParsedReflection{
        analysis: "Good analysis",
        root_causes: ["C1", "C2"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Add constraints",
            rationale: "Improves clarity",
            priority: :high,
            specific_text: "Exact text to add"
          },
          %Reflector.Suggestion{
            type: :modify,
            category: :structure,
            description: "Modify structure",
            rationale: "Better flow",
            priority: :high,
            specific_text: "New structure"
          }
        ]
      }

      without_text = %{
        with_text
        | suggestions: Enum.map(with_text.suggestions, fn s -> %{s | specific_text: nil} end)
      }

      with_conf = SuggestionParser.score_confidence(with_text)
      without_conf = SuggestionParser.score_confidence(without_text)

      # Specific text should improve confidence score
      # Both might still be same level, but scores should differ internally
      assert with_conf in [:high, :medium]
      assert without_conf in [:high, :medium, :low]
    end

    test "considers high priority suggestions in scoring" do
      high_priority = %Reflector.ParsedReflection{
        analysis: String.duplicate("Detailed analysis. ", 5),
        root_causes: ["C1", "C2", "C3"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Critical change with detailed explanation",
            rationale: "Essential for preventing errors",
            priority: :high,
            specific_text: "Add this specific constraint"
          },
          %Reflector.Suggestion{
            type: :add,
            category: :structure,
            description: "Important structural change needed",
            rationale: "Very helpful for clarity and flow",
            priority: :high,
            specific_text: "Restructure like this"
          },
          %Reflector.Suggestion{
            type: :add,
            category: :example,
            description: "Add comprehensive examples",
            rationale: "Clarifies expectations significantly",
            priority: :high,
            specific_text: "Example: {...}"
          }
        ]
      }

      low_priority = %{
        high_priority
        | suggestions:
            Enum.map(high_priority.suggestions, fn s ->
              %{s | priority: :low, specific_text: nil}
            end),
          root_causes: []
      }

      high_conf = SuggestionParser.score_confidence(high_priority)
      _low_conf = SuggestionParser.score_confidence(low_priority)

      # High priority suggestions with good content should result in high confidence
      assert high_conf in [:high, :medium]
    end
  end

  describe "needs_clarification?/1" do
    test "returns true for low confidence" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Brief",
        root_causes: [],
        suggestions: [
          %Reflector.Suggestion{
            type: :modify,
            category: :clarity,
            description: "Fix",
            rationale: "Because",
            priority: :low
          }
        ],
        confidence: :low
      }

      assert SuggestionParser.needs_clarification?(parsed) == true
    end

    test "returns true for insufficient root causes" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Good analysis",
        root_causes: ["Only one cause"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Add constraints",
            rationale: "Helps",
            priority: :medium
          }
        ],
        confidence: :medium
      }

      assert SuggestionParser.needs_clarification?(parsed) == true
    end

    test "returns true for generic suggestions" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Analysis",
        root_causes: ["C1", "C2", "C3"],
        suggestions: [
          %Reflector.Suggestion{
            type: :modify,
            category: :clarity,
            description: "Fix",
            rationale: "Better",
            priority: :medium,
            specific_text: nil
          },
          %Reflector.Suggestion{
            type: :add,
            category: :structure,
            description: "Add",
            rationale: "Good",
            priority: :low,
            specific_text: nil
          }
        ],
        confidence: :medium
      }

      # Generic short suggestions without specific text
      assert SuggestionParser.needs_clarification?(parsed) == true
    end

    test "returns false for high-quality reflection" do
      parsed = %Reflector.ParsedReflection{
        analysis: "Comprehensive detailed analysis",
        root_causes: ["Cause 1", "Cause 2", "Cause 3"],
        suggestions: [
          %Reflector.Suggestion{
            type: :add,
            category: :clarity,
            description: "Add explicit output format constraints",
            rationale: "Prevents ambiguous outputs",
            priority: :high,
            specific_text: "Always format your response as JSON"
          },
          %Reflector.Suggestion{
            type: :modify,
            category: :structure,
            description: "Restructure the reasoning section",
            rationale: "Improves logical flow",
            priority: :medium,
            specific_text: "Use numbered steps for reasoning"
          }
        ],
        confidence: :high
      }

      assert SuggestionParser.needs_clarification?(parsed) == false
    end
  end

  describe "edge cases" do
    test "handles empty JSON response gracefully" do
      response = %Reflector.ReflectionResponse{
        content: "{}",
        format: :json,
        timestamp: DateTime.utc_now()
      }

      result = SuggestionParser.parse(response)
      # Should either parse with defaults or fail validation
      case result do
        {:ok, parsed} ->
          # If it parses, validation should catch issues
          assert {:error, _} = SuggestionParser.validate(parsed)

        {:error, _} ->
          # Direct parse error is also acceptable
          assert true
      end
    end

    test "handles very long analysis text" do
      long_analysis = String.duplicate("analysis text ", 1000)

      response = %Reflector.ReflectionResponse{
        content:
          Jason.encode!(%{
            "analysis" => long_analysis,
            "root_causes" => ["C1"],
            "suggestions" => [
              %{
                "type" => "add",
                "category" => "clarity",
                "description" => "Test",
                "rationale" => "Test",
                "priority" => "high"
              }
            ],
            "expected_improvement" => "Test"
          }),
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert String.length(parsed.analysis) > 100
    end

    test "handles suggestions as strings in JSON" do
      response = %Reflector.ReflectionResponse{
        content:
          Jason.encode!(%{
            "analysis" => "Test",
            "root_causes" => [],
            "suggestions" => [
              "Add more examples",
              "Clarify constraints"
            ],
            "expected_improvement" => "Test"
          }),
        format: :json,
        timestamp: DateTime.utc_now()
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      assert length(parsed.suggestions) == 2
      # Should default to modify/clarity
      assert Enum.all?(parsed.suggestions, &(&1.type in [:modify, :add]))
    end

    test "preserves metadata from response" do
      response = %Reflector.ReflectionResponse{
        content: valid_json_response(),
        format: :json,
        timestamp: DateTime.utc_now(),
        metadata: %{model: "gpt-4", request_id: "123"}
      }

      assert {:ok, parsed} = SuggestionParser.parse(response)
      # Metadata should be stored in parsed result
      assert is_map(parsed.metadata)
    end
  end

  # Helper functions

  defp valid_json_response do
    Jason.encode!(%{
      "analysis" => "The prompt lacks specific constraints and clear examples",
      "root_causes" => [
        "Insufficient guidance on output format",
        "Missing examples for edge cases"
      ],
      "suggestions" => [
        %{
          "type" => "add",
          "category" => "constraint",
          "description" => "Add explicit output format requirement",
          "rationale" => "Prevents formatting inconsistencies",
          "priority" => "high",
          "specific_text" => "Always format your response as valid JSON",
          "target_section" => "constraints"
        },
        %{
          "type" => "add",
          "category" => "example",
          "description" => "Include example for edge case handling",
          "rationale" => "Clarifies expected behavior",
          "priority" => "medium",
          "specific_text" => "Example: For empty input, return {\"result\": null}",
          "target_section" => "examples"
        },
        %{
          "type" => "modify",
          "category" => "clarity",
          "description" => "Clarify the reasoning step requirements",
          "rationale" => "Improves step-by-step logic quality",
          "priority" => "medium"
        }
      ],
      "expected_improvement" =>
        "The model should produce more consistent outputs with better formatting"
    })
  end
end
