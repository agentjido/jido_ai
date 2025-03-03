defmodule JidoTest.AI.SkillTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Jido.AI.Prompt

  describe "validate_prompt_opts/1" do
    test "converts a string to a Prompt struct with a system message" do
      input = "You are a helpful assistant"
      {:ok, result} = Prompt.validate_prompt_opts(input)

      assert %Prompt{} = result
      assert length(result.messages) == 1
      assert hd(result.messages).role == :system
      assert hd(result.messages).content == input
      assert hd(result.messages).engine == :none
    end

    test "returns a Prompt struct unchanged" do
      original = Prompt.new(:system, "Custom prompt")
      {:ok, result} = Prompt.validate_prompt_opts(original)

      assert result == original
    end

    test "returns an error for invalid input" do
      assert {:error, error_message} = Prompt.validate_prompt_opts(123)
      assert error_message =~ "Expected a string or a Jido.AI.Prompt struct"
    end
  end
end
