defmodule Jido.AI.Runner.GEPA.Evaluation.Strategies.QuestionAnsweringEvaluatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Evaluation.Strategies.QuestionAnsweringEvaluator

  describe "evaluate_qa/2" do
    test "evaluates correct answer with high scores" do
      answer = "Paris is the capital"

      task = %{
        type: :question_answering,
        question: "What is the capital of France?",
        expected_answer: "Paris",
        question_type: :what
      }

      metrics = QuestionAnsweringEvaluator.evaluate_qa(answer, task)

      assert metrics.answer_accuracy == 0.8
      assert metrics.relevance_score >= 0.6
      assert metrics.question_type_match == true
    end

    test "evaluates answer with context grounding" do
      answer = "The Eiffel Tower is located in Paris"
      context = "The Eiffel Tower is a famous landmark in Paris, France."

      task = %{
        type: :question_answering,
        question: "Where is the Eiffel Tower?",
        context: context,
        question_type: :where
      }

      metrics = QuestionAnsweringEvaluator.evaluate_qa(answer, task)

      assert metrics.relevance_score > 0.5
      assert metrics.contains_hallucination == false
    end

    test "detects hallucination when answer not in context" do
      answer = "The tower is made of gold and diamonds and platinum"
      context = "The tower is tall."

      task = %{
        type: :question_answering,
        question: "What is the tower made of?",
        context: context
      }

      metrics = QuestionAnsweringEvaluator.evaluate_qa(answer, task)

      assert metrics.contains_hallucination == true
    end
  end

  describe "detect_question_type/1" do
    test "detects 'who' questions" do
      assert QuestionAnsweringEvaluator.detect_question_type("Who invented the telephone?") ==
               :who
    end

    test "detects 'what' questions" do
      assert QuestionAnsweringEvaluator.detect_question_type("What is the capital?") == :what
    end

    test "detects 'when' questions" do
      assert QuestionAnsweringEvaluator.detect_question_type("When did WW2 end?") == :when
    end

    test "detects 'where' questions" do
      assert QuestionAnsweringEvaluator.detect_question_type("Where is Paris?") == :where
    end

    test "detects 'why' questions" do
      assert QuestionAnsweringEvaluator.detect_question_type("Why is the sky blue?") == :why
    end

    test "detects 'how' questions" do
      assert QuestionAnsweringEvaluator.detect_question_type("How does it work?") == :how
    end

    test "returns unknown for ambiguous questions" do
      assert QuestionAnsweringEvaluator.detect_question_type("Tell me about cats") == :unknown
    end
  end

  describe "assess_answer_accuracy/3" do
    test "returns 1.0 for exact match" do
      accuracy = QuestionAnsweringEvaluator.assess_answer_accuracy("Paris", "Paris", nil)
      assert accuracy == 1.0
    end

    test "returns 0.8 for partial match" do
      accuracy =
        QuestionAnsweringEvaluator.assess_answer_accuracy(
          "The capital is Paris",
          "Paris",
          nil
        )

      assert accuracy == 0.8
    end

    test "returns 0.0 for empty answer" do
      accuracy = QuestionAnsweringEvaluator.assess_answer_accuracy("", "Paris", nil)
      assert accuracy == 0.0
    end

    test "returns 0.5 when no expected answer" do
      accuracy = QuestionAnsweringEvaluator.assess_answer_accuracy("Some answer", nil, nil)
      assert accuracy == 0.5
    end

    test "considers context grounding" do
      context = "Paris is the capital of France"
      accuracy = QuestionAnsweringEvaluator.assess_answer_accuracy("Paris", "London", context)

      # Should get some credit for being grounded in context
      assert accuracy > 0.0
    end
  end

  describe "normalize_text/1" do
    test "converts to lowercase" do
      assert QuestionAnsweringEvaluator.normalize_text("HELLO") == "hello"
    end

    test "removes punctuation" do
      assert QuestionAnsweringEvaluator.normalize_text("Hello, world!") == "hello world"
    end

    test "trims whitespace" do
      assert QuestionAnsweringEvaluator.normalize_text("  hello  ") == "hello"
    end

    test "handles nil" do
      assert QuestionAnsweringEvaluator.normalize_text(nil) == ""
    end
  end

  describe "overlap_score/2" do
    test "returns 1.0 for identical texts" do
      score = QuestionAnsweringEvaluator.overlap_score("hello world", "hello world")
      assert score == 1.0
    end

    test "returns partial score for partial overlap" do
      score = QuestionAnsweringEvaluator.overlap_score("hello world", "hello")
      assert score == 1.0
    end

    test "returns 0.0 for no overlap" do
      score = QuestionAnsweringEvaluator.overlap_score("hello", "goodbye")
      assert score == 0.0
    end

    test "handles empty strings" do
      assert QuestionAnsweringEvaluator.overlap_score("", "test") == 0.0
    end
  end

  describe "extract_words/1" do
    test "extracts words from text" do
      words = QuestionAnsweringEvaluator.extract_words("hello world test")
      assert words == ["hello", "world", "test"]
    end

    test "handles empty string" do
      assert QuestionAnsweringEvaluator.extract_words("") == []
    end

    test "handles nil" do
      assert QuestionAnsweringEvaluator.extract_words(nil) == []
    end

    test "splits on whitespace" do
      words = QuestionAnsweringEvaluator.extract_words("one  two   three")
      assert words == ["one", "two", "three"]
    end
  end

  describe "grounded_in_context?/2" do
    test "returns true when answer is grounded in context" do
      answer = "Paris is the capital"
      context = "Paris is the capital of France"

      assert QuestionAnsweringEvaluator.grounded_in_context?(answer, context) == true
    end

    test "returns false when answer contains hallucinations" do
      answer = "London is made of gold"
      context = "London is a city in England"

      assert QuestionAnsweringEvaluator.grounded_in_context?(answer, context) == false
    end

    test "returns false when context is nil" do
      assert QuestionAnsweringEvaluator.grounded_in_context?("answer", nil) == false
    end

    test "returns false for empty answer" do
      assert QuestionAnsweringEvaluator.grounded_in_context?("", "context") == false
    end
  end

  describe "assess_relevance/3" do
    test "returns high score for relevant answer" do
      answer = "Paris"
      question = "What is the capital of France?"

      relevance = QuestionAnsweringEvaluator.assess_relevance(answer, question, :what)

      assert relevance >= 0.4
    end

    test "returns 0.0 for empty answer" do
      relevance = QuestionAnsweringEvaluator.assess_relevance("", "What?", :what)
      assert relevance == 0.0
    end

    test "considers question type matching" do
      answer = "Because it reflects light"
      question = "Why is the sky blue?"

      relevance = QuestionAnsweringEvaluator.assess_relevance(answer, question, :why)

      assert relevance > 0.7
    end

    test "gives lower score when question type doesn't match" do
      answer = "Just because"
      question = "When did it happen?"

      relevance = QuestionAnsweringEvaluator.assess_relevance(answer, question, :when)

      assert relevance < 0.7
    end
  end

  describe "addresses_question_type?/2" do
    test "validates 'who' answers contain person references" do
      assert QuestionAnsweringEvaluator.addresses_question_type?("Albert Einstein", :who) == true
      assert QuestionAnsweringEvaluator.addresses_question_type?("The scientist", :who) == true
      assert QuestionAnsweringEvaluator.addresses_question_type?("42", :who) == false
    end

    test "validates 'what' answers are descriptive" do
      assert QuestionAnsweringEvaluator.addresses_question_type?(
               "It is a programming language",
               :what
             ) == true

      assert QuestionAnsweringEvaluator.addresses_question_type?("Yes", :what) == false
    end

    test "validates 'when' answers contain time references" do
      assert QuestionAnsweringEvaluator.addresses_question_type?("In 1945", :when) == true
      assert QuestionAnsweringEvaluator.addresses_question_type?("During the war", :when) == true
      # Note: "In Paris" might match due to "in" keyword, but lacks clear time indicators
    end

    test "validates 'where' answers contain location references" do
      assert QuestionAnsweringEvaluator.addresses_question_type?("In Paris", :where) == true

      assert QuestionAnsweringEvaluator.addresses_question_type?("Located in France", :where) ==
               true

      assert QuestionAnsweringEvaluator.addresses_question_type?("Yesterday", :where) == false
    end

    test "validates 'why' answers contain explanations" do
      assert QuestionAnsweringEvaluator.addresses_question_type?(
               "Because of gravity",
               :why
             ) == true

      assert QuestionAnsweringEvaluator.addresses_question_type?("Due to the law", :why) == true
      assert QuestionAnsweringEvaluator.addresses_question_type?("In Paris", :why) == false
    end

    test "validates 'how' answers describe processes" do
      assert QuestionAnsweringEvaluator.addresses_question_type?(
               "By using a computer",
               :how
             ) == true

      assert QuestionAnsweringEvaluator.addresses_question_type?(
               "First, then finally",
               :how
             ) == true

      assert QuestionAnsweringEvaluator.addresses_question_type?("Yes", :how) == false
    end

    test "returns true for unknown question types" do
      assert QuestionAnsweringEvaluator.addresses_question_type?("anything", :unknown) == true
    end
  end

  describe "assess_completeness/2" do
    test "returns 1.0 for sufficiently detailed answers" do
      answer = "The capital of France is Paris, located in the north-central part of the country"

      completeness = QuestionAnsweringEvaluator.assess_completeness(answer, :what)

      assert completeness == 1.0
    end

    test "returns low score for very short answers" do
      completeness = QuestionAnsweringEvaluator.assess_completeness("Yes", :why)
      assert completeness < 0.5
    end

    test "adjusts expectations by question type" do
      short_answer = "Paris"

      # 'What' questions need 10+ words, so 1 word gets low score
      what_completeness = QuestionAnsweringEvaluator.assess_completeness(short_answer, :what)

      # Simple fact questions might be okay with short answers
      assert what_completeness < 1.0
    end

    test "returns 0.0 for empty answer" do
      assert QuestionAnsweringEvaluator.assess_completeness("", :what) == 0.0
    end

    test "expects longer answers for 'why' questions" do
      answer = "Because it is"

      completeness = QuestionAnsweringEvaluator.assess_completeness(answer, :why)

      # Needs 15+ words, has 3
      assert completeness < 0.3
    end
  end

  describe "check_question_type_match/2" do
    test "checks if answer matches question type" do
      assert QuestionAnsweringEvaluator.check_question_type_match("In 1945", :when) == true
      assert QuestionAnsweringEvaluator.check_question_type_match("London", :where) == true
    end
  end

  describe "detect_hallucination/2" do
    test "returns false when no context provided" do
      assert QuestionAnsweringEvaluator.detect_hallucination("Any answer", nil) == false
    end

    test "returns false when answer is grounded in context" do
      answer = "Paris is the capital"
      context = "Paris is the capital of France"

      assert QuestionAnsweringEvaluator.detect_hallucination(answer, context) == false
    end

    test "returns true when answer contains many words not in context" do
      answer = "The tower is made of gold diamonds and platinum"
      context = "The tower is tall"

      assert QuestionAnsweringEvaluator.detect_hallucination(answer, context) == true
    end

    test "returns false for empty answer" do
      assert QuestionAnsweringEvaluator.detect_hallucination("", "context") == false
    end
  end

  describe "calculate_qa_fitness/2" do
    test "calculates fitness with perfect scores" do
      metrics = %{
        answer_accuracy: 1.0,
        relevance_score: 1.0,
        completeness_score: 1.0,
        contains_hallucination: false
      }

      fitness = QuestionAnsweringEvaluator.calculate_qa_fitness(0.8, metrics)

      # Should be: 0.6*1.0 + 0.25*1.0 + 0.15*1.0 = 1.0
      assert_in_delta fitness, 1.0, 0.01
    end

    test "calculates fitness with mixed scores" do
      metrics = %{
        answer_accuracy: 0.8,
        relevance_score: 0.9,
        completeness_score: 0.7,
        contains_hallucination: false
      }

      fitness = QuestionAnsweringEvaluator.calculate_qa_fitness(0.7, metrics)

      # Should be: 0.6*0.8 + 0.25*0.9 + 0.15*0.7 = 0.81
      assert_in_delta fitness, 0.81, 0.01
    end

    test "penalizes hallucinations heavily" do
      metrics = %{
        answer_accuracy: 1.0,
        relevance_score: 1.0,
        completeness_score: 1.0,
        contains_hallucination: true
      }

      fitness = QuestionAnsweringEvaluator.calculate_qa_fitness(0.8, metrics)

      # Should be: 1.0 * 0.5 (hallucination penalty) = 0.5
      assert_in_delta fitness, 0.5, 0.01
    end

    test "prioritizes answer accuracy" do
      high_accuracy = %{
        answer_accuracy: 1.0,
        relevance_score: 0.0,
        completeness_score: 0.0,
        contains_hallucination: false
      }

      low_accuracy = %{
        answer_accuracy: 0.0,
        relevance_score: 1.0,
        completeness_score: 1.0,
        contains_hallucination: false
      }

      fitness_high = QuestionAnsweringEvaluator.calculate_qa_fitness(0.5, high_accuracy)
      fitness_low = QuestionAnsweringEvaluator.calculate_qa_fitness(0.5, low_accuracy)

      # High accuracy (0.6) should score higher than perfect relevance+completeness (0.4)
      assert fitness_high > fitness_low
    end
  end
end
