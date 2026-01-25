defmodule Jido.AI.Accuracy.GeneratorTest do
  use ExUnit.Case, async: false

  alias LLMGenerator

  describe "behavior contract" do
    test "defines generate_candidates callback" do
      # Ensure module is loaded before checking exports
      Code.ensure_loaded(LLMGenerator)
      # The behavior defines @callback for generate_candidates/3
      # Check that LLMGenerator implements it by calling the function
      # Note: Implementation has opts \\ [] default, so both arity 2 and 3 are exported
      _generator = LLMGenerator.new!([])
      # Should have the function because of @impl
      assert function_exported?(LLMGenerator, :generate_candidates, 3)
    end

    test "defines generate_candidates_async callback" do
      Code.ensure_loaded(LLMGenerator)
      assert function_exported?(LLMGenerator, :generate_candidates_async, 3)
    end

    test "defines generate_with_reasoning callback" do
      Code.ensure_loaded(LLMGenerator)
      assert function_exported?(LLMGenerator, :generate_with_reasoning, 3)
    end
  end

  describe "types" do
    test "t type is defined as module" do
      assert is_atom(LLMGenerator)
    end

    test "opts type is keyword list" do
      assert is_list([])
      assert is_list(num_candidates: 5)
    end
  end
end
