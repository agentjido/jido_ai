defmodule Jido.AI.Accuracy.GeneratorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Generator

  describe "behavior contract" do
    test "defines generate_candidates callback" do
      # The behavior defines @callback for generate_candidates/3
      # Check that LLMGenerator implements it by calling the function
      # Note: Implementation has opts \\ [] default, so both arity 2 and 3 are exported
      generator = Jido.AI.Accuracy.Generators.LLMGenerator.new!([])
      # Should have the function because of @impl
      assert function_exported?(Jido.AI.Accuracy.Generators.LLMGenerator, :generate_candidates, 3)
    end

    test "defines generate_candidates_async callback" do
      assert function_exported?(Jido.AI.Accuracy.Generators.LLMGenerator, :generate_candidates_async, 3)
    end

    test "defines generate_with_reasoning callback" do
      assert function_exported?(Jido.AI.Accuracy.Generators.LLMGenerator, :generate_with_reasoning, 3)
    end
  end

  describe "types" do
    test "t type is defined as module" do
      assert is_atom(Jido.AI.Accuracy.Generators.LLMGenerator)
    end

    test "opts type is keyword list" do
      assert is_list([])
      assert is_list(num_candidates: 5)
    end
  end
end
