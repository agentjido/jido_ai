defmodule JidoTest.AI.Model.FromTest do
  use ExUnit.Case
  import JidoTest.ReqLLMTestHelper

  alias Jido.AI.Model

  @moduletag :capture_log
  @moduletag :reqllm_integration

  describe "Model.from/1 with ReqLLM.Model pass-through" do
    test "passes through existing ReqLLM.Model unchanged" do
      original = create_test_model(:openai, model: "gpt-4")

      {:ok, result} = Model.from(original)

      assert result == original
      assert_reqllm_model(result)
    end

    test "passes through ReqLLM.Model with all fields preserved" do
      original = %ReqLLM.Model{
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        max_tokens: 4096,
        capabilities: %{tool_call: true, vision: true},
        modalities: %{input: [:text, :image], output: [:text]},
        cost: %{input: 3.0, output: 15.0}
      }

      {:ok, result} = Model.from(original)

      assert result.provider == :anthropic
      assert result.model == "claude-3-5-sonnet"
      assert result.max_tokens == 4096
      assert result.capabilities == %{tool_call: true, vision: true}
    end
  end

  describe "Model.from/1 with Jido.AI.Model struct" do
    test "converts Jido.AI.Model to ReqLLM.Model" do
      original = %Model{
        provider: :anthropic,
        model: "claude-3-5-haiku",
        base_url: "https://api.anthropic.com/v1"
      }

      {:ok, result} = Model.from(original)

      assert_reqllm_model(result)
      assert result.provider == original.provider
      assert result.model == original.model
    end

    test "converts Jido.AI.Model with all standard providers" do
      # Note: cloudflare string spec is not supported by ReqLLM, but tuple format works
      providers = [:openai, :anthropic, :google, :openrouter]

      for provider <- providers do
        original = %Model{provider: provider, model: "test-model"}
        {:ok, result} = Model.from(original)

        assert_reqllm_model(result)
        assert result.provider == provider
        assert result.model == "test-model"
      end
    end
  end

  describe "Model.from/1 with provider tuples" do
    test "with anthropic provider" do
      input = {:anthropic, [model: "claude-3-5-haiku", temperature: 0.2]}
      {:ok, model} = Model.from(input)

      assert_reqllm_model(model)
      assert model.provider == :anthropic
      assert model.model == "claude-3-5-haiku"
    end

    test "with openai provider" do
      input = {:openai, [model: "gpt-4", temperature: 0.5]}
      {:ok, model} = Model.from(input)

      assert_reqllm_model(model)
      assert model.provider == :openai
      assert model.model == "gpt-4"
    end

    test "with google provider" do
      input = {:google, [model: "gemini-pro", max_tokens: 1024]}
      {:ok, model} = Model.from(input)

      assert_reqllm_model(model)
      assert model.provider == :google
      assert model.model == "gemini-pro"
    end

    test "with openrouter provider" do
      input = {:openrouter, [model: "anthropic/claude-3-opus-20240229", max_tokens: 2000]}
      {:ok, model} = Model.from(input)

      assert_reqllm_model(model)
      assert model.provider == :openrouter
      assert model.model == "anthropic/claude-3-opus-20240229"
    end

    test "with cloudflare provider tuple" do
      input = {:cloudflare, [model: "@cf/meta/llama-3-8b-instruct", max_retries: 2]}
      {:ok, model} = Model.from(input)

      # Cloudflare works with tuple format
      assert_reqllm_model(model)
      assert model.provider == :cloudflare
      assert model.model == "@cf/meta/llama-3-8b-instruct"
    end

    test "with max_retries option" do
      input = {:openai, [model: "gpt-4", max_retries: 3]}
      {:ok, model} = Model.from(input)

      assert model.max_retries == 3
    end

    test "with max_tokens option" do
      input = {:anthropic, [model: "claude-3-sonnet", max_tokens: 4096]}
      {:ok, model} = Model.from(input)

      assert model.max_tokens == 4096
    end
  end

  describe "Model.from/1 with string specifications" do
    test "converts 'provider:model' string format" do
      input = "openai:gpt-4"
      {:ok, model} = Model.from(input)

      assert_reqllm_model(model)
      assert model.provider == :openai
      assert model.model == "gpt-4"
    end

    test "converts anthropic string spec" do
      input = "anthropic:claude-3-5-sonnet"
      {:ok, model} = Model.from(input)

      assert model.provider == :anthropic
      assert model.model == "claude-3-5-sonnet"
    end

    test "converts google string spec" do
      input = "google:gemini-pro"
      {:ok, model} = Model.from(input)

      assert model.provider == :google
      assert model.model == "gemini-pro"
    end

    test "converts openrouter string spec with nested model name" do
      input = "openrouter:anthropic/claude-3-opus"
      {:ok, model} = Model.from(input)

      assert model.provider == :openrouter
      assert model.model == "anthropic/claude-3-opus"
    end

    test "cloudflare string spec returns error (not supported by ReqLLM)" do
      input = "cloudflare:@cf/meta/llama-3-8b"
      result = Model.from(input)

      # Cloudflare is not a supported provider in ReqLLM
      assert match?({:error, _}, result)
    end
  end

  describe "Model.from/1 error handling" do
    test "returns error for tuple with missing model" do
      input = {:anthropic, [temperature: 0.2]}
      {:error, message} = Model.from(input)

      assert message =~ "model" or is_struct(message)
    end

    test "returns error for category tuples (not supported)" do
      input = {:category, :chat, :fastest}
      {:error, message} = Model.from(input)

      assert message =~ "not supported" or message =~ "Category"
    end

    test "returns error for invalid input types" do
      invalid_inputs = [
        123,
        [:not, :valid],
        %{not: "a model"}
      ]

      for input <- invalid_inputs do
        result = Model.from(input)
        assert match?({:error, _}, result), "Expected error for input: #{inspect(input)}"
      end
    end

    test "returns error tuple for completely invalid input" do
      result = Model.from(nil)
      assert match?({:error, _}, result)
    end

    test "handles empty options list" do
      input = {:openai, []}
      {:error, _message} = Model.from(input)
    end
  end

  describe "Model.from/1 field mapping" do
    test "maps provider correctly across all supported providers" do
      test_cases = [
        {:openai, "gpt-4", :openai},
        {:anthropic, "claude-3", :anthropic},
        {:google, "gemini", :google},
        {:cloudflare, "llama", :cloudflare},
        {:openrouter, "meta/llama", :openrouter}
      ]

      for {provider, model_name, expected_provider} <- test_cases do
        {:ok, model} = Model.from({provider, [model: model_name]})
        assert model.provider == expected_provider
      end
    end

    test "preserves model name exactly as provided" do
      model_names = [
        "gpt-4-turbo-preview",
        "claude-3-5-sonnet-20241022",
        "gemini-1.5-pro-latest",
        "anthropic/claude-3-opus:beta"
      ]

      for model_name <- model_names do
        {:ok, model} = Model.from({:openai, [model: model_name]})
        assert model.model == model_name
      end
    end
  end

  describe "Model.from/1 with assert_model_conversion helper" do
    test "conversion helper validates openai" do
      assert_model_conversion({:openai, [model: "gpt-4"]}, :openai, "gpt-4")
    end

    test "conversion helper validates anthropic" do
      assert_model_conversion({:anthropic, [model: "claude-3"]}, :anthropic, "claude-3")
    end

    test "conversion helper validates string spec" do
      assert_model_conversion("google:gemini-pro", :google, "gemini-pro")
    end
  end

  describe "Model.validate_model_opts/1" do
    test "validates and returns ReqLLM.Model" do
      input = {:openai, [model: "gpt-4"]}
      {:ok, model} = Model.validate_model_opts(input)

      assert_reqllm_model(model)
    end

    test "returns error for invalid input" do
      {:error, _reason} = Model.validate_model_opts({:openai, []})
    end

    test "passes through valid ReqLLM.Model" do
      original = create_test_model(:anthropic, model: "claude-3")
      {:ok, result} = Model.validate_model_opts(original)

      assert result == original
    end
  end
end
