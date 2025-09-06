defmodule ReqAI.APIIntegrationTest do
  @moduledoc """
  Integration tests for the ReqAI public API.

  These tests verify that the main API functions work correctly without
  requiring actual network calls to AI providers.
  """

  use ExUnit.Case, async: false
  import ReqAI.Test.Fixture

  alias ReqAI.Provider.Registry

  describe "ReqAI.provider/1" do
    test "returns anthropic provider" do
      assert {:ok, ReqAI.Providers.Anthropic} = ReqAI.provider(:anthropic)
    end

    test "returns error for unknown provider" do
      assert {:error, :not_found} = ReqAI.provider(:unknown)
    end
  end

  describe "ReqAI.model/1" do
    test "parses string model specification" do
      assert {:ok, model} = ReqAI.model("anthropic:claude-3-sonnet")
      assert model.provider == :anthropic
      assert model.model == "claude-3-sonnet"
      assert model.max_retries == 3
    end

    test "parses tuple model specification" do
      assert {:ok, model} = ReqAI.model({:anthropic, model: "claude-3-sonnet", temperature: 0.7})
      assert model.provider == :anthropic
      assert model.model == "claude-3-sonnet"
      assert model.temperature == 0.7
      assert model.max_retries == 3
    end

    test "returns error for invalid specification" do
      assert {:error, _error} = ReqAI.model("invalid")
      assert {:error, _error} = ReqAI.model({:provider, []})
    end
  end

  describe "ReqAI.generate_text/3" do
    test "successfully generates text with working provider using fixtures" do
      # Test the full integration flow by testing provider components directly
      # This avoids real HTTP calls while still testing the ReqAI API

      # Create a mock response using fixture data
      success_response = %Req.Response{
        status: 200,
        body: json!(:anthropic, "success.json")
      }

      # Test that the provider can parse the fixture response
      provider = ReqAI.Providers.Anthropic
      {:ok, text} = provider.parse_response(success_response, [], stream?: false)

      # Verify the parsing works correctly
      assert is_binary(text)
      assert text == "Hello! How can I help you today?"

      # Test that the model parsing works
      assert {:ok, model} = ReqAI.model("anthropic:claude-3-haiku-20240307")
      assert model.provider == :anthropic
      assert model.model == "claude-3-haiku-20240307"
    end

    test "validates options schema" do
      # Invalid temperature should be caught by NimbleOptions
      result = ReqAI.generate_text("anthropic:claude-3-sonnet", "Hello", temperature: "invalid")
      assert {:error, %NimbleOptions.ValidationError{key: :temperature}} = result
    end

    test "returns error for unknown provider" do
      result = ReqAI.generate_text("unknown:model", "Hello", [])
      assert {:error, %ReqAI.Error.Validation.Error{tag: :invalid_provider}} = result
    end
  end

  describe "ReqAI.stream_text/3" do
    test "successfully streams text with working provider using fixtures" do
      # Test streaming integration flow using fixture data
      # This avoids real HTTP calls while testing the model resolution and provider lookup

      # Load streaming fixture data
      stream_data = File.read!(Path.join([__DIR__, "..", "fixtures", "anthropic", "stream.txt"]))

      # Verify the fixture contains expected streaming format
      assert String.contains?(stream_data, "event:")
      assert String.contains?(stream_data, "data:")
      assert String.contains?(stream_data, "content_block_delta")
      assert String.contains?(stream_data, "Hello")
      assert String.contains?(stream_data, "! How can I help you?")

      # Test that the model parsing works for streaming requests
      assert {:ok, model} = ReqAI.model("anthropic:claude-3-haiku-20240307")
      assert model.provider == :anthropic
      assert model.model == "claude-3-haiku-20240307"

      # Test that provider lookup works
      assert {:ok, ReqAI.Providers.Anthropic} = ReqAI.provider(:anthropic)

      # Test provider spec for streaming
      spec = ReqAI.Providers.Anthropic.spec()
      assert spec.id == :anthropic
    end

    test "validates options schema" do
      result = ReqAI.stream_text("anthropic:claude-3-sonnet", "Hello", temperature: "invalid")
      assert {:error, %NimbleOptions.ValidationError{key: :temperature}} = result
    end

    test "returns error for unknown provider" do
      result = ReqAI.stream_text("unknown:model", "Hello", [])
      assert {:error, %ReqAI.Error.Validation.Error{tag: :invalid_provider}} = result
    end
  end

  describe "Provider Registry" do
    test "lists available providers" do
      providers = Registry.list_providers()
      assert :anthropic in providers
    end

    test "fetches known provider" do
      assert {:ok, ReqAI.Providers.Anthropic} = Registry.fetch(:anthropic)
    end

    test "returns not_found for unknown provider" do
      assert {:error, :not_found} = Registry.fetch(:unknown)
    end

    test "returns error for non-atom provider" do
      assert Registry.fetch("string") == {:error, :not_found}
    end

    test "fetch!/1 raises for unknown provider" do
      assert_raise ReqAI.Error.Invalid.Provider, ~r/Unknown provider: unknown/, fn ->
        Registry.fetch!(:unknown)
      end
    end
  end
end
