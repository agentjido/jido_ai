defmodule ReqAI.ModelTest do
  use ExUnit.Case, async: true

  alias ReqAI.Model

  describe "new/3" do
    test "creates model with required fields" do
      model = Model.new(:openai, "gpt-4")

      assert model.provider == :openai
      assert model.model == "gpt-4"
      assert model.max_retries == 3
    end

    test "creates model with options" do
      model =
        Model.new(:anthropic, "claude-3-sonnet",
          temperature: 0.7,
          max_tokens: 1000,
          max_retries: 5
        )

      assert model.provider == :anthropic
      assert model.model == "claude-3-sonnet"
      assert model.temperature == 0.7
      assert model.max_tokens == 1000
      assert model.max_retries == 5
    end

    test "creates model with limit" do
      limit = %{context: 128_000, output: 4096}
      model = Model.new(:openai, "gpt-4", limit: limit)

      assert model.limit == limit
    end
  end

  describe "from/1" do
    test "returns existing model struct unchanged" do
      original = %Model{provider: :openai, model: "gpt-4", max_retries: 3}

      assert {:ok, result} = Model.from(original)
      assert result == original
    end

    test "creates model from tuple with model option" do
      assert {:ok, model} = Model.from({:openai, model: "gpt-4"})

      assert model.provider == :openai
      assert model.model == "gpt-4"
      assert model.max_retries == 3
    end

    test "creates model from tuple with full options" do
      opts = [model: "gpt-4", temperature: 0.7, max_tokens: 1000, max_retries: 5]

      assert {:ok, model} = Model.from({:openai, opts})

      assert model.provider == :openai
      assert model.model == "gpt-4"
      assert model.temperature == 0.7
      assert model.max_tokens == 1000
      assert model.max_retries == 5
    end

    test "returns error for tuple missing model" do
      assert {:error, error} = Model.from({:openai, temperature: 0.7})

      assert error.tag == :missing_model
      assert error.reason == "model is required in options"
      assert error.context[:provider] == :openai
    end

    test "returns error for tuple with invalid model" do
      assert {:error, error} = Model.from({:openai, model: 123})

      assert error.tag == :invalid_model
      assert error.reason == "model must be a string"
    end

    test "creates model from string specification" do
      assert {:ok, model} = Model.from("openai:gpt-4")

      assert model.provider == :openai
      assert model.model == "gpt-4"
      assert model.max_retries == 3
    end

    test "creates model from string with complex model name" do
      assert {:ok, model} = Model.from("openrouter:anthropic/claude-3.5-sonnet")

      assert model.provider == :openrouter
      assert model.model == "anthropic/claude-3.5-sonnet"
    end

    test "returns error for invalid string format" do
      assert {:error, error} = Model.from("invalid-format")

      assert error.tag == :invalid_format
      assert error.reason == "Invalid model specification. Expected format: 'provider:model'"
    end

    test "returns error for empty string parts" do
      assert {:error, error} = Model.from(":gpt-4")

      assert error.tag == :invalid_format

      assert {:error, error} = Model.from("openai:")

      assert error.tag == :invalid_format
    end

    test "returns error for invalid input types" do
      assert {:error, error} = Model.from(123)

      assert error.tag == :invalid_input
      assert error.reason == "Invalid model specification"

      assert {:error, error} = Model.from(%{provider: :openai})

      assert error.tag == :invalid_input
    end
  end

  describe "from!/1" do
    test "returns model on success" do
      model = Model.from!("openai:gpt-4")

      assert model.provider == :openai
      assert model.model == "gpt-4"
    end

    test "raises exception on error" do
      assert_raise ReqAI.Error.Validation.Error, fn ->
        Model.from!("invalid-format")
      end
    end
  end

  describe "valid?/1" do
    test "returns true for valid model" do
      model = %Model{provider: :openai, model: "gpt-4", max_retries: 3}

      assert Model.valid?(model)
    end

    test "returns true for model with optional fields" do
      model = %Model{
        provider: :anthropic,
        model: "claude-3-sonnet",
        temperature: 0.7,
        max_tokens: 1000,
        max_retries: 5,
        limit: %{context: 128_000, output: 4096}
      }

      assert Model.valid?(model)
    end

    test "returns false for non-model struct" do
      refute Model.valid?(%{provider: :openai, model: "gpt-4"})
    end

    test "returns false for model with invalid provider" do
      model = %Model{provider: "openai", model: "gpt-4", max_retries: 3}

      refute Model.valid?(model)
    end

    test "returns false for model with invalid model name" do
      model = %Model{provider: :openai, model: "", max_retries: 3}

      refute Model.valid?(model)

      model = %Model{provider: :openai, model: nil, max_retries: 3}

      refute Model.valid?(model)
    end

    test "returns false for model with invalid max_retries" do
      model = %Model{provider: :openai, model: "gpt-4", max_retries: -1}

      refute Model.valid?(model)

      model = %Model{provider: :openai, model: "gpt-4", max_retries: "3"}

      refute Model.valid?(model)
    end
  end
end
