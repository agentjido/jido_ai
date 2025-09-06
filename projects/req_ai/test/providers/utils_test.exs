defmodule ReqAI.Provider.UtilsTest do
  use ExUnit.Case, async: true
  doctest ReqAI.Provider.Utils

  alias ReqAI.Provider.Utils

  describe "normalize_messages/1" do
    test "converts string prompt to user message" do
      prompt = "What is the weather like?"
      result = Utils.normalize_messages(prompt)

      assert result == [%{role: "user", content: "What is the weather like?"}]
    end

    test "returns message list unchanged" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"},
        %{role: "user", content: "How are you?"}
      ]

      result = Utils.normalize_messages(messages)
      assert result == messages
    end

    test "converts other types to string and wraps in user message" do
      assert Utils.normalize_messages(123) == [%{role: "user", content: "123"}]
      assert Utils.normalize_messages(:atom) == [%{role: "user", content: "atom"}]
      assert Utils.normalize_messages(nil) == [%{role: "user", content: ""}]
    end

    test "handles empty string" do
      result = Utils.normalize_messages("")
      assert result == [%{role: "user", content: ""}]
    end

    test "handles empty list" do
      result = Utils.normalize_messages([])
      assert result == []
    end

    test "preserves complex message structures" do
      messages = [
        %{role: "user", content: [%{type: "text", text: "Hello"}]},
        %{role: "assistant", content: "Hi!"}
      ]

      result = Utils.normalize_messages(messages)
      assert result == messages
    end
  end

  describe "default_model/1" do
    test "returns spec default_model when available" do
      spec = %{
        default_model: "gpt-4",
        models: %{"gpt-3.5-turbo" => %{}, "gpt-4" => %{}}
      }

      assert Utils.default_model(spec) == "gpt-4"
    end

    test "returns first model when no default_model specified" do
      spec = %{
        default_model: nil,
        models: %{"claude-3-haiku" => %{}, "claude-3-opus" => %{}}
      }

      result = Utils.default_model(spec)
      # Since map keys order can vary, check it's one of the available models
      assert result in ["claude-3-haiku", "claude-3-opus"]
    end

    test "returns nil when no models available" do
      spec = %{
        default_model: nil,
        models: %{}
      }

      assert Utils.default_model(spec) == nil
    end

    test "prefers default_model over available models" do
      spec = %{
        default_model: "custom-model",
        models: %{"model-a" => %{}, "model-b" => %{}}
      }

      assert Utils.default_model(spec) == "custom-model"
    end

    test "handles spec with string keys in models" do
      spec = %{
        default_model: nil,
        models: %{"anthropic/claude" => %{max_tokens: 4096}}
      }

      assert Utils.default_model(spec) == "anthropic/claude"
    end

    test "returns nil for empty spec" do
      spec = %{default_model: nil, models: %{}}
      assert Utils.default_model(spec) == nil
    end
  end
end
