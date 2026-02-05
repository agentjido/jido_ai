defmodule Jido.AI.Actions.LLM.EmbedTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.LLM.Embed

  describe "Embed action" do
    test "has correct metadata" do
      metadata = Embed.__action_metadata__()
      assert metadata.name == "llm_embed"
      assert metadata.category == "ai"
      assert metadata.vsn == "1.0.0"
    end

    test "requires model parameter" do
      assert {:error, _} = Jido.Exec.run(Embed, %{texts: "Hello"}, %{})
    end

    test "accepts single text parameter" do
      params = %{
        model: "openai:text-embedding-3-small",
        texts: "Hello world"
      }

      assert params.model == "openai:text-embedding-3-small"
      assert params.texts == "Hello world"
    end

    test "accepts texts_list parameter for batch" do
      params = %{
        model: "openai:text-embedding-3-small",
        texts_list: ["Hello", "World"]
      }

      assert params.model == "openai:text-embedding-3-small"
      assert params.texts_list == ["Hello", "World"]
    end

    test "accepts optional dimensions parameter" do
      params = %{
        model: "openai:text-embedding-3-small",
        texts: "Test",
        dimensions: 1536
      }

      assert params.dimensions == 1536
    end
  end
end
