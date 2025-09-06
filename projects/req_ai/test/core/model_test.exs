defmodule ReqAI.ModelTest do
  use ExUnit.Case, async: true

  import ReqAI.Test.Macros

  alias ReqAI.Model

  describe "new/3" do
    test "creates model with required fields" do
      model = Model.new(:openai, "gpt-4")
      assert_struct(model, Model, provider: :openai, model: "gpt-4", max_retries: 3)
    end

    test "creates model with options" do
      model =
        Model.new(:anthropic, "claude-3-sonnet",
          temperature: 0.7,
          max_tokens: 1000,
          max_retries: 5
        )

      assert_struct(model, Model,
        provider: :anthropic,
        model: "claude-3-sonnet",
        temperature: 0.7,
        max_tokens: 1000,
        max_retries: 5
      )
    end

    test "creates model with limit" do
      limit = %{context: 128_000, output: 4096}
      model = Model.new(:openai, "gpt-4", limit: limit)
      assert model.limit == limit
    end
  end

  describe "from/1 success cases" do
    test "returns existing model struct unchanged" do
      original = %Model{provider: :openai, model: "gpt-4", max_retries: 3}
      assert_ok(Model.from(original))
      {:ok, result} = Model.from(original)
      assert result == original
    end

    test "creates model from tuple with model option" do
      assert_ok(Model.from({:openai, model: "gpt-4"}))
      {:ok, model} = Model.from({:openai, model: "gpt-4"})
      assert_struct(model, Model, provider: :openai, model: "gpt-4", max_retries: 3)
    end

    test "creates model from tuple with full options" do
      input = {:openai, [model: "gpt-4", temperature: 0.7, max_tokens: 1000, max_retries: 5]}
      assert_ok(Model.from(input))
      {:ok, model} = Model.from(input)

      assert_struct(model, Model,
        provider: :openai,
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000,
        max_retries: 5
      )
    end

    test "creates model from string specification" do
      assert_ok(Model.from("openai:gpt-4"))
      {:ok, model} = Model.from("openai:gpt-4")
      assert_struct(model, Model, provider: :openai, model: "gpt-4", max_retries: 3)
    end

    test "creates model from string with complex model name" do
      assert_ok(Model.from("openrouter:anthropic/claude-3.5-sonnet"))
      {:ok, model} = Model.from("openrouter:anthropic/claude-3.5-sonnet")
      assert_struct(model, Model, provider: :openrouter, model: "anthropic/claude-3.5-sonnet")
    end
  end

  describe "from/1 error cases" do
    test "returns error for tuple missing model" do
      assert_error(Model.from({:openai, temperature: 0.7}))
      {:error, error} = Model.from({:openai, temperature: 0.7})
      assert error.tag == :missing_model
    end

    test "returns error for tuple with invalid model type" do
      assert_error(Model.from({:openai, model: 123}))
      {:error, error} = Model.from({:openai, model: 123})
      assert error.tag == :invalid_model_type
    end

    test "returns error for invalid string formats" do
      test_cases = [
        {"invalid-format", :invalid_model_spec},
        {":gpt-4", :invalid_model_spec},
        {"openai:", :invalid_model_spec},
        {"malicious_provider:model", :invalid_provider},
        {"definitely_not_supported:model", :invalid_provider}
      ]

      for {input, expected_tag} <- test_cases do
        assert_error(Model.from(input))
        {:error, error} = Model.from(input)
        assert error.tag == expected_tag
      end
    end

    test "returns error for invalid input types" do
      test_cases = [123, %{provider: :openai}]

      for input <- test_cases do
        assert_error(Model.from(input))
        {:error, error} = Model.from(input)
        assert error.tag == :invalid_model_spec
      end
    end
  end

  describe "from!/1" do
    test "returns model on success" do
      model = Model.from!("openai:gpt-4")
      assert_struct(model, Model, provider: :openai, model: "gpt-4")
    end

    test "raises exception on error" do
      assert_raise ReqAI.Error.Validation.Error, fn ->
        Model.from!("invalid-format")
      end
    end
  end

  describe "valid?/1" do
    test "returns true for valid models" do
      valid_models = [
        %Model{provider: :openai, model: "gpt-4", max_retries: 3},
        %Model{
          provider: :anthropic,
          model: "claude-3-sonnet",
          temperature: 0.7,
          max_tokens: 1000,
          max_retries: 5,
          limit: %{context: 128_000, output: 4096}
        }
      ]

      for model <- valid_models do
        assert Model.valid?(model)
      end
    end

    test "returns false for invalid models" do
      invalid_models = [
        %{provider: :openai, model: "gpt-4"},
        %Model{provider: "openai", model: "gpt-4", max_retries: 3},
        %Model{provider: :openai, model: "", max_retries: 3},
        %Model{provider: :openai, model: nil, max_retries: 3},
        %Model{provider: :openai, model: "gpt-4", max_retries: -1},
        %Model{provider: :openai, model: "gpt-4", max_retries: "3"}
      ]

      for model <- invalid_models do
        refute Model.valid?(model)
      end
    end
  end
end
