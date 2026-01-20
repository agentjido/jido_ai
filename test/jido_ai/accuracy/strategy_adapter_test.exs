defmodule Jido.AI.Accuracy.StrategyAdapterTest do
  @moduledoc """
  Tests for the Strategy Adapter.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Directive
  alias Jido.AI.Accuracy.StrategyAdapter

  describe "to_directive/2" do
    test "creates directive from query with defaults" do
      directive = StrategyAdapter.to_directive("What is 2+2?")

      assert directive.query == "What is 2+2?"
      assert directive.preset == :balanced
      assert directive.config == %{}
      assert directive.timeout == 30_000
      assert is_binary(directive.id)
    end

    test "creates directive with preset option" do
      directive = StrategyAdapter.to_directive("What is 2+2?", preset: :fast)

      assert directive.preset == :fast
    end

    test "creates directive with config option" do
      config = %{generation_config: %{max_candidates: 15}}
      directive = StrategyAdapter.to_directive("What is 2+2?", config: config)

      assert directive.config == config
    end

    test "creates directive with custom call_id" do
      directive = StrategyAdapter.to_directive("What is 2+2?", call_id: "custom_123")

      assert directive.id == "custom_123"
    end

    test "creates directive with timeout" do
      directive = StrategyAdapter.to_directive("What is 2+2?", timeout: 60_000)

      assert directive.timeout == 60_000
    end
  end

  describe "from_signal/1" do
    test "extracts query from signal map format" do
      signal = %{"accuracy.run" => %{query: "What is 2+2?", preset: :fast}}

      query = StrategyAdapter.from_signal(signal)

      assert query == "What is 2+2?"
    end

    test "extracts query from signal typed format" do
      signal = %{type: "accuracy.run", data: %{query: "What is 2+2?", preset: :fast}}

      query = StrategyAdapter.from_signal(signal)

      assert query == "What is 2+2?"
    end

    test "returns nil for unknown signal format" do
      signal = %{type: "unknown.signal", data: %{query: "What is 2+2?"}}

      query = StrategyAdapter.from_signal(signal)

      assert is_nil(query)
    end

    test "returns nil for signal without query" do
      signal = %{"accuracy.run" => %{preset: :fast}}

      query = StrategyAdapter.from_signal(signal)

      assert is_nil(query)
    end
  end

  describe "make_generator/1" do
    test "creates generator function from model spec" do
      generator = StrategyAdapter.make_generator("anthropic:claude-haiku-4-5")

      assert is_function(generator, 1)
    end

    test "generator function returns expected format" do
      generator = StrategyAdapter.make_generator("test-model")

      assert {:ok, result} = generator.("test prompt")
      assert is_binary(result)
      assert result =~ "test prompt"
    end

    test "returns module when given module" do
      generator = StrategyAdapter.make_generator(MyModule)

      assert generator == MyModule
    end

    test "returns function when given function" do
      fun = fn prompt -> {:ok, prompt} end
      generator = StrategyAdapter.make_generator(fun)

      assert generator == fun
    end
  end

  describe "Directive integration" do
    test "to_directive creates valid directive" do
      directive = StrategyAdapter.to_directive("What is 2+2?", preset: :fast)

      assert %Directive.Run{} = directive
      assert directive.query == "What is 2+2?"
      assert directive.preset == :fast
    end

    test "to_directive with all options" do
      directive =
        StrategyAdapter.to_directive("What is 2+2?",
          preset: :accurate,
          config: %{generation_config: %{max_candidates: 15}},
          timeout: 45_000
        )

      assert directive.config.generation_config.max_candidates == 15
      assert directive.timeout == 45_000
    end
  end
end
