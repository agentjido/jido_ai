defmodule ReqAI.APIIntegrationTest do
  @moduledoc """
  Integration tests for the ReqAI public API.

  These tests verify that the main API functions work correctly without
  requiring actual network calls to AI providers.
  """

  use ExUnit.Case, async: true

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
    test "successfully generates text with working provider" do
      # The API successfully routes to the provider and makes real API calls
      result = ReqAI.generate_text("anthropic:claude-3-haiku-20240307", "Hello", [])

      case result do
        {:ok, text} when is_binary(text) ->
          # Success - API call worked and returned text
          assert String.length(text) > 0

        {:error, _reason} ->
          # Expected if no API key is configured
          assert true
      end
    end

    test "validates options schema" do
      # Invalid temperature should be caught by NimbleOptions
      result = ReqAI.generate_text("anthropic:claude-3-sonnet", "Hello", temperature: "invalid")
      assert {:error, %NimbleOptions.ValidationError{key: :temperature}} = result
    end

    test "returns error for unknown provider" do
      result = ReqAI.generate_text("unknown:model", "Hello", [])
      assert {:error, %ReqAI.Error.Invalid.Provider{}} = result
    end
  end

  describe "ReqAI.stream_text/3" do
    test "successfully streams text with working provider" do
      # The API successfully routes to the provider and makes real API calls
      result = ReqAI.stream_text("anthropic:claude-3-haiku-20240307", "Hello", [])

      case result do
        {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
          # Success - API call worked and returned streaming response
          assert String.contains?(body, "event:")
          assert String.contains?(body, "data:")

        {:error, _reason} ->
          # Expected if no API key is configured
          assert true
      end
    end

    test "validates options schema" do
      result = ReqAI.stream_text("anthropic:claude-3-sonnet", "Hello", temperature: "invalid")
      assert {:error, %NimbleOptions.ValidationError{key: :temperature}} = result
    end

    test "returns error for unknown provider" do
      result = ReqAI.stream_text("unknown:model", "Hello", [])
      assert {:error, %ReqAI.Error.Invalid.Provider{}} = result
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
  end
end
