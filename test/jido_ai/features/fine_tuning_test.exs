defmodule Jido.AI.Features.FineTuningTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Features.FineTuning
  alias Jido.AI.Model

  describe "fine_tuned?/1" do
    test "detects OpenAI fine-tuned models" do
      model = %Model{provider: :openai, model: "ft:gpt-4-0613:org:suffix:id"}
      assert FineTuning.fine_tuned?(model)
    end

    test "detects Google fine-tuned models" do
      model = %Model{provider: :google, model: "projects/proj/locations/us/models/model1"}
      assert FineTuning.fine_tuned?(model)
    end

    test "detects Cohere fine-tuned models" do
      model = %Model{provider: :cohere, model: "custom-model-123"}
      assert FineTuning.fine_tuned?(model)
    end

    test "detects Together fine-tuned models" do
      model = %Model{provider: :together, model: "org/model"}
      assert FineTuning.fine_tuned?(model)
    end

    test "returns false for base models" do
      model = %Model{provider: :openai, model: "gpt-4"}
      refute FineTuning.fine_tuned?(model)
    end

    test "works with string model IDs" do
      assert FineTuning.fine_tuned?("ft:gpt-4:org:id")
      refute FineTuning.fine_tuned?("gpt-4")
    end
  end

  describe "parse_model_id/2" do
    test "parses OpenAI fine-tuned ID with suffix" do
      {:ok, info} = FineTuning.parse_model_id("ft:gpt-4-0613:org:suffix:id", :openai)

      assert info.provider == :openai
      assert info.base_model == "gpt-4-0613"
      assert info.organization == "org"
      assert info.suffix == "suffix"
      assert info.fine_tune_id == "id"
    end

    test "parses OpenAI fine-tuned ID without suffix" do
      {:ok, info} = FineTuning.parse_model_id("ft:gpt-4-0613:org:id", :openai)

      assert info.base_model == "gpt-4-0613"
      assert info.organization == "org"
      assert info.suffix == nil
      assert info.fine_tune_id == "id"
    end

    test "parses Google fine-tuned ID" do
      {:ok, info} =
        FineTuning.parse_model_id("projects/my-proj/locations/us/models/gemini-custom", :google)

      assert info.provider == :google
      assert info.organization == "my-proj"
      assert info.fine_tune_id == "gemini-custom"
    end

    test "parses Cohere fine-tuned ID" do
      {:ok, info} = FineTuning.parse_model_id("custom-model-123", :cohere)

      assert info.provider == :cohere
      assert info.base_model == "command"
      assert info.fine_tune_id == "custom-model-123"
    end

    test "parses Together fine-tuned ID" do
      {:ok, info} = FineTuning.parse_model_id("my-org/my-model", :together)

      assert info.provider == :together
      assert info.organization == "my-org"
      assert info.fine_tune_id == "my-org/my-model"
    end

    test "returns error for base model" do
      assert {:error, :not_fine_tuned} = FineTuning.parse_model_id("gpt-4", :openai)
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = FineTuning.parse_model_id("ft:invalid", :openai)
    end

    test "returns error for unsupported provider" do
      assert {:error, :not_fine_tuned} = FineTuning.parse_model_id("model", :ollama)
    end
  end

  describe "get_base_model/1" do
    test "extracts base model from OpenAI fine-tuned" do
      model = %Model{provider: :openai, model: "ft:gpt-4-0613:org:suffix:id"}

      {:ok, base} = FineTuning.get_base_model(model)
      assert base == "gpt-4-0613"
    end

    test "extracts base model from Google fine-tuned" do
      model = %Model{provider: :google, model: "projects/proj/locations/us/models/gemini-ft"}

      {:ok, base} = FineTuning.get_base_model(model)
      assert base == "gemini-pro"
    end

    test "returns error for base model" do
      model = %Model{provider: :openai, model: "gpt-4"}

      assert {:error, :not_fine_tuned} = FineTuning.get_base_model(model)
    end
  end

  describe "parse_model_id/2 validation" do
    test "returns error for empty model ID" do
      assert {:error, :empty_model_id} = FineTuning.parse_model_id("", :openai)
    end

    test "returns error for model ID too long" do
      long_id = "ft:" <> String.duplicate("a", 520)

      assert {:error, reason} = FineTuning.parse_model_id(long_id, :openai)
      assert is_binary(reason)
      assert reason =~ "too long"
      assert reason =~ "512"
    end

    test "returns error for model ID with invalid characters" do
      invalid_id = "ft:gpt-4:org:suffix:id@#$%"

      assert {:error, reason} = FineTuning.parse_model_id(invalid_id, :openai)
      assert is_binary(reason)
      assert reason =~ "invalid characters"
    end

    test "returns error for non-string model ID" do
      assert {:error, :invalid_model_id} = FineTuning.parse_model_id(123, :openai)
      assert {:error, :invalid_model_id} = FineTuning.parse_model_id(nil, :openai)
      assert {:error, :invalid_model_id} = FineTuning.parse_model_id(%{}, :openai)
    end
  end

  describe "discover/2" do
    test "returns not implemented error" do
      assert {:error, :not_implemented} = FineTuning.discover(:openai, "test-api-key")
    end

    test "returns not implemented for any provider" do
      assert {:error, :not_implemented} = FineTuning.discover(:google, "test-key")
      assert {:error, :not_implemented} = FineTuning.discover(:cohere, "test-key")
    end
  end

  describe "supports_capability?/2" do
    test "returns false for base model" do
      model = %Model{provider: :openai, model: "gpt-4"}
      refute FineTuning.supports_capability?(model, :streaming)
    end

    test "returns false when base model cannot be parsed" do
      model = %Model{provider: :openai, model: "ft:invalid-format"}
      refute FineTuning.supports_capability?(model, :streaming)
    end

    test "returns false when base model lookup fails" do
      # Model with valid fine-tuned format but invalid base model
      model = %Model{provider: :openai, model: "ft:nonexistent-model:org:id"}
      refute FineTuning.supports_capability?(model, :streaming)
    end
  end
end
