defmodule Jido.Eval.MetricsTest do
  use ExUnit.Case, async: false

  alias Jido.Eval.{Metrics, ComponentRegistry, Sample.SingleTurn}
  alias Jido.Eval.Metrics.{Faithfulness, ContextPrecision}

  @moduletag :capture_log

  setup do
    ComponentRegistry.start_link()
    ComponentRegistry.clear()
    :ok
  end

  describe "register_all/0" do
    test "registers all built-in metrics successfully" do
      assert :ok = Metrics.register_all()

      # Verify metrics are registered
      metrics = ComponentRegistry.list(:metric)
      assert Faithfulness in metrics
      assert ContextPrecision in metrics
    end

    test "is idempotent - can be called multiple times" do
      assert :ok = Metrics.register_all()
      assert :ok = Metrics.register_all()

      # Should still have the same metrics
      metrics = ComponentRegistry.list(:metric)
      assert length(metrics) >= 2
    end
  end

  describe "list_available/0" do
    test "returns empty list when no metrics registered" do
      assert Metrics.list_available() == []
    end

    test "returns registered metrics" do
      Metrics.register_all()

      metrics = Metrics.list_available()
      assert Faithfulness in metrics
      assert ContextPrecision in metrics
    end
  end

  describe "get_info/1" do
    test "returns metric information for Faithfulness" do
      assert {:ok, info} = Metrics.get_info(Faithfulness)

      assert info.name == "Faithfulness"
      assert is_binary(info.description)
      assert info.required_fields == [:response, :retrieved_contexts]
      assert info.sample_types == [:single_turn]
      assert info.score_range == {0.0, 1.0}
    end

    test "returns metric information for ContextPrecision" do
      assert {:ok, info} = Metrics.get_info(ContextPrecision)

      assert info.name == "Context Precision"
      assert is_binary(info.description)
      assert info.required_fields == [:user_input, :retrieved_contexts, :reference]
      assert info.sample_types == [:single_turn]
      assert info.score_range == {0.0, 1.0}
    end

    test "returns error for invalid metric module" do
      defmodule NotAMetric do
        # Missing behaviour implementation
      end

      assert {:error, {:metric_info_error, _}} = Metrics.get_info(NotAMetric)
    end
  end

  describe "check_compatibility/2" do
    test "validates compatible sample for Faithfulness" do
      sample = %SingleTurn{
        response: "Paris is the capital of France.",
        retrieved_contexts: ["France's capital city is Paris."]
      }

      assert :ok = Metrics.check_compatibility(Faithfulness, sample)
    end

    test "rejects incompatible sample for Faithfulness" do
      sample = %SingleTurn{
        user_input: "What is the capital of France?"
        # Missing response and retrieved_contexts
      }

      assert {:error, {:missing_field, :response}} =
               Metrics.check_compatibility(Faithfulness, sample)
    end

    test "validates compatible sample for ContextPrecision" do
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: ["Paris is the capital of France."],
        reference: "Paris"
      }

      assert :ok = Metrics.check_compatibility(ContextPrecision, sample)
    end

    test "rejects incompatible sample for ContextPrecision" do
      sample = %SingleTurn{
        response: "Paris is the capital of France."
        # Missing user_input, retrieved_contexts, and reference
      }

      assert {:error, {:missing_field, :user_input}} =
               Metrics.check_compatibility(ContextPrecision, sample)
    end
  end

  describe "find_compatible/1" do
    setup do
      Metrics.register_all()
      :ok
    end

    test "finds Faithfulness for compatible sample" do
      sample = %SingleTurn{
        response: "Paris is the capital of France.",
        retrieved_contexts: ["France's capital city is Paris."]
      }

      compatible = Metrics.find_compatible(sample)
      assert Faithfulness in compatible
    end

    test "finds ContextPrecision for compatible sample" do
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: ["Paris is the capital of France."],
        reference: "Paris"
      }

      compatible = Metrics.find_compatible(sample)
      assert ContextPrecision in compatible
    end

    test "finds both metrics for fully compatible sample" do
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        response: "Paris is the capital of France.",
        retrieved_contexts: ["France's capital city is Paris."],
        reference: "Paris"
      }

      compatible = Metrics.find_compatible(sample)
      assert Faithfulness in compatible
      assert ContextPrecision in compatible
    end

    test "finds no metrics for incompatible sample" do
      sample = %SingleTurn{
        id: "test_sample"
        # Missing all required fields
      }

      compatible = Metrics.find_compatible(sample)
      assert compatible == []
    end
  end

  describe "built_in_metrics/0" do
    test "returns list of built-in metrics" do
      built_ins = Metrics.built_in_metrics()

      assert Faithfulness in built_ins
      assert ContextPrecision in built_ins
      assert is_list(built_ins)
      assert length(built_ins) >= 2
    end
  end
end
