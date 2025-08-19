defmodule Jido.Eval.ProcessorTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.Processor

  defmodule TestProcessor do
    @behaviour Processor

    def process(data, stage, opts) do
      processed_data = %{
        original: data,
        stage: stage,
        timestamp: System.system_time(),
        opts: opts
      }

      {:ok, processed_data}
    end
  end

  defmodule NormalizingProcessor do
    @behaviour Processor

    def process(data, :pre, _opts) do
      normalized = %{data | text: String.downcase(data.text)}
      {:ok, normalized}
    end

    def process(data, :post, _opts) do
      enriched = Map.put(data, :processed_at, DateTime.utc_now())
      {:ok, enriched}
    end
  end

  defmodule ErrorProcessor do
    @behaviour Processor

    def process(_data, :pre, _opts) do
      {:error, :pre_processing_failed}
    end

    def process(_data, :post, _opts) do
      {:error, :post_processing_failed}
    end
  end

  describe "behaviour implementation" do
    test "TestProcessor processes data with context" do
      data = %{id: 1, text: "Hello"}
      opts = [debug: true]

      {:ok, result} = TestProcessor.process(data, :pre, opts)

      assert result.original == data
      assert result.stage == :pre
      assert result.opts == opts
      assert is_integer(result.timestamp)
    end

    test "TestProcessor works with different stages" do
      data = %{id: 1}

      {:ok, pre_result} = TestProcessor.process(data, :pre, [])
      {:ok, post_result} = TestProcessor.process(data, :post, [])

      assert pre_result.stage == :pre
      assert post_result.stage == :post
    end

    test "NormalizingProcessor handles pre-processing" do
      data = %{text: "HELLO WORLD", id: 1}

      {:ok, result} = NormalizingProcessor.process(data, :pre, [])

      assert result.text == "hello world"
      assert result.id == 1
    end

    test "NormalizingProcessor handles post-processing" do
      data = %{text: "hello", score: 0.8}

      {:ok, result} = NormalizingProcessor.process(data, :post, [])

      assert result.text == "hello"
      assert result.score == 0.8
      assert %DateTime{} = result.processed_at
    end

    test "ErrorProcessor returns errors for both stages" do
      assert ErrorProcessor.process(%{}, :pre, []) == {:error, :pre_processing_failed}
      assert ErrorProcessor.process(%{}, :post, []) == {:error, :post_processing_failed}
    end
  end

  describe "behaviour validation" do
    test "behaviour callbacks are defined" do
      callbacks = Processor.behaviour_info(:callbacks)

      assert {:process, 3} in callbacks
    end

    test "no optional callbacks defined" do
      optional_callbacks = Processor.behaviour_info(:optional_callbacks)
      assert optional_callbacks == []
    end
  end
end
