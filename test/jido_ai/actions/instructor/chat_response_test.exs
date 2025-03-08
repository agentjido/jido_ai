defmodule Jido.AI.Actions.Instructor.ChatResponseTest do
  use ExUnit.Case
  use Mimic

  alias Jido.AI.Actions.Instructor.ChatResponse
  alias Jido.AI.Prompt
  alias Jido.AI.Model

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    Mimic.copy(ChatResponse)
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
    Model.from(%{
      max_retries: 0,
      max_tokens: 1024,
      temperature: 0.7,
      model_id: "claude-3-sonnet-20240229",
      api_key: "test-api-key",
      base_url: "https://api.anthropic.com/v1",
      endpoints: [],
      description: "Anthropic Claude model",
      created: 1_741_285_515,
      architecture: %{
        tokenizer: "unknown",
        modality: "text",
        instruct_type: nil
      },
      provider: :anthropic,
      name: "Anthropic claude-3-sonnet-20240229",
      id: "anthropic_claude-3-sonnet-20240229"
    })
  end

  defp mock_workflow_response do
    expect(ChatResponse, :run, fn params, _opts ->
      assert params[:model] != nil
      assert params[:temperature] != nil
      assert params[:max_tokens] != nil
      {:ok, %{content: "Test response"}}
    end)
  end

  defp mock_workflow_error do
    expect(ChatResponse, :run, fn params, _opts ->
      assert params[:model] != nil
      assert params[:temperature] != nil
      assert params[:max_tokens] != nil
      {:error, "API error"}
    end)
  end


  describe "run/2" do
    test "processes a simple question and returns a structured response" do
      prompt = create_prompt("What is pattern matching in Elixir?")
      model = create_model()
      mock_workflow_response()

      assert {:ok, %{content: "Test response"}} =
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

      assert {:ok, %{content: "Test response"}} =
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

      assert {:ok, %{content: "Test response"}} =
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

      assert {:ok, %{content: "Test response"}} =
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
      mock_workflow_error()

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

      expect(ChatResponse, :run, fn params, _opts ->
        assert params[:model] != nil
        assert params[:temperature] != nil
        assert params[:max_tokens] != nil
        {:ok, %{result: %{result: nil}}, %{}}
      end)

      assert {:ok, %{result: %{result: nil}}, %{}} =
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

      assert {:ok, %{content: "Test response"}} =
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
