defmodule Jido.AI.Actions.LLM.EmbedTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.LLM.Embed

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context

  describe "schema" do
    test "has required and optional fields" do
      refute Embed.schema().fields[:model].meta.required
      refute Embed.schema().fields[:texts].meta.required
      refute Embed.schema().fields[:texts_list].meta.required
      refute Embed.schema().fields[:dimensions].meta.required
      refute Embed.schema().fields[:timeout].meta.required
    end
  end

  describe "run/2" do
    test "embeds single text with default model resolution" do
      expect(ReqLLM.Embedding, :embed, fn model, texts, opts ->
        assert model == Jido.AI.resolve_model(:embedding)
        assert texts == ["Hello world"]
        assert opts == []
        {:ok, [[0.1, 0.2, 0.3]]}
      end)

      assert {:ok, result} = Embed.run(%{texts: "Hello world"}, %{})
      assert result.model == Jido.AI.resolve_model(:embedding)
      assert result.count == 1
      assert result.dimensions == 3
      assert result.embeddings == [[0.1, 0.2, 0.3]]
    end

    test "embeds multiple texts with dimensions and timeout options" do
      expect(ReqLLM.Embedding, :embed, fn model, texts, opts ->
        assert model == "openai:text-embedding-3-small"
        assert texts == ["one", "two"]
        assert opts[:dimensions] == 2
        assert opts[:receive_timeout] == 1_000
        {:ok, [[0.5, 0.4], [0.3, 0.2]]}
      end)

      params = %{
        model: "openai:text-embedding-3-small",
        texts_list: ["one", "two"],
        dimensions: 2,
        timeout: 1_000
      }

      assert {:ok, result} = Embed.run(params, %{})
      assert result.model == "openai:text-embedding-3-small"
      assert result.count == 2
      assert result.dimensions == 2
    end

    test "uses context default model when omitted" do
      context = %{
        provided_params: [:texts],
        plugin_state: %{chat: %{default_model: :capable}}
      }

      expect(ReqLLM.Embedding, :embed, fn model, texts, _opts ->
        assert model == Jido.AI.resolve_model(:capable)
        assert texts == ["hello"]
        {:ok, [[0.9]]}
      end)

      assert {:ok, result} = Embed.run(%{texts: "hello"}, context)
      assert result.model == Jido.AI.resolve_model(:capable)
    end

    test "explicit model overrides context default model" do
      context = %{
        provided_params: [:texts, :model],
        plugin_state: %{chat: %{default_model: :embedding}}
      }

      expect(ReqLLM.Embedding, :embed, fn model, texts, _opts ->
        assert model == "custom:embedding-model"
        assert texts == ["hello"]
        {:ok, [[0.8]]}
      end)

      assert {:ok, result} = Embed.run(%{texts: "hello", model: "custom:embedding-model"}, context)
      assert result.model == "custom:embedding-model"
    end

    test "returns validation error when text input is missing" do
      assert {:error, _reason} = Embed.run(%{}, %{})
    end

    test "returns validation error when text contains dangerous bytes" do
      assert {:error, _reason} = Embed.run(%{texts: "bad" <> <<0>>}, %{})
    end

    test "sanitizes provider errors" do
      expect(ReqLLM.Embedding, :embed, fn _model, _texts, _opts ->
        {:error, :timeout}
      end)

      assert {:error, "Request timed out"} = Embed.run(%{texts: "hello"}, %{})
    end

    test "returns sanitized error on invalid model format" do
      assert {:error, "An error occurred"} = Embed.run(%{texts: "hello", model: 123}, %{})
    end
  end
end
