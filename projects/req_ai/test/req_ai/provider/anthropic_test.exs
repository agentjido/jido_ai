defmodule ReqAI.Provider.AnthropicTest do
  use ExUnit.Case, async: true

  alias ReqAI.{Model, Provider.Anthropic, Error}

  doctest Anthropic

  describe "provider_info/0" do
    test "returns correct provider information" do
      info = Anthropic.provider_info()

      assert info.id == :anthropic
      assert info.name == "Anthropic"
      assert info.base_url == "https://api.anthropic.com"
      assert is_map(info.models)
      assert Map.has_key?(info.models, "claude-3-5-sonnet-20241022")
    end
  end

  describe "generate_text/3" do
    setup do
      model = Model.new(:anthropic, "claude-3-5-sonnet-20241022")
      {:ok, model: model}
    end

    test "returns error when API key is missing", %{model: model} do
      System.delete_env("ANTHROPIC_API_KEY")
      Application.delete_env(:req_ai, :anthropic_api_key)

      assert {:error, %Error.Invalid.Parameter{}} = Anthropic.generate_text(model, "Hello")
    end

    @tag :skip
    test "makes successful API request with mocked response", %{model: model} do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert {:ok, _text} = Anthropic.generate_text(model, "Hello")

      System.delete_env("ANTHROPIC_API_KEY")
    end

    @tag :skip
    test "handles API error responses", %{model: model} do
      System.put_env("ANTHROPIC_API_KEY", "invalid-key")

      assert {:error, %Error.API.Request{}} = Anthropic.generate_text(model, "Hello")

      System.delete_env("ANTHROPIC_API_KEY")
    end

    @tag :skip
    test "includes system prompt when provided", %{model: model} do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      Anthropic.generate_text(model, "Hello", system_prompt: "You are helpful")

      System.delete_env("ANTHROPIC_API_KEY")
    end
  end
end
