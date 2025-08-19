defmodule Jido.Eval.MetricTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.{Metric, Sample.SingleTurn, Sample.MultiTurn}

  doctest Jido.Eval.Metric

  # Test metric implementation for testing
  defmodule TestMetric do
    @behaviour Jido.Eval.Metric

    @impl true
    def name, do: "Test Metric"

    @impl true
    def description, do: "A test metric for validation"

    @impl true
    def required_fields, do: [:response]

    @impl true
    def sample_types, do: [:single_turn]

    @impl true
    def score_range, do: {0.0, 1.0}

    @impl true
    def evaluate(_sample, _config, _opts), do: {:ok, 0.5}
  end

  defmodule TestMetricMultiTurn do
    @behaviour Jido.Eval.Metric

    @impl true
    def name, do: "Test Multi-turn Metric"
    @impl true
    def description, do: "A test metric supporting multiple sample types"
    @impl true
    def required_fields, do: [:conversation]
    @impl true
    def sample_types, do: [:single_turn, :multi_turn]
    @impl true
    def score_range, do: {0.0, 1.0}
    @impl true
    def evaluate(_sample, _config, _opts), do: {:ok, 0.8}
  end

  describe "validate_sample/2" do
    test "validates sample with all required fields" do
      sample = %SingleTurn{response: "Hello world"}

      assert :ok = Metric.validate_sample(sample, TestMetric)
    end

    test "returns error when required field is missing" do
      sample = %SingleTurn{user_input: "Hello"}

      assert {:error, {:missing_field, :response}} =
               Metric.validate_sample(sample, TestMetric)
    end

    test "returns error when required field is empty string" do
      sample = %SingleTurn{response: ""}

      assert {:error, {:missing_field, :response}} =
               Metric.validate_sample(sample, TestMetric)
    end

    test "returns error when required field is empty list" do
      sample = %SingleTurn{retrieved_contexts: []}

      defmodule TestMetricWithContexts do
        @behaviour Jido.Eval.Metric
        @impl true
        def name, do: "Test With Contexts"
        @impl true
        def description, do: "Test metric requiring contexts"
        @impl true
        def required_fields, do: [:retrieved_contexts]
        @impl true
        def sample_types, do: [:single_turn]
        @impl true
        def score_range, do: {0.0, 1.0}
        @impl true
        def evaluate(_sample, _config, _opts), do: {:ok, 0.5}
      end

      assert {:error, {:missing_field, :retrieved_contexts}} =
               Metric.validate_sample(sample, TestMetricWithContexts)
    end

    test "returns error for unsupported sample type" do
      sample = %MultiTurn{conversation: []}

      assert {:error, {:invalid_sample_type, :multi_turn}} =
               Metric.validate_sample(sample, TestMetric)
    end

    test "validates multi-turn samples for compatible metrics" do
      sample = %MultiTurn{conversation: [%Jido.AI.Message{role: :user, content: "Hello"}]}

      assert :ok = Metric.validate_sample(sample, TestMetricMultiTurn)
    end
  end

  describe "get_sample_type/1" do
    test "identifies SingleTurn samples" do
      sample = %SingleTurn{}

      assert :single_turn = Metric.get_sample_type(sample)
    end

    test "identifies MultiTurn samples" do
      sample = %MultiTurn{}

      assert :multi_turn = Metric.get_sample_type(sample)
    end
  end
end
