defmodule Jido.Eval.Metrics.UtilsTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.Metrics.Utils

  doctest Jido.Eval.Metrics.Utils

  describe "build_prompt/2" do
    test "substitutes variables in template" do
      template = "Rate this {{response}} with context {{context}}"
      variables = %{response: "Hello", context: "World"}

      result = Utils.build_prompt(template, variables)

      assert result == "Rate this Hello with context World"
    end

    test "handles missing variables by leaving placeholders" do
      template = "{{question}} leads to {{answer}}"
      variables = %{question: "What"}

      result = Utils.build_prompt(template, variables)

      assert result == "What leads to {{answer}}"
    end

    test "handles empty variables map" do
      template = "No {{variables}} here"
      variables = %{}

      result = Utils.build_prompt(template, variables)

      assert result == "No {{variables}} here"
    end

    test "converts non-string values to strings" do
      template = "Score: {{score}}, Count: {{count}}"
      variables = %{score: 0.85, count: 42}

      result = Utils.build_prompt(template, variables)

      assert result == "Score: 0.85, Count: 42"
    end
  end

  describe "normalize_score/2" do
    test "keeps scores within range unchanged" do
      assert Utils.normalize_score(0.5, {0.0, 1.0}) == 0.5
      assert Utils.normalize_score(0.0, {0.0, 1.0}) == 0.0
      assert Utils.normalize_score(1.0, {0.0, 1.0}) == 1.0
    end

    test "normalizes scores from 0-10 scale" do
      assert Utils.normalize_score(8.5, {0.0, 1.0}) == 0.85
      assert Utils.normalize_score(10, {0.0, 1.0}) == 1.0
    end

    test "normalizes scores from 0-100 scale" do
      assert Utils.normalize_score(85, {0.0, 1.0}) == 0.85
      assert Utils.normalize_score(100, {0.0, 1.0}) == 1.0
    end

    test "clamps scores below minimum to minimum" do
      assert Utils.normalize_score(-0.5, {0.0, 1.0}) == 0.0
    end

    test "handles large scores by clamping to maximum" do
      assert Utils.normalize_score(1000, {0.0, 1.0}) == 1.0
    end
  end

  describe "extract_score/1" do
    test "extracts score with 'Score:' prefix" do
      assert {:ok, 0.8} = Utils.extract_score("The score is 0.8")
      assert {:ok, 0.8} = Utils.extract_score("Score: 0.8")
      assert {:ok, 0.8} = Utils.extract_score("SCORE: 0.8")
    end

    test "extracts fractions" do
      assert {:ok, 0.8} = Utils.extract_score("4/5")
      assert {:ok, 0.8} = Utils.extract_score("Rating: 4 / 5")
      assert {:ok, 0.75} = Utils.extract_score("3/4")
    end

    test "extracts rating with prefix" do
      assert {:ok, 0.9} = Utils.extract_score("Rating: 0.9")
      assert {:ok, 0.9} = Utils.extract_score("RATING: 0.9")
    end

    test "extracts standalone decimal numbers" do
      assert {:ok, 0.85} = Utils.extract_score("The result is 0.85 overall")
    end

    test "extracts standalone integers when no decimals" do
      assert {:ok, 8.0} = Utils.extract_score("The result is 8 points")
    end

    test "returns error when no score found" do
      assert {:error, :no_score_found} = Utils.extract_score("No score here")
      assert {:error, :no_score_found} = Utils.extract_score("Just text")
    end

    test "handles edge cases" do
      assert {:ok, score} = Utils.extract_score("Score: 0")
      assert score == +0.0
      assert {:ok, 1.0} = Utils.extract_score("Perfect score: 1.0")
    end
  end

  describe "format_contexts/1" do
    test "formats contexts with numbering" do
      contexts = ["First context", "Second context", "Third context"]

      result = Utils.format_contexts(contexts)
      expected = "Context 1: First context\nContext 2: Second context\nContext 3: Third context"

      assert result == expected
    end

    test "handles single context" do
      contexts = ["Only context"]

      result = Utils.format_contexts(contexts)

      assert result == "Context 1: Only context"
    end

    test "handles empty list" do
      contexts = []

      result = Utils.format_contexts(contexts)

      assert result == ""
    end
  end

  describe "parse_boolean/1" do
    test "parses yes responses" do
      assert {:ok, true} = Utils.parse_boolean("Yes")
      assert {:ok, true} = Utils.parse_boolean("YES")
      assert {:ok, true} = Utils.parse_boolean("yes")
      assert {:ok, true} = Utils.parse_boolean("Yes, this is correct")
    end

    test "parses no responses" do
      assert {:ok, false} = Utils.parse_boolean("No")
      assert {:ok, false} = Utils.parse_boolean("NO")
      assert {:ok, false} = Utils.parse_boolean("no")
      assert {:ok, false} = Utils.parse_boolean("No, this is wrong")
    end

    test "parses true responses" do
      assert {:ok, true} = Utils.parse_boolean("True")
      assert {:ok, true} = Utils.parse_boolean("true")
      assert {:ok, true} = Utils.parse_boolean("This is true")
    end

    test "parses false responses" do
      assert {:ok, false} = Utils.parse_boolean("False")
      assert {:ok, false} = Utils.parse_boolean("false")
      assert {:ok, false} = Utils.parse_boolean("This is false")
    end

    test "parses numeric responses" do
      assert {:ok, true} = Utils.parse_boolean("1")
      assert {:ok, true} = Utils.parse_boolean("1 - correct")
      assert {:ok, false} = Utils.parse_boolean("0")
      assert {:ok, false} = Utils.parse_boolean("0 - incorrect")
    end

    test "returns error for ambiguous responses" do
      assert {:error, :no_boolean_found} = Utils.parse_boolean("Maybe")
      assert {:error, :no_boolean_found} = Utils.parse_boolean("Uncertain")
      assert {:error, :no_boolean_found} = Utils.parse_boolean("Could be either")
    end

    test "handles whitespace" do
      assert {:ok, true} = Utils.parse_boolean("  Yes  ")
      assert {:ok, false} = Utils.parse_boolean("  No  ")
    end
  end
end
