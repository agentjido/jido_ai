defmodule JidoTest.AI.ModelTest do
  use ExUnit.Case
  alias Jido.AI.Model

  @moduletag :capture_log

  describe "validate_model_opts/1" do
    test "validates provider with options" do
      assert {:ok, model} =
               Model.validate_model_opts(
                 {:anthropic,
                  [
                    model: "claude-3-5-haiku"
                  ]}
               )

      # ReqLLM.Model has different fields
      assert %ReqLLM.Model{} = model
      assert model.provider == :anthropic
      assert model.model == "claude-3-5-haiku"
    end

    test "validates provider with capabilities" do
      assert {:ok, model} =
               Model.validate_model_opts(
                 {:anthropic,
                  [
                    model: "claude-3-5-haiku",
                    capabilities: [:chat]
                  ]}
               )

      # ReqLLM.Model has different fields
      assert %ReqLLM.Model{} = model
      assert model.provider == :anthropic
      assert model.model == "claude-3-5-haiku"
      assert model.capabilities == [:chat]
    end

    test "validates provider atom" do
      assert {:ok, model} =
               Model.validate_model_opts({:anthropic, [model: "claude-3-5-haiku"]})

      # ReqLLM.Model has different fields
      assert %ReqLLM.Model{} = model
      assert model.provider == :anthropic
      assert model.model == "claude-3-5-haiku"
    end

    test "rejects invalid provider" do
      assert {:error, message} = Model.validate_model_opts(:invalid_provider)
      assert message =~ "Invalid model specification"
    end

    test "rejects missing model for provider" do
      assert {:error, message} =
               Model.validate_model_opts(
                 {:anthropic,
                  [
                    id: "anthropic_test",
                    name: "Test Model",
                    modality: "text"
                  ]}
               )

      assert message =~ "model option is required"
    end
  end

  describe "new!/2" do
    test "creates model with provider and options" do
      result = Model.new!(:anthropic, model: "claude-3-5-haiku-20240307")
      assert is_tuple(result)
      assert elem(result, 0) == :anthropic
      assert Keyword.get(elem(result, 1), :model) == "claude-3-5-haiku-20240307"
    end

    test "creates model with tuple format" do
      result = Model.new!({:anthropic, [model: "claude-3-5-haiku-20240307"]})
      assert is_tuple(result)
      assert elem(result, 0) == :anthropic
      assert Keyword.get(elem(result, 1), :model) == "claude-3-5-haiku-20240307"
    end

    test "handles unknown provider" do
      result = Model.new!(:unknown_provider, model: "test-model")
      assert is_tuple(result)
      assert elem(result, 0) == :openai
      assert Keyword.get(elem(result, 1), :original_provider) == :unknown_provider
    end
  end

  describe "validate/1" do
    test "validates provider with options" do
      assert {:ok, {provider, _opts}} = Model.validate({:anthropic, [model: "claude-3-5-haiku"]})
      assert provider == :anthropic
    end

    test "validates provider atom" do
      assert {:ok, provider} = Model.validate(:anthropic)
      assert provider == :anthropic
    end

    test "rejects invalid input" do
      assert {:error, message} = Model.validate("not_a_valid_input")
      assert message =~ "Invalid model configuration"
    end
  end
end
