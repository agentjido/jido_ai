defmodule Jido.AI.Actions.Instructor.ChatResponseTest do
  use ExUnit.Case
  use Mimic

  alias Jido.AI.Actions.Instructor.ChatResponse
  alias Jido.AI.Actions.Instructor
  alias Jido.AI.Prompt
  alias Jido.AI.Model

  @moduletag :capture_log

  setup :set_mimic_global

  defp mock_base_completion_response(response_text) do
    expect(Instructor, :run, fn params, _context ->
      assert params.model != nil
      assert params.prompt != nil
      assert params.response_model == ChatResponse.Schema
      assert params.temperature != nil
      assert params.max_tokens != nil
      assert params.mode == :tools
      {:ok, %{result: %ChatResponse.Schema{response: response_text}}, %{}}
    end)
  end

  defp mock_base_completion_error(error) do
    expect(Instructor, :run, fn _params, _context ->
      {:error, error, %{}}
    end)
  end

  describe "run/2" do
    test "processes a simple question and returns a structured response" do
      prompt = Prompt.new(:user, "What is pattern matching in Elixir?")

      {:ok, model} =
        Model.from(
          {:anthropic,
           [
             model: "claude-3-sonnet-20240229",
             api_key: "test-api-key"
           ]}
        )

      mock_base_completion_response(
        "Pattern matching in Elixir is a powerful feature that allows you to match values against patterns and extract parts from complex data structures."
      )

      assert {:ok, %{response: response}} =
               ChatResponse.run(
                 %{
                   prompt: prompt,
                   model: model,
                   temperature: 0.7,
                   max_tokens: 1024
                 },
                 %{}
               )

      assert response =~ "Pattern matching in Elixir"
    end

    test "handles prompts with multiple messages" do
      prompt =
        Prompt.new(%{
          messages: [
            %{role: :system, content: "You are an Elixir expert."},
            %{role: :user, content: "Explain the pipe operator."}
          ]
        })

      {:ok, model} =
        Model.from(
          {:anthropic,
           [
             model: "claude-3-sonnet-20240229",
             api_key: "test-api-key"
           ]}
        )

      mock_base_completion_response(
        "The pipe operator (|>) in Elixir is used to chain function calls, passing the result of the left side as the first argument to the function on the right side."
      )

      assert {:ok, %{response: response}} =
               ChatResponse.run(
                 %{
                   prompt: prompt,
                   model: model,
                   temperature: 0.7,
                   max_tokens: 1024
                 },
                 %{}
               )

      assert response =~ "pipe operator"
    end

    test "handles prompts with EEx templating" do
      prompt =
        Prompt.new(%{
          messages: [
            %{role: :user, engine: :eex, content: "Explain <%= @concept %> in Elixir"}
          ],
          params: %{concept: "supervisors"}
        })

      {:ok, model} =
        Model.from(
          {:anthropic,
           [
             model: "claude-3-sonnet-20240229",
             api_key: "test-api-key"
           ]}
        )

      mock_base_completion_response(
        "Supervisors in Elixir are processes that monitor other processes, called child processes, and can restart them when they crash."
      )

      assert {:ok, %{response: response}} =
               ChatResponse.run(
                 %{
                   prompt: prompt,
                   model: model,
                   temperature: 0.7,
                   max_tokens: 1024
                 },
                 %{}
               )

      assert response =~ "Supervisors in Elixir"
    end

    test "handles base completion errors gracefully" do
      prompt = Prompt.new(:user, "What is Elixir?")

      {:ok, model} =
        Model.from(
          {:anthropic,
           [
             model: "claude-3-sonnet-20240229",
             api_key: "test-api-key"
           ]}
        )

      mock_base_completion_error("API error")

      assert {:error, "API error"} =
               ChatResponse.run(
                 %{
                   prompt: prompt,
                   model: model,
                   temperature: 0.7,
                   max_tokens: 1024
                 },
                 %{}
               )
    end

    test "supports different model providers" do
      prompt = Prompt.new(:user, "What is pattern matching?")

      {:ok, openai_model} =
        Model.from(
          {:openai,
           [
             model: "gpt-4",
             api_key: "test-openai-key"
           ]}
        )

      mock_base_completion_response(
        "Pattern matching is a feature in Elixir and other functional programming languages that allows you to match values against patterns and destructure complex data."
      )

      assert {:ok, %{response: response}} =
               ChatResponse.run(
                 %{
                   prompt: prompt,
                   model: openai_model,
                   temperature: 0.7,
                   max_tokens: 1024
                 },
                 %{}
               )

      assert response =~ "Pattern matching"
    end

    test "uses default parameters when not provided" do
      prompt = Prompt.new(:user, "What is Elixir?")

      {:ok, model} =
        Model.from(
          {:anthropic,
           [
             model: "claude-3-sonnet-20240229",
             api_key: "test-api-key"
           ]}
        )

      expect(Instructor, :run, fn params, _context ->
        assert params.temperature == 0.7
        assert params.max_tokens == 1000
        assert params.mode == :tools

        {:ok,
         %{
           result: %ChatResponse.Schema{response: "Elixir is a functional programming language."}
         }, %{}}
      end)

      assert {:ok, %{response: response}} =
               ChatResponse.run(
                 %{
                   prompt: prompt,
                   model: model
                 },
                 %{}
               )

      assert response =~ "Elixir is a functional programming language"
    end
  end
end
