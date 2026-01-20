defmodule Jido.AI.Accuracy.DirectiveTest do
  @moduledoc """
  Tests for the Accuracy Directive.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Directive

  describe "Directive.Run" do
    test "creates a valid directive with required fields" do
      directive =
        Directive.Run.new!(%{
          id: "call_123",
          query: "What is 2+2?"
        })

      assert directive.id == "call_123"
      assert directive.query == "What is 2+2?"
      assert directive.preset == :balanced
      assert directive.config == %{}
      assert directive.timeout == 30_000
    end

    test "creates a directive with preset" do
      directive =
        Directive.Run.new!(%{
          id: "call_123",
          query: "What is 2+2?",
          preset: :fast
        })

      assert directive.preset == :fast
    end

    test "creates a directive with config overrides" do
      config = %{generation_config: %{max_candidates: 15}}

      directive =
        Directive.Run.new!(%{
          id: "call_123",
          query: "What is 2+2?",
          preset: :accurate,
          config: config
        })

      assert directive.config == config
    end

    test "creates a directive with generator" do
      generator = fn prompt -> {:ok, "Answer: #{prompt}"} end

      directive =
        Directive.Run.new!(%{
          id: "call_123",
          query: "What is 2+2?",
          generator: generator
        })

      assert is_function(directive.generator, 1)
    end

    test "creates a directive with custom timeout" do
      directive =
        Directive.Run.new!(%{
          id: "call_123",
          query: "What is 2+2?",
          timeout: 60_000
        })

      assert directive.timeout == 60_000
    end

    test "accepts any atom as preset (validation happens at execution time)" do
      # Zoi doesn't constrain atom values, so this passes
      # Actual validation happens when the preset is used with Presets.get/1
      directive =
        Directive.Run.new!(%{
          id: "call_123",
          query: "What is 2+2?",
          preset: :custom_preset
        })

      assert directive.preset == :custom_preset
    end

    test "raises error with missing required fields" do
      assert_raise RuntimeError, ~r/Invalid/, fn ->
        Directive.Run.new!(%{
          query: "What is 2+2?"
        })
      end
    end

    test "accepts negative timeout (validation happens at execution time)" do
      # Zoi doesn't constrain integer values to be positive
      directive =
        Directive.Run.new!(%{
          id: "call_123",
          query: "What is 2+2?",
          timeout: -1000
        })

      assert directive.timeout == -1000
    end

    test "converts directive to execution map" do
      directive =
        Directive.Run.new!(%{
          id: "call_123",
          query: "What is 2+2?",
          preset: :fast,
          timeout: 45_000
        })

      exec_map = Directive.Run.to_execution_map(directive)

      assert exec_map.id == "call_123"
      assert exec_map.query == "What is 2+2?"
      assert exec_map.preset == :fast
      assert exec_map.timeout == 45_000
    end
  end

  describe "Preset Validation" do
    test "accepts all valid presets" do
      presets = [:fast, :balanced, :accurate, :coding, :research]

      for preset <- presets do
        directive =
          Directive.Run.new!(%{
            id: "call_#{System.unique_integer()}",
            query: "Test query",
            preset: preset
          })

        assert directive.preset == preset
      end
    end
  end
end
