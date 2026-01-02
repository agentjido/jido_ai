defmodule JidoAi.Actions.AnthropicTest do
  use ExUnit.Case, async: true
  use Mimic

  alias JidoAi.Actions.Anthropic.ChatCompletion
  alias Jido.Workflow

  # Define a sample response model for testing
  defmodule SampleResponseModel do
    use Ecto.Schema
    use Instructor

    @primary_key false
    embedded_schema do
      field(:content, :string)
    end
  end

  setup do
    # Set a fake Anthropic API key for testing
    Application.put_env(:instructor, :anthropic, api_key: "fake_api_key_for_testing")

    # Stub Instructor
    stub(Instructor)

    on_exit(fn ->
      # Reset the configuration after the test
      Application.delete_env(:instructor, :anthropic)
    end)

    :ok
  end

  setup :verify_on_exit!
  setup :set_mimic_global

  describe "ChatCompletion" do
    test "successfully handles valid parameters" do
      expect(Instructor, :chat_completion, fn _opts ->
        {:ok, %SampleResponseModel{content: "Test response"}}
      end)

      params = %{
        model: "claude-3-5-haiku-latest",
        messages: [%{role: "user", content: "Hello"}],
        response_model: SampleResponseModel,
        temperature: 0.7,
        max_tokens: 1000,
        max_retries: 0,
        timeout: 30_000
      }

      assert {:ok, %{result: %SampleResponseModel{content: "Test response"}}} =
               Workflow.run(ChatCompletion, params)
    end

    test "handles different models" do
      expect(Instructor, :chat_completion, fn opts ->
        assert opts[:model] == "claude-3-opus-20240229"
        {:ok, %SampleResponseModel{content: "Opus response"}}
      end)

      params = %{
        model: "claude-3-opus-20240229",
        messages: [%{role: "user", content: "Hello"}],
        response_model: SampleResponseModel,
        temperature: 0.7,
        max_tokens: 1000
      }

      assert {:ok, %{result: %SampleResponseModel{content: "Opus response"}}} =
               Workflow.run(ChatCompletion, params)
    end

    test "handles custom temperature" do
      expect(Instructor, :chat_completion, fn opts ->
        assert_in_delta opts[:temperature], 0.9, 0.001
        {:ok, %SampleResponseModel{content: "Custom temperature response"}}
      end)

      params = %{
        model: "claude-3-5-haiku-latest",
        messages: [%{role: "user", content: "Hello"}],
        response_model: SampleResponseModel,
        temperature: 0.9,
        max_tokens: 1000
      }

      assert {:ok, %{result: %SampleResponseModel{content: "Custom temperature response"}}} =
               Workflow.run(ChatCompletion, params)
    end

    test "handles custom max_tokens" do
      expect(Instructor, :chat_completion, fn opts ->
        assert opts[:max_tokens] == 500
        {:ok, %SampleResponseModel{content: "Custom max_tokens response"}}
      end)

      params = %{
        model: "claude-3-5-haiku-latest",
        messages: [%{role: "user", content: "Hello"}],
        response_model: SampleResponseModel,
        temperature: 0.7,
        max_tokens: 500
      }

      assert {:ok, %{result: %SampleResponseModel{content: "Custom max_tokens response"}}} =
               Workflow.run(ChatCompletion, params)
    end

    test "handles custom timeout" do
      expect(Instructor, :chat_completion, fn opts ->
        assert opts[:timeout] == 60_000
        {:ok, %SampleResponseModel{content: "Custom timeout response"}}
      end)

      params = %{
        model: "claude-3-5-haiku-latest",
        messages: [%{role: "user", content: "Hello"}],
        response_model: SampleResponseModel,
        temperature: 0.7,
        max_tokens: 1000,
        timeout: 60_000
      }

      assert {:ok, %{result: %SampleResponseModel{content: "Custom timeout response"}}} =
               Workflow.run(ChatCompletion, params)
    end

    test "handles error response" do
      expect(Instructor, :chat_completion, fn opts ->
        assert opts[:model] == "claude-3-5-haiku-latest"
        assert length(opts[:messages]) == 1
        assert opts[:temperature] == 0.7
        assert opts[:max_tokens] == 1000
        assert opts[:max_retries] == 0
        assert opts[:timeout] == 30_000
        {:error, "API error"}
      end)

      params = %{
        model: "claude-3-5-haiku-latest",
        messages: [%{role: "user", content: "Hello"}],
        response_model: SampleResponseModel,
        temperature: 0.7,
        max_tokens: 1000,
        max_retries: 0,
        timeout: 30_000
      }

      assert {:error, %Jido.Error{type: :execution_error}} = Workflow.run(ChatCompletion, params)
    end
  end
end
