defmodule Jido.AITest do
  use ExUnit.Case, async: true

  alias Jido.AI

  doctest Jido.AI

  describe "llm_defaults/0 and llm_defaults/1" do
    test "returns built-in defaults for text/object/stream" do
      defaults = AI.llm_defaults()

      assert defaults[:text][:model] == :fast
      assert defaults[:object][:model] == :thinking
      assert defaults[:stream][:model] == :fast
      assert defaults[:text][:timeout] == 30_000
    end

    test "merges configured defaults with built-ins" do
      original = Application.get_env(:jido_ai, :llm_defaults)

      Application.put_env(:jido_ai, :llm_defaults, %{
        text: %{model: :capable, temperature: 0.7},
        stream: %{max_tokens: 2048}
      })

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:jido_ai, :llm_defaults)
        else
          Application.put_env(:jido_ai, :llm_defaults, original)
        end
      end)

      assert AI.llm_defaults(:text)[:model] == :capable
      assert AI.llm_defaults(:text)[:temperature] == 0.7
      assert AI.llm_defaults(:text)[:timeout] == 30_000
      assert AI.llm_defaults(:stream)[:max_tokens] == 2048
      assert AI.llm_defaults(:stream)[:model] == :fast
    end

    test "raises for unknown default kind" do
      assert_raise ArgumentError, fn ->
        AI.llm_defaults(:unknown_kind)
      end
    end
  end
end
