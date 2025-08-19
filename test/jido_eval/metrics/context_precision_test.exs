defmodule Jido.Eval.Metrics.ContextPrecisionTest do
  use ExUnit.Case, async: false

  alias Jido.Eval.{Config, Sample.SingleTurn, Sample.MultiTurn}
  alias Jido.Eval.Metrics.ContextPrecision

  @moduletag :capture_log

  setup do
    # Set up Req.Test adapter for mocking LLM calls
    Req.Test.stub(Jido.Eval.LLM, fn conn ->
      case conn.request_path do
        "/generate_text" ->
          # Check the request body to determine response
          body = Jason.decode!(conn.body)
          prompt = body["prompt"] || body["messages"] |> List.last() |> Map.get("content", "")

          response =
            cond do
              String.contains?(prompt, "Paris is the capital and largest city") ->
                # Highly relevant
                "YES"

              String.contains?(prompt, "France is a country in Western Europe") ->
                # Somewhat relevant
                "YES"

              String.contains?(prompt, "Germany is a country in Central Europe") ->
                # Not relevant
                "NO"

              String.contains?(prompt, "Spain shares a border with France") ->
                # Somewhat relevant
                "YES"

              String.contains?(prompt, "The weather in Tokyo") ->
                # Not relevant
                "NO"

              true ->
                # Default to relevant
                "YES"
            end

          Req.Test.json(conn, %{"text" => response})

        _ ->
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.resp(404, Jason.encode!(%{"error" => "Not found"}))
      end
    end)

    config = %Config{
      model_spec: "test:model"
    }

    %{config: config}
  end

  describe "metric metadata" do
    test "returns correct name" do
      assert ContextPrecision.name() == "Context Precision"
    end

    test "returns correct description" do
      description = ContextPrecision.description()
      assert String.contains?(description, "relevance")
      assert String.contains?(description, "contexts")
      assert String.contains?(description, "question")
    end

    test "returns required fields" do
      assert ContextPrecision.required_fields() == [:user_input, :retrieved_contexts, :reference]
    end

    test "returns supported sample types" do
      assert ContextPrecision.sample_types() == [:single_turn]
    end

    test "returns score range" do
      assert ContextPrecision.score_range() == {0.0, 1.0}
    end
  end

  describe "evaluate/3" do
    @describetag :skip
    test "evaluates perfect precision with all relevant contexts", %{config: config} do
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: [
          "Paris is the capital and largest city of France.",
          "France is a country in Western Europe."
        ],
        reference: "Paris is the capital of France."
      }

      assert {:ok, score} = ContextPrecision.evaluate(sample, config, [])
      assert score == 1.0
    end

    test "evaluates mixed precision with relevant and irrelevant contexts", %{config: config} do
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: [
          # Not relevant - position 1
          "Germany is a country in Central Europe.",
          # Relevant - position 2  
          "Paris is the capital and largest city of France.",
          # Relevant - position 3
          "Spain shares a border with France."
        ],
        reference: "Paris is the capital of France."
      }

      assert {:ok, score} = ContextPrecision.evaluate(sample, config, [])

      # Average precision calculation:
      # Position 1: irrelevant, precision = 0
      # Position 2: relevant, precision = 1/2 = 0.5
      # Position 3: relevant, precision = 2/3 ≈ 0.667
      # Average of relevant positions: (0.5 + 0.667) / 2 ≈ 0.583
      assert_in_delta score, 0.583, 0.01
    end

    test "evaluates zero precision with no relevant contexts", %{config: config} do
      # Mock all contexts as irrelevant
      Req.Test.stub(Jido.Eval.LLM, fn conn ->
        Req.Test.json(conn, %{"text" => "NO"})
      end)

      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: [
          "The weather in Tokyo is nice.",
          "Cats are popular pets."
        ],
        reference: "Paris is the capital of France."
      }

      assert {:ok, score} = ContextPrecision.evaluate(sample, config, [])
      assert score == 0.0
    end

    test "handles empty contexts list", %{config: config} do
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: [],
        reference: "Paris is the capital of France."
      }

      assert {:error, {:missing_field, :retrieved_contexts}} =
               ContextPrecision.evaluate(sample, config, [])
    end

    test "handles missing user input", %{config: config} do
      sample = %SingleTurn{
        user_input: nil,
        retrieved_contexts: ["Some context"],
        reference: "Some reference"
      }

      assert {:error, {:missing_field, :user_input}} =
               ContextPrecision.evaluate(sample, config, [])
    end

    test "handles missing reference", %{config: config} do
      sample = %SingleTurn{
        user_input: "What is the capital?",
        retrieved_contexts: ["Some context"],
        reference: nil
      }

      assert {:error, {:missing_field, :reference}} =
               ContextPrecision.evaluate(sample, config, [])
    end

    test "rejects multi-turn samples", %{config: config} do
      sample = %MultiTurn{
        conversation: [%Jido.AI.Message{role: :user, content: "Hello"}]
      }

      assert {:error, {:invalid_sample_type, :multi_turn}} =
               ContextPrecision.evaluate(sample, config, [])
    end

    test "handles LLM errors gracefully", %{config: config} do
      # Mock LLM error
      Req.Test.stub(Jido.Eval.LLM, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(503, Jason.encode!(%{"error" => "Service unavailable"}))
      end)

      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: ["Paris is the capital of France."],
        reference: "Paris"
      }

      assert {:error, {:llm_error, _reason}} =
               ContextPrecision.evaluate(sample, config, [])
    end

    test "handles unparseable boolean responses", %{config: config} do
      # Mock ambiguous boolean response
      Req.Test.stub(Jido.Eval.LLM, fn conn ->
        Req.Test.json(conn, %{"text" => "Maybe relevant"})
      end)

      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: ["Paris is the capital of France."],
        reference: "Paris"
      }

      assert {:ok, score} = ContextPrecision.evaluate(sample, config, [])
      # Should default to false (not relevant) when can't parse
      assert score == 0.0
    end

    test "evaluates single relevant context", %{config: config} do
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: ["Paris is the capital and largest city of France."],
        reference: "Paris is the capital of France."
      }

      assert {:ok, score} = ContextPrecision.evaluate(sample, config, [])
      assert score == 1.0
    end

    test "calculates precision correctly for different arrangements", %{config: config} do
      # Test with relevant context first, then irrelevant
      sample1 = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: [
          # Relevant
          "Paris is the capital and largest city of France.",
          # Irrelevant
          "The weather in Tokyo is nice."
        ],
        reference: "Paris is the capital of France."
      }

      # Mock first context as relevant, second as irrelevant
      Req.Test.stub(Jido.Eval.LLM, fn conn ->
        body = Jason.decode!(conn.body)
        prompt = body["prompt"] || body["messages"] |> List.last() |> Map.get("content", "")

        response = if String.contains?(prompt, "Paris is the capital"), do: "YES", else: "NO"
        Req.Test.json(conn, %{"text" => response})
      end)

      assert {:ok, score1} = ContextPrecision.evaluate(sample1, config, [])

      # Precision at position 1: 1/1 = 1.0 (only relevant position)
      assert score1 == 1.0
    end
  end

  describe "performance" do
    @describetag :skip
    @describetag :benchmark
    test "evaluates sample with multiple contexts within reasonable time", %{config: config} do
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: [
          "Paris is the capital of France.",
          "France is in Europe.",
          "Germany borders France.",
          "Spain also borders France.",
          "The Mediterranean Sea is south of France."
        ],
        reference: "Paris"
      }

      {time_micro, {:ok, _score}} =
        :timer.tc(fn -> ContextPrecision.evaluate(sample, config, timeout: 15_000) end)

      # Should complete within 15 seconds even with multiple LLM calls
      assert time_micro < 15_000_000
    end
  end
end
