defmodule Jido.AITest do
  use ExUnit.Case, async: true

  alias Jido.AI

  doctest Jido.AI

  describe "model_aliases/0 and resolve_model/1" do
    test "loads built-in defaults" do
      assert is_binary(AI.resolve_model(:fast))
    end

    test "merges configured aliases over defaults" do
      original = Application.get_env(:jido_ai, :model_aliases)

      Application.put_env(:jido_ai, :model_aliases, %{
        fast: "test:fast",
        custom: "test:custom"
      })

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:jido_ai, :model_aliases)
        else
          Application.put_env(:jido_ai, :model_aliases, original)
        end
      end)

      assert AI.resolve_model(:fast) == "test:fast"
      assert AI.resolve_model(:custom) == "test:custom"
    end
  end

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
