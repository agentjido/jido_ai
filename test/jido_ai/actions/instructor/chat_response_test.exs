defmodule Jido.AI.Actions.Instructor.ChatResponseTest do
  use ExUnit.Case
  use Mimic

  alias Jido.AI.Actions.Instructor.{ChatResponse, ChatCompletion}
  alias Jido.AI.Prompt
  alias Jido.AI.Model
  alias Instructor.Adapters.Anthropic
  alias Jido.Workflow

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    Mimic.copy(Anthropic)
    Mimic.copy(Instructor)
    Mimic.copy(Workflow)
    :ok
  end

  # Helper functions
  defp create_prompt(content, engine \\ :none, params \\ %{}) do
    %Prompt{
      metadata: %{},
      params: params,
      messages: [
        %{role: :user, engine: engine, content: content}
      ],
      history: [],
      version: 1,
      id: "test-prompt-id"
    }
  end

  defp create_model do
    {:ok, model} = Model.from({:anthropic, [
      model_id: "claude-3-sonnet-20240229",
      api_key: "test-api-key",
      base_url: "https://api.anthropic.com/v1",
      description: "Anthropic Claude model",
      temperature: 0.7,
      max_tokens: 1024,
      max_retries: 0
    ]})
    model
  end

  defp mock_workflow_response do
    expect(Instructor, :chat_completion, fn opts, config ->
      assert opts[:model] == "claude-3-sonnet-20240229"
      assert length(opts[:messages]) > 0
      assert opts[:temperature] == 0.7
      assert opts[:max_tokens] == 1024
      assert config[:adapter] == Instructor.Adapters.Anthropic
      assert config[:api_key] == "test-api-key"

      {:ok, %ChatResponse.Schema{response: "Test response"}}
    end)

    expect(Workflow, :run, fn ChatCompletion, params ->
      assert params[:model] != nil
      assert params[:temperature] != nil
      assert params[:max_tokens] != nil

      # Forward the call to ChatCompletion.run
      ChatCompletion.run(params, %{})
    end)
  end

  describe "run/2" do
    test "processes a simple question and returns a structured response" do
      prompt = create_prompt("What is pattern matching in Elixir?")
      model = create_model()
      mock_workflow_response()

      assert {:ok, %{response: "Test response"}} =
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

    test "handles prompts with multiple messages" do
      prompt = %Prompt{
        metadata: %{},
        params: %{},
        messages: [
          %{role: :system, engine: :none, content: "You are an Elixir expert."},
          %{role: :user, engine: :none, content: "Explain the pipe operator."}
        ],
        history: [],
        version: 1,
        id: "test-prompt-id"
      }

      model = create_model()
      mock_workflow_response()

      assert {:ok, %{response: "Test response"}} =
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

    test "handles prompts with EEx templating" do
      prompt = create_prompt("Explain <%= @concept %> in Elixir", :eex, %{concept: "supervisors"})
      model = create_model()
      mock_workflow_response()

      assert {:ok, %{response: "Test response"}} =
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

    test "handles prompts with Liquid templating" do
      prompt = create_prompt("What is {{ concept }}?", :liquid, %{concept: "OTP"})
      model = create_model()
      mock_workflow_response()

      assert {:ok, %{response: "Test response"}} =
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

    test "handles workflow errors gracefully" do
      prompt = create_prompt("What is Elixir?")
      model = create_model()

      expect(Workflow, :run, fn ChatCompletion, params ->
        assert params[:model] != nil
        assert params[:temperature] != nil
        assert params[:max_tokens] != nil
        {:error, "API error", %{}}
      end)

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

    test "handles unexpected response shapes" do
      prompt = create_prompt("What is Elixir?")
      model = create_model()

      expect(Workflow, :run, fn ChatCompletion, params ->
        assert params[:model] != nil
        assert params[:temperature] != nil
        assert params[:max_tokens] != nil
        {:ok, %{result: %{result: nil}}, %{}}
      end)

      assert {:error, "Unexpected response shape"} =
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

    test "handles empty references" do
      prompt = create_prompt("What is pattern matching?")
      model = create_model()
      mock_workflow_response()

      assert {:ok, %{response: "Test response"}} =
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
  end
end
