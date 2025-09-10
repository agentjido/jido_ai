defmodule ReqLLM.Coverage.Anthropic.SamplingParametersTest do
  use ExUnit.Case, async: true
  alias ReqLLM.Test.LiveFixture

  @moduletag :coverage
  @moduletag :anthropic
  @moduletag :sampling

  describe "temperature parameter" do
    test "low temperature (0.1) for deterministic output" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Count from 1 to 5")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("sampling/low_temperature", fn ->
          ReqLLM.generate_text(model, context: context, temperature: 0.1, max_tokens: 50)
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      assert text_content =~ "1"
      assert text_content =~ "5"
    end

    test "high temperature (1.0) for creative output" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Write a creative haiku about programming")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("sampling/high_temperature", fn ->
          ReqLLM.generate_text(model, context: context, temperature: 1.0, max_tokens: 100)
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should contain haiku-like structure
      assert String.contains?(text_content, "\n")
    end
  end

  describe "top_p parameter" do
    test "nucleus sampling with top_p=0.9" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Describe the color blue in 3 words")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("sampling/top_p_sampling", fn ->
          ReqLLM.generate_text(model, context: context, top_p: 0.9, max_tokens: 20)
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should be concise response
      word_count = text_content |> String.split() |> length()
      # Some flexibility for model interpretation
      assert word_count <= 6
    end
  end

  describe "top_k parameter" do
    test "truncated sampling with top_k=50" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("What comes after the number 9?")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("sampling/top_k_sampling", fn ->
          ReqLLM.generate_text(model, context: context, top_k: 50, max_tokens: 10)
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      assert text_content =~ "10"
    end
  end

  describe "combined sampling parameters" do
    test "temperature, top_p, and top_k together" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Tell me a programming joke")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("sampling/combined_sampling", fn ->
          ReqLLM.generate_text(model,
            context: context,
            temperature: 0.7,
            top_p: 0.9,
            top_k: 100,
            max_tokens: 100
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should contain humor elements
      assert String.length(text_content) > 10
    end
  end

  describe "parameter validation" do
    test "invalid temperature range should be handled gracefully" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Hello")
        ])

      # Anthropic API accepts 0-2 range, but some providers might validate
      {:ok, response} =
        LiveFixture.use_fixture("sampling/boundary_temperature", fn ->
          ReqLLM.generate_text(model, context: context, temperature: 2.0, max_tokens: 20)
        end)

      assert response.chunks != []
    end

    test "zero values for sampling parameters" do
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          ReqLLM.Message.user("Say exactly: Hello World")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("sampling/zero_sampling", fn ->
          ReqLLM.generate_text(model,
            context: context,
            temperature: 0.0,
            top_k: 1,
            max_tokens: 10
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # With very low temperature and top_k=1, should be deterministic
      assert text_content =~ "Hello"
    end
  end
end
