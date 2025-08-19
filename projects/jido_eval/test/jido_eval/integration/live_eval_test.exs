defmodule Jido.Eval.Integration.LiveEvalTest do
  use ExUnit.Case
  alias Jido.Eval.Sample.SingleTurn
  alias Jido.Eval.Dataset.InMemory

  @moduletag :live_eval
  @moduletag timeout: 120_000

  describe "live evaluation with real LLM" do
    test "evaluates faithfulness on single RAG example" do
      # Single sample for reliable testing  
      samples = [
        %SingleTurn{
          id: "sample_001",
          user_input: "What is the capital of France?",
          retrieved_contexts: [
            "France is a country in Western Europe. Its capital and largest city is Paris.",
            "Paris is located in northern France on the River Seine."
          ],
          response: "The capital of France is Paris.",
          reference: "Paris is the capital of France.",
          tags: %{"source" => "geography_qa"}
        }
      ]

      {:ok, dataset} = InMemory.new(samples)

      # Run evaluation with faithfulness only (most reliable metric)
      {:ok, result} =
        Jido.Eval.evaluate(dataset,
          metrics: [:faithfulness],
          llm: "openai:gpt-4o-mini",
          reporters: [],
          broadcasters: [],
          processors: [],
          config: %Jido.Eval.Config{middleware: []}
        )

      # Validate result structure matches Ragas pattern
      assert %Jido.Eval.Result{} = result
      assert result.run_id
      assert is_list(result.sample_results)
      assert length(result.sample_results) == 1

      # Check that sample was evaluated
      sample_result = hd(result.sample_results)
      assert is_map(sample_result)
      assert sample_result.sample_id == "sample_001"
      assert is_map(sample_result.scores)

      # Validate faithfulness score
      assert Map.has_key?(sample_result.scores, :faithfulness)
      faithfulness_score = sample_result.scores.faithfulness
      assert is_float(faithfulness_score)
      assert faithfulness_score >= 0.0 and faithfulness_score <= 1.0

      # Validate summary statistics
      assert is_map(result.summary_stats)
      assert Map.has_key?(result.summary_stats, :faithfulness)

      faithfulness_summary = result.summary_stats.faithfulness
      assert is_float(faithfulness_summary.mean)
      assert is_float(faithfulness_summary.std_dev)
      assert faithfulness_summary.count == 1

      # Log results for manual inspection
      IO.puts("\n=== Live Evaluation Results ===")
      IO.puts("Faithfulness Score: #{faithfulness_score}")
      IO.puts("Faithfulness Mean: #{faithfulness_summary.mean}")
      IO.puts("Run ID: #{result.run_id}")
      IO.puts("✅ Basic live evaluation working!")
    end

    test "evaluates with custom LLM configuration" do
      samples = [
        %SingleTurn{
          id: "sample_004",
          user_input: "What is machine learning?",
          retrieved_contexts: [
            "Machine learning is a subset of artificial intelligence that enables computers to learn from data.",
            "ML algorithms can identify patterns and make predictions without being explicitly programmed."
          ],
          response:
            "Machine learning is an AI technique where computers learn from data to make predictions and identify patterns automatically.",
          reference: "Machine learning uses data to train algorithms to make predictions.",
          tags: %{"source" => "tech_qa"}
        }
      ]

      {:ok, dataset} = InMemory.new(samples)

      # Test with custom temperature for more deterministic results
      {:ok, result} =
        Jido.Eval.evaluate(dataset,
          metrics: [:faithfulness],
          llm: {:openai, model: "gpt-4o-mini", temperature: 0.1},
          reporters: [],
          broadcasters: [],
          processors: [],
          config: %Jido.Eval.Config{middleware: []}
        )

      assert %Jido.Eval.Result{} = result
      assert length(result.sample_results) == 1

      sample_result = hd(result.sample_results)
      assert Map.has_key?(sample_result.scores, :faithfulness)

      faithfulness_score = sample_result.scores.faithfulness
      assert is_float(faithfulness_score)
      assert faithfulness_score >= 0.0 and faithfulness_score <= 1.0

      IO.puts("\n=== Custom LLM Config Results ===")
      IO.puts("Faithfulness Score: #{faithfulness_score}")
      IO.puts("Sample evaluated successfully with custom temperature")
    end

    test "evaluates multiple samples with both metrics" do
      # Multiple samples to test batch processing
      samples = [
        %SingleTurn{
          id: "sample_001",
          user_input: "What is the capital of France?",
          retrieved_contexts: [
            "France is a country in Western Europe. Its capital and largest city is Paris.",
            "Paris is located in northern France on the River Seine."
          ],
          response: "The capital of France is Paris.",
          reference: "Paris is the capital of France.",
          tags: %{"source" => "geography_qa"}
        },
        %SingleTurn{
          id: "sample_002",
          user_input: "How does photosynthesis work?",
          retrieved_contexts: [
            "Photosynthesis is the process by which plants convert sunlight into energy.",
            "During photosynthesis, plants use chlorophyll to absorb light energy."
          ],
          response: "Photosynthesis converts sunlight into energy using chlorophyll.",
          reference: "Photosynthesis converts sunlight to energy.",
          tags: %{"source" => "biology_qa"}
        }
      ]

      {:ok, dataset} = InMemory.new(samples)

      # Test both metrics together
      {:ok, result} =
        Jido.Eval.evaluate(dataset,
          metrics: [:faithfulness, :context_precision],
          llm: "openai:gpt-4o-mini",
          reporters: [],
          broadcasters: [],
          processors: [],
          config: %Jido.Eval.Config{middleware: []}
        )

      assert %Jido.Eval.Result{} = result
      assert length(result.sample_results) == 2

      # Validate all samples have both metric scores
      for sample_result <- result.sample_results do
        assert Map.has_key?(sample_result.scores, :faithfulness)
        assert Map.has_key?(sample_result.scores, :context_precision)
        assert sample_result.scores.faithfulness >= 0.0
        assert sample_result.scores.context_precision >= 0.0
      end

      IO.puts("\n=== Multi-Sample Results ===")
      IO.puts("Faithfulness: #{result.summary_stats.faithfulness.mean}")
      IO.puts("Context Precision: #{result.summary_stats.context_precision.mean}")
      IO.puts("✅ Multi-sample evaluation working!")
    end

    test "evaluates imperfect responses with realistic scores" do
      # Samples designed to get non-perfect scores
      samples = [
        %SingleTurn{
          id: "sample_partial",
          user_input: "What causes global warming?",
          retrieved_contexts: [
            "Global warming is primarily caused by greenhouse gas emissions from fossil fuel burning.",
            "Carbon dioxide, methane, and other greenhouse gases trap heat in Earth's atmosphere.",
            "Deforestation also contributes by reducing CO2 absorption by trees."
          ],
          # Incomplete response missing key details
          response: "Global warming happens because of fossil fuels.",
          reference: "Global warming is caused by greenhouse gas emissions from burning fossil fuels, deforestation, and industrial processes that release heat-trapping gases into the atmosphere.",
          tags: %{"source" => "climate_qa", "expected_score" => "partial"}
        },
        %SingleTurn{
          id: "sample_hallucination",
          user_input: "How do solar panels work?",
          retrieved_contexts: [
            "Solar panels contain photovoltaic cells that convert sunlight directly into electricity.",
            "When photons hit the semiconductor material, they knock electrons loose, creating electrical current."
          ],
          # Response adds information not in context (hallucination)
          response: "Solar panels work by using photovoltaic cells to convert sunlight into electricity. They also use mirrors to concentrate the sunlight and generate steam to turn turbines.",
          reference: "Solar panels use photovoltaic cells to convert sunlight directly into electricity through the photovoltaic effect.",
          tags: %{"source" => "tech_qa", "expected_score" => "mixed"}
        },
        %SingleTurn{
          id: "sample_irrelevant_context",
          user_input: "What is machine learning?",
          retrieved_contexts: [
            "Machine learning is a subset of artificial intelligence.",
            "There are three types of pasta: spaghetti, penne, and fusilli.",
            "Popular programming languages include Python, Java, and C++."
          ],
          response: "Machine learning is a subset of AI that allows computers to learn from data without being explicitly programmed.",
          reference: "Machine learning is a branch of artificial intelligence that enables computers to learn and make decisions from data.",
          tags: %{"source" => "mixed_qa", "expected_score" => "low_precision"}
        }
      ]

      {:ok, dataset} = InMemory.new(samples)

      # Test both metrics to see realistic score ranges
      {:ok, result} =
        Jido.Eval.evaluate(dataset,
          metrics: [:faithfulness, :context_precision],
          llm: "openai:gpt-4o-mini",
          reporters: [],
          broadcasters: [],
          processors: [],
          config: %Jido.Eval.Config{middleware: []}
        )

      assert %Jido.Eval.Result{} = result
      assert length(result.sample_results) == 3

      # Check for varied scores (not all perfect)
      faithfulness_scores = 
        Enum.map(result.sample_results, fn sr -> sr.scores.faithfulness end)

      # At least one score should be less than perfect
      assert Enum.any?(faithfulness_scores, fn score -> score < 1.0 end),
             "Expected at least one faithfulness score < 1.0, got: #{inspect(faithfulness_scores)}"

      IO.puts("\n=== Imperfect Response Results ===")
      for sample_result <- result.sample_results do
        sample_id = sample_result.sample_id
        faith_score = sample_result.scores.faithfulness
        precision_score = sample_result.scores.context_precision
        IO.puts("#{sample_id}: Faithfulness=#{faith_score}, Context Precision=#{precision_score}")
      end
      IO.puts("Avg Faithfulness: #{result.summary_stats.faithfulness.mean}")
      IO.puts("Avg Context Precision: #{result.summary_stats.context_precision.mean}")
      IO.puts("✅ Realistic score variation detected!")
    end

    test "evaluates async with progress monitoring" do
      samples = [
        %SingleTurn{
          id: "async_001",
          user_input: "What is the theory of relativity?",
          retrieved_contexts: [
            "Einstein's theory of relativity consists of special and general relativity.",
            "Special relativity deals with objects moving at constant speeds in a straight line.",
            "General relativity extends this to include gravity and acceleration."
          ],
          response: "Einstein's theory of relativity includes both special relativity (dealing with constant motion) and general relativity (including gravity effects).",
          reference: "The theory of relativity, developed by Einstein, includes special and general relativity theories.",
          tags: %{"source" => "physics_qa"}
        },
        %SingleTurn{
          id: "async_002",
          user_input: "How do vaccines work?",
          retrieved_contexts: [
            "Vaccines contain weakened or killed pathogens that train the immune system.",
            "After vaccination, the immune system remembers the pathogen and can fight it quickly.",
            "This creates immunity without causing the actual disease."
          ],
          response: "Vaccines work by exposing the immune system to harmless versions of pathogens, allowing it to develop immunity without getting sick.",
          reference: "Vaccines train the immune system to recognize and fight specific diseases by using weakened or killed pathogens.",
          tags: %{"source" => "medical_qa"}
        }
      ]

      {:ok, dataset} = InMemory.new(samples)

      # Test async evaluation
      {:ok, run_id} = 
        Jido.Eval.evaluate_async(dataset,
          metrics: [:faithfulness, :context_precision],
          llm: "openai:gpt-4o-mini",
          reporters: [],
          broadcasters: [],
          processors: [],
          config: %Jido.Eval.Config{middleware: []}
        )

      # Monitor progress
      {:ok, progress} = Jido.Eval.get_progress(run_id)
      assert is_map(progress)
      assert Map.has_key?(progress, :run_id)
      assert progress.run_id == run_id

      # Wait for completion
      {:ok, result} = Jido.Eval.await_result(run_id, 60_000)

      assert %Jido.Eval.Result{} = result
      assert result.run_id == run_id
      assert length(result.sample_results) == 2

      # Validate results
      for sample_result <- result.sample_results do
        assert Map.has_key?(sample_result.scores, :faithfulness)
        assert Map.has_key?(sample_result.scores, :context_precision)
        assert is_float(sample_result.scores.faithfulness)
        assert is_float(sample_result.scores.context_precision)
      end

      IO.puts("\n=== Async Evaluation Results ===")
      IO.puts("Run ID: #{run_id}")
      IO.puts("Faithfulness: #{result.summary_stats.faithfulness.mean}")
      IO.puts("Context Precision: #{result.summary_stats.context_precision.mean}")
      IO.puts("✅ Async evaluation completed successfully!")
    end

    test "handles challenging evaluation scenarios" do
      # Create a sample that might challenge the evaluation
      samples = [
        %SingleTurn{
          id: "sample_005",
          user_input: "What is the meaning of life?",
          retrieved_contexts: [
            "This is completely unrelated context about cooking recipes.",
            "Here's how to make pasta: boil water, add salt, cook noodles."
          ],
          response: "The answer is 42, according to Douglas Adams.",
          reference:
            "The meaning of life is a philosophical question with many different answers.",
          tags: %{"source" => "philosophy_qa"}
        }
      ]

      {:ok, dataset} = InMemory.new(samples)

      # This should still work but might produce low scores
      {:ok, result} =
        Jido.Eval.evaluate(dataset,
          metrics: [:faithfulness],
          llm: "openai:gpt-4o-mini",
          reporters: [],
          broadcasters: [],
          processors: [],
          config: %Jido.Eval.Config{middleware: []}
        )

      assert %Jido.Eval.Result{} = result
      assert length(result.sample_results) == 1

      sample_result = hd(result.sample_results)
      assert Map.has_key?(sample_result.scores, :faithfulness)

      # Score might be low due to context mismatch, but should still be valid
      faithfulness = sample_result.scores.faithfulness
      assert is_float(faithfulness) and faithfulness >= 0.0 and faithfulness <= 1.0

      IO.puts("\n=== Challenging Scenario Results ===")
      IO.puts("Faithfulness (mismatched context): #{faithfulness}")
      IO.puts("✅ System handled challenging evaluation gracefully")
    end
  end
end
