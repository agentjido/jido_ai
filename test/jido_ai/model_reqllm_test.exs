defmodule Jido.AI.Model.ReqLLMTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Model

  describe "compute_reqllm_id/2" do
    test "computes ReqLLM ID from provider and model" do
      assert Model.compute_reqllm_id(:openai, "gpt-4o") == "openai:gpt-4o"

      assert Model.compute_reqllm_id(:anthropic, "claude-3-5-haiku") ==
               "anthropic:claude-3-5-haiku"

      assert Model.compute_reqllm_id(:google, "gemini-2.0-flash") == "google:gemini-2.0-flash"
    end

    test "handles non-atom providers" do
      assert Model.compute_reqllm_id("openai", "gpt-4o") == "openai:gpt-4o"

      assert Model.compute_reqllm_id("anthropic", "claude-3-5-haiku") ==
               "anthropic:claude-3-5-haiku"
    end
  end

  describe "ensure_reqllm_id/1" do
    test "computes reqllm_id when missing and provider/model are present" do
      model = %Model{
        provider: :openai,
        model: "gpt-4o",
        reqllm_id: nil
      }

      updated = Model.ensure_reqllm_id(model)
      assert updated.reqllm_id == "openai:gpt-4o"
    end

    test "computes reqllm_id when empty string and provider/model are present" do
      model = %Model{
        provider: :anthropic,
        model: "claude-3-5-haiku",
        reqllm_id: ""
      }

      updated = Model.ensure_reqllm_id(model)
      assert updated.reqllm_id == "anthropic:claude-3-5-haiku"
    end

    test "preserves existing reqllm_id" do
      model = %Model{
        provider: :openai,
        model: "gpt-4o",
        reqllm_id: "existing:id"
      }

      updated = Model.ensure_reqllm_id(model)
      assert updated.reqllm_id == "existing:id"
    end

    test "does not compute reqllm_id when provider is missing" do
      model = %Model{
        provider: nil,
        model: "gpt-4o",
        reqllm_id: nil
      }

      updated = Model.ensure_reqllm_id(model)
      assert updated.reqllm_id == nil
    end

    test "does not compute reqllm_id when model is missing" do
      model = %Model{
        provider: :openai,
        model: nil,
        reqllm_id: nil
      }

      updated = Model.ensure_reqllm_id(model)
      assert updated.reqllm_id == nil
    end
  end

  describe "from/1 with reqllm_id integration" do
    test "existing model struct gets ensured reqllm_id" do
      model = %Model{
        provider: :openai,
        model: "gpt-4o",
        reqllm_id: nil
      }

      {:ok, result} = Model.from(model)
      assert result.reqllm_id == "openai:gpt-4o"
    end

    test "category model gets reqllm_id computed" do
      {:ok, model} = Model.from({:category, :chat, :small})

      assert model.provider == nil
      assert model.model == "chat_small"
      assert model.reqllm_id == "chat:chat_small"
    end

    test "provider tuple creates model with reqllm_id through adapter" do
      # This tests the integration with provider adapters
      {:ok, model} = Model.from({:openai, [model: "gpt-4o"]})

      assert model.provider == :openai
      assert model.model == "gpt-4o"
      assert model.reqllm_id == "openai:gpt-4o"
    end
  end

  describe "model struct reqllm_id field" do
    test "reqllm_id field is present in struct" do
      model = %Model{}
      assert Map.has_key?(model, :reqllm_id)
    end

    test "reqllm_id can be set directly" do
      model = %Model{reqllm_id: "test:model"}
      assert model.reqllm_id == "test:model"
    end
  end
end
