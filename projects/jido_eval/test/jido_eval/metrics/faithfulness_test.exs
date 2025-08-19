defmodule Jido.Eval.Metrics.FaithfulnessTest do
  use ExUnit.Case, async: false

  alias Jido.Eval.{Config, Sample.SingleTurn, Sample.MultiTurn}
  alias Jido.Eval.Metrics.Faithfulness

  @moduletag :capture_log

  setup do
    # Use Application environment for test model
    Application.put_env(:jido_ai, :test_mode, true)

    config = %Config{
      model_spec: "test:model"
    }

    %{config: config}

    on_exit(fn ->
      Application.delete_env(:jido_ai, :test_mode)
    end)
  end

  describe "metric metadata" do
    test "returns correct name" do
      assert Faithfulness.name() == "Faithfulness"
    end

    test "returns correct description" do
      description = Faithfulness.description()
      assert String.contains?(description, "grounded")
      assert String.contains?(description, "contexts")
    end

    test "returns required fields" do
      assert Faithfulness.required_fields() == [:response, :retrieved_contexts]
    end

    test "returns supported sample types" do
      assert Faithfulness.sample_types() == [:single_turn]
    end

    test "returns score range" do
      assert Faithfulness.score_range() == {0.0, 1.0}
    end
  end

  describe "evaluate/3" do
    @describetag :skip
    test "evaluates faithful response with perfect score", %{config: config} do
      sample = %SingleTurn{
        response: "Paris is the capital of France.",
        retrieved_contexts: ["France's capital city is Paris."]
      }

      assert {:ok, score} = Faithfulness.evaluate(sample, config, [])
      assert score == 1.0
    end

    test "evaluates partially faithful response", %{config: config} do
      # Mock mixed responses - one supported, one not
      Req.Test.stub(Jido.Eval.LLM, fn conn ->
        body = Jason.decode!(conn.body)
        prompt = body["prompt"] || body["messages"] |> List.last() |> Map.get("content", "")

        response =
          cond do
            String.contains?(prompt, "extract all the individual claims") ->
              "1. Paris is the capital of France.\n2. London is the capital of Germany."

            String.contains?(prompt, "Paris is the capital of France") ->
              "YES"

            String.contains?(prompt, "London is the capital of Germany") ->
              "NO"

            true ->
              "NO"
          end

        Req.Test.json(conn, %{"text" => response})
      end)

      sample = %SingleTurn{
        response: "Paris is the capital of France. London is the capital of Germany.",
        retrieved_contexts: ["France's capital city is Paris."]
      }

      assert {:ok, score} = Faithfulness.evaluate(sample, config, [])
      # 1 out of 2 statements supported
      assert score == 0.5
    end

    test "evaluates unfaithful response with zero score", %{config: config} do
      # Mock all statements as unsupported
      Req.Test.stub(Jido.Eval.LLM, fn conn ->
        body = Jason.decode!(conn.body)
        prompt = body["prompt"] || body["messages"] |> List.last() |> Map.get("content", "")

        response =
          cond do
            String.contains?(prompt, "extract all the individual claims") ->
              "1. Mars is inhabited by aliens."

            String.contains?(prompt, "Mars is inhabited by aliens") ->
              "NO"

            true ->
              "NO"
          end

        Req.Test.json(conn, %{"text" => response})
      end)

      sample = %SingleTurn{
        response: "Mars is inhabited by aliens.",
        retrieved_contexts: ["Mars is a planet in our solar system."]
      }

      assert {:ok, score} = Faithfulness.evaluate(sample, config, [])
      assert score == 0.0
    end

    test "handles empty response", %{config: config} do
      sample = %SingleTurn{
        response: "",
        retrieved_contexts: ["Some context"]
      }

      assert {:error, {:missing_field, :response}} =
               Faithfulness.evaluate(sample, config, [])
    end

    test "handles missing contexts", %{config: config} do
      sample = %SingleTurn{
        response: "Some response",
        retrieved_contexts: nil
      }

      assert {:error, {:missing_field, :retrieved_contexts}} =
               Faithfulness.evaluate(sample, config, [])
    end

    test "handles empty contexts list", %{config: config} do
      sample = %SingleTurn{
        response: "Some response",
        retrieved_contexts: []
      }

      assert {:error, {:missing_field, :retrieved_contexts}} =
               Faithfulness.evaluate(sample, config, [])
    end

    test "rejects multi-turn samples", %{config: config} do
      sample = %MultiTurn{
        conversation: [%Jido.AI.Message{role: :user, content: "Hello"}]
      }

      assert {:error, {:invalid_sample_type, :multi_turn}} =
               Faithfulness.evaluate(sample, config, [])
    end

    test "handles LLM errors gracefully", %{config: config} do
      # Mock LLM error
      Req.Test.stub(Jido.Eval.LLM, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(429, Jason.encode!(%{"error" => "API rate limit exceeded"}))
      end)

      sample = %SingleTurn{
        response: "Paris is the capital of France.",
        retrieved_contexts: ["France's capital city is Paris."]
      }

      assert {:error, {:llm_error, _reason}} =
               Faithfulness.evaluate(sample, config, [])
    end

    test "handles unparseable boolean responses", %{config: config} do
      # Mock ambiguous boolean response
      Req.Test.stub(Jido.Eval.LLM, fn conn ->
        body = Jason.decode!(conn.body)
        prompt = body["prompt"] || body["messages"] |> List.last() |> Map.get("content", "")

        response =
          cond do
            String.contains?(prompt, "extract all the individual claims") ->
              "1. Paris is the capital of France."

            String.contains?(prompt, "Paris is the capital of France") ->
              "Maybe, it depends on your perspective"

            true ->
              "Uncertain"
          end

        Req.Test.json(conn, %{"text" => response})
      end)

      sample = %SingleTurn{
        response: "Paris is the capital of France.",
        retrieved_contexts: ["France's capital city is Paris."]
      }

      assert {:ok, score} = Faithfulness.evaluate(sample, config, [])
      # Should default to false (not supported) when can't parse
      assert score == 0.0
    end

    test "uses entire response as statement when extraction fails", %{config: config} do
      # Mock empty statement extraction
      Req.Test.stub(Jido.Eval.LLM, fn conn ->
        body = Jason.decode!(conn.body)
        prompt = body["prompt"] || body["messages"] |> List.last() |> Map.get("content", "")

        response =
          cond do
            String.contains?(prompt, "extract all the individual claims") ->
              "No clear statements found."

            String.contains?(prompt, "Paris is the capital") ->
              "YES"

            true ->
              "YES"
          end

        Req.Test.json(conn, %{"text" => response})
      end)

      sample = %SingleTurn{
        response: "Paris is the capital of France.",
        retrieved_contexts: ["France's capital city is Paris."]
      }

      assert {:ok, score} = Faithfulness.evaluate(sample, config, [])
      # Entire response treated as single statement
      assert score == 1.0
    end
  end

  describe "performance" do
    @describetag :skip
    @describetag :benchmark
    test "evaluates sample within reasonable time", %{config: config} do
      sample = %SingleTurn{
        response: "Paris is the capital of France and it's located in Europe.",
        retrieved_contexts: ["France's capital city is Paris, located in northern France."]
      }

      {time_micro, {:ok, _score}} =
        :timer.tc(fn -> Faithfulness.evaluate(sample, config, timeout: 10_000) end)

      # Should complete within 10 seconds even with network calls
      assert time_micro < 10_000_000
    end
  end
end
