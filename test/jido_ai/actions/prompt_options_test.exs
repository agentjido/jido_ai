defmodule JidoTest.AI.Actions.PromptOptionsTest do
  use ExUnit.Case, async: false
  use Mimic
  @moduletag :capture_log

  alias Jido.AI.Prompt
  alias Jido.AI.Model
  alias Jido.AI.Actions.Langchain
  alias Jido.AI.Actions.Instructor
  alias Jido.AI.Actions.OpenaiEx
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Chains.LLMChain

  # Add correct module imports for mocking
  setup do
    Mimic.verify!(LangChain.ChatModels.ChatOpenAI)
    Mimic.verify!(LangChain.Chains.LLMChain)
    Mimic.verify!(Instructor)
    Mimic.verify!(OpenaiEx.Chat.Completions)
    :ok
  end

  setup :set_mimic_global

  describe "prompt options in Langchain action" do
    test "uses options from prompt as defaults" do
      # Create a prompt with options
      prompt =
        Prompt.new(:user, "Test message")
        |> Prompt.with_temperature(0.5)
        |> Prompt.with_max_tokens(800)
        |> Prompt.with_top_p(0.9)

      # Mock the model validation
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}

      # Mock LangChain modules
      expect(ChatOpenAI, :new!, fn opts ->
        # Verify the options were passed from the prompt
        assert opts[:temperature] == 0.5
        assert opts[:max_tokens] == 800
        assert opts[:top_p] == 0.9
        %{llm: "mocked_llm"}
      end)

      # Mock other dependencies
      expect(LLMChain, :new!, fn _opts -> %{} end)
      expect(LLMChain, :add_messages, fn chain, _messages -> chain end)

      expect(LLMChain, :run, fn _chain ->
        {:ok,
         %LLMChain{
           last_message: %LangChain.Message{
             content: "Test response",
             role: :assistant
           }
         }}
      end)

      # Run the action
      Langchain.run(%{model: model, prompt: prompt}, %{})
    end

    test "explicit params override prompt options" do
      # Create a prompt with options
      prompt =
        Prompt.new(:user, "Test message")
        |> Prompt.with_temperature(0.5)
        |> Prompt.with_max_tokens(800)

      # Mock the model validation
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}

      # Mock LangChain modules
      expect(ChatOpenAI, :new!, fn opts ->
        # Verify that explicit param overrides prompt option
        # From explicit param
        assert opts[:temperature] == 0.8
        # From prompt
        assert opts[:max_tokens] == 800
        %{llm: "mocked_llm"}
      end)

      # Mock other dependencies
      expect(LLMChain, :new!, fn _opts -> %{} end)
      expect(LLMChain, :add_messages, fn chain, _messages -> chain end)

      expect(LLMChain, :run, fn _chain ->
        {:ok,
         %LLMChain{
           last_message: %LangChain.Message{
             content: "Test response",
             role: :assistant
           }
         }}
      end)

      # Run the action with an explicit parameter that overrides the prompt option
      Langchain.run(%{model: model, prompt: prompt, temperature: 0.8}, %{})
    end
  end

  # These tests would need more complex mocking and knowledge of the internal structure
  # We'll comment them out for now to focus on the Langchain test

  # Uncomment and fix these tests based on actual module structure
  #
  # describe "prompt options in Instructor action" do
  #   test "uses options from prompt as defaults" do
  #     # Create a prompt with options
  #     prompt = Prompt.new(:user, "Test message")
  #              |> Prompt.with_temperature(0.4)
  #              |> Prompt.with_max_tokens(1200)
  #
  #     # Mock the model and response model
  #     model = %Model{provider: :anthropic, model: "claude-3-haiku-20240307", api_key: "test-key"}
  #     response_model = %{}
  #
  #     # Mock Instructor module - update according to actual module structure
  #     # expect(Instructor, :chat_completion, fn opts, _config ->
  #     #   # Verify the options were passed from the prompt
  #     #   assert opts[:temperature] == 0.4
  #     #   assert opts[:max_tokens] == 1200
  #     #   {:ok, "Test response"}
  #     # end)
  #
  #     # Run the action
  #     Instructor.run(%{
  #       model: model,
  #       prompt: prompt,
  #       response_model: response_model
  #     }, %{})
  #   end
  # end
  #
  # describe "prompt options in OpenaiEx action" do
  #   test "uses options from prompt as defaults" do
  #     # Create a prompt with options
  #     prompt = Prompt.new(:user, "Test message")
  #              |> Prompt.with_temperature(0.3)
  #              |> Prompt.with_max_tokens(500)
  #              |> Prompt.with_top_p(0.8)
  #
  #     # Mock the model
  #     model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
  #
  #     # Mock OpenaiEx modules - update according to actual module structure
  #     # expect(OpenaiEx.Chat.Completions, :create, fn _client, chat_req ->
  #     #   # Verify that prompt options were applied
  #     #   assert chat_req.temperature == 0.3
  #     #   assert chat_req.max_tokens == 500
  #     #   assert chat_req.top_p == 0.8
  #     #   {:ok, %{choices: [%{message: %{content: "Test response"}}]}}
  #     # end)
  #
  #     # Run the action
  #     OpenaiEx.run(%{model: model, prompt: prompt}, %{})
  #   end
  # end
end
