defmodule JidoTest.AI.Model.FromTest do
  use ExUnit.Case
  alias Jido.AI.Model

  @moduletag :capture_log

  describe "Model.from/1" do
    test "with a valid existing Model struct" do
      original = %Model{
        provider: :anthropic,
        model: "claude-3-5-haiku",
        base_url: "https://api.anthropic.com/v1"
      }

      assert {:ok, ^original} = Model.from(original)
    end

    test "with a tuple: anthropic provider" do
      input = {:anthropic, [model: "claude-3-5-haiku", temperature: 0.2]}
      assert {:ok, %Model{} = model} = Model.from(input)
      assert model.provider == :anthropic
      assert model.model == "claude-3-5-haiku"
      assert model.temperature == 0.2
      assert model.base_url == "https://api.anthropic.com/v1"
    end

    test "with a tuple: openai provider" do
      input = {:openai, [model: "gpt-4", temperature: 0.5]}
      assert {:ok, %Model{} = model} = Model.from(input)
      assert model.provider == :openai
      assert model.model == "gpt-4"
      assert model.temperature == 0.5
      assert model.base_url == "https://api.openai.com/v1"
    end

    test "with a tuple: openrouter provider" do
      input = {:openrouter, [model: "anthropic/claude-3-opus-20240229", max_tokens: 2000]}
      assert {:ok, %Model{} = model} = Model.from(input)
      assert model.provider == :openrouter
      assert model.model == "anthropic/claude-3-opus-20240229"
      assert model.max_tokens == 2000
      assert model.base_url == "https://openrouter.ai/api/v1"
    end

    test "with a tuple: cloudflare provider" do
      input = {:cloudflare, [model: "@cf/meta/llama-3-8b-instruct", max_retries: 2]}
      assert {:ok, %Model{} = model} = Model.from(input)
      assert model.provider == :cloudflare
      assert model.model == "@cf/meta/llama-3-8b-instruct"
      assert model.max_retries == 2
      assert model.base_url == "https://api.cloudflare.com/client/v4/accounts"
    end

    test "with a tuple: missing model" do
      input = {:anthropic, [temperature: 0.2]}
      assert {:error, message} = Model.from(input)
      assert message =~ "model is required"
    end

    test "with a category tuple" do
      input = {:category, :chat, :fastest}
      assert {:ok, %Model{} = model} = Model.from(input)
      assert model.id == "chat_fastest"
      assert model.name == "chat fastest Model"
      assert model.description =~ "Category-based model"
    end

    test "with invalid input" do
      assert {:error, message} = Model.from("not_a_valid_input")
      assert message =~ "Invalid model specification"
    end

    test "with invalid provider" do
      input = {:invalid_provider, [model: "test"]}
      assert {:error, message} = Model.from(input)
      assert message =~ "No adapter found for provider"
    end
  end
end
