defmodule Jido.AI.FeaturesTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{Features, Model}

  describe "supports?/2" do
    test "detects RAG support for Cohere" do
      model = %Model{provider: :cohere, model: "command-r"}
      assert Features.supports?(model, :rag)
    end

    test "detects RAG support for Google" do
      model = %Model{provider: :google, model: "gemini-pro"}
      assert Features.supports?(model, :rag)
    end

    test "detects RAG support for Anthropic" do
      model = %Model{provider: :anthropic, model: "claude-3-sonnet"}
      assert Features.supports?(model, :rag)
    end

    test "no RAG support for OpenAI" do
      model = %Model{provider: :openai, model: "gpt-4"}
      refute Features.supports?(model, :rag)
    end

    test "detects code execution support for OpenAI GPT-4" do
      model = %Model{provider: :openai, model: "gpt-4-0613"}
      assert Features.supports?(model, :code_execution)
    end

    test "detects code execution support for OpenAI GPT-3.5" do
      model = %Model{provider: :openai, model: "gpt-3.5-turbo"}
      assert Features.supports?(model, :code_execution)
    end

    test "no code execution support for Anthropic" do
      model = %Model{provider: :anthropic, model: "claude-3-sonnet"}
      refute Features.supports?(model, :code_execution)
    end

    test "detects plugin support for OpenAI" do
      model = %Model{provider: :openai, model: "gpt-4"}
      assert Features.supports?(model, :plugins)
    end

    test "detects plugin support for Anthropic" do
      model = %Model{provider: :anthropic, model: "claude-3-sonnet"}
      assert Features.supports?(model, :plugins)
    end

    test "detects plugin support for Google" do
      model = %Model{provider: :google, model: "gemini-pro"}
      assert Features.supports?(model, :plugins)
    end

    test "detects fine-tuning for OpenAI fine-tuned model" do
      model = %Model{provider: :openai, model: "ft:gpt-4-0613:org:suffix:id"}
      assert Features.supports?(model, :fine_tuning)
    end

    test "detects fine-tuning for Google fine-tuned model" do
      model = %Model{provider: :google, model: "projects/proj/locations/us/models/model1"}
      assert Features.supports?(model, :fine_tuning)
    end

    test "no fine-tuning for base models" do
      model = %Model{provider: :openai, model: "gpt-4"}
      refute Features.supports?(model, :fine_tuning)
    end
  end

  describe "capabilities/1" do
    test "returns RAG and fine-tuning for Cohere" do
      model = %Model{provider: :cohere, model: "command-r"}
      caps = Features.capabilities(model)
      assert :rag in caps
      assert :fine_tuning in caps
    end

    test "returns RAG and plugins for Anthropic" do
      model = %Model{provider: :anthropic, model: "claude-3-sonnet"}
      caps = Features.capabilities(model)
      assert :rag in caps
      assert :plugins in caps
    end

    test "returns code execution, plugins, and fine-tuning for OpenAI" do
      model = %Model{provider: :openai, model: "gpt-4"}
      caps = Features.capabilities(model)
      assert :code_execution in caps
      assert :plugins in caps
      assert :fine_tuning in caps
    end

    test "returns empty list for providers without special features" do
      model = %Model{provider: :ollama, model: "llama2"}
      caps = Features.capabilities(model)
      assert caps == []
    end

    test "includes fine_tuning for fine-tuned models" do
      model = %Model{provider: :openai, model: "ft:gpt-4:org:id"}
      caps = Features.capabilities(model)
      assert :fine_tuning in caps
    end
  end

  describe "provider_supports?/2" do
    test "Cohere supports RAG" do
      assert Features.provider_supports?(:cohere, :rag)
    end

    test "OpenAI supports code execution" do
      assert Features.provider_supports?(:openai, :code_execution)
    end

    test "Anthropic supports plugins" do
      assert Features.provider_supports?(:anthropic, :plugins)
    end

    test "Ollama does not support RAG" do
      refute Features.provider_supports?(:ollama, :rag)
    end

    test "Groq does not support code execution" do
      refute Features.provider_supports?(:groq, :code_execution)
    end
  end

  describe "provider_features/1" do
    test "returns features for Cohere" do
      features = Features.provider_features(:cohere)
      assert :rag in features
      assert :fine_tuning in features
    end

    test "returns features for OpenAI" do
      features = Features.provider_features(:openai)
      assert :code_execution in features
      assert :plugins in features
      assert :fine_tuning in features
    end

    test "returns empty list for Ollama" do
      features = Features.provider_features(:ollama)
      assert features == []
    end
  end

  describe "providers_for/1" do
    test "returns providers supporting RAG" do
      providers = Features.providers_for(:rag)
      assert :cohere in providers
      assert :anthropic in providers
      assert :google in providers
    end

    test "returns providers supporting code execution" do
      providers = Features.providers_for(:code_execution)
      assert :openai in providers
      assert length(providers) == 1
    end

    test "returns providers supporting plugins" do
      providers = Features.providers_for(:plugins)
      assert :openai in providers
      assert :anthropic in providers
      assert :google in providers
    end

    test "returns providers supporting fine-tuning" do
      providers = Features.providers_for(:fine_tuning)
      assert :openai in providers
      assert :cohere in providers
      assert :google in providers
      assert :together in providers
    end
  end

  describe "edge cases" do
    test "supports?/2 returns false when Model.from/1 fails" do
      # Model.from/1 will fail for non-existent provider format
      refute Features.supports?("invalid-format", :rag)
    end

    test "capabilities/1 returns empty list when Model.from/1 fails" do
      # Model.from/1 will fail for non-existent provider format
      caps = Features.capabilities("invalid-format")
      assert caps == []
    end
  end
end
