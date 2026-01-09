defmodule Jido.AI.Actions.ReqLlm.ChatCompletionTest do
  use ExUnit.Case, async: false
  import JidoTest.ReqLLMTestHelper
  import Mimic

  alias Jido.AI.Actions.ReqLlm.ChatCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt

  @moduletag :capture_log
  @moduletag :reqllm_integration

  setup :verify_on_exit!

  describe "parameter validation" do
    test "handles missing model parameter" do
      result = ChatCompletion.run(%{prompt: Prompt.new(:user, "Hello")}, %{})
      assert match?({:error, _}, result)
    end

    test "handles missing prompt parameter" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      result = ChatCompletion.run(%{model: model}, %{})
      assert match?({:error, _}, result)
    end

    test "validates model format" do
      result =
        ChatCompletion.run(
          %{
            model: "invalid",
            prompt: Prompt.new(:user, "Hello")
          },
          %{}
        )

      assert {:error, _} = result
    end

    test "accepts valid model and prompt" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")
      params = %{model: model, prompt: prompt}

      result = ChatCompletion.on_before_validate_params(params)
      assert {:ok, validated_params} = result
      assert validated_params.model == model
      assert validated_params.prompt == prompt
    end
  end

  describe "basic chat completion with mocking" do
    test "generates text with valid model and prompt" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "What is 2+2?")

      mock_generate_text(mock_chat_response("The answer is 4."))

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "The answer is 4."
      assert result.tool_results == []
    end

    test "generates text with ReqLLM.Model struct" do
      model = create_test_model(:anthropic, model: "claude-3-5-sonnet")
      prompt = Prompt.new(:user, "Hello")

      mock_generate_text(mock_chat_response("Hello! How can I help?"))

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "Hello! How can I help?"
    end

    test "generates text with Jido.AI.Model struct" do
      model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(mock_chat_response("Test response"))

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "Test response"
    end

    test "passes correct model spec to ReqLLM" do
      model = {:anthropic, [model: "claude-3-5-haiku"]}
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn model_spec, _messages, _opts ->
        assert model_spec == "anthropic:claude-3-5-haiku"
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
    end

    test "converts prompt to messages correctly" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Hello world")

      expect_generate_text(fn _model, context, _opts ->
        # Context is a struct, we need to get messages from it
        # Based on #Context<1 msgs...>, it likely has a messages field
        messages = context.messages
        assert length(messages) == 1
        [message] = messages
        assert message.role == :user
        # assert message.content == "Hello world"
        # Content is converted to a list of ContentPart structs
        assert is_list(message.content)
        [content_part] = message.content
        assert content_part.type == :text
        assert content_part.text == "Hello world"

        {:ok, mock_chat_response("Hi!")}
      end)

      {:ok, _result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
    end
  end

  describe "parameters passing to ReqLLM" do
    test "passes temperature parameter" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :temperature) == 0.2
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            temperature: 0.2
          },
          %{}
        )
    end

    test "passes max_tokens parameter" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :max_tokens) == 2048
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            max_tokens: 2048
          },
          %{}
        )
    end

    test "passes top_p parameter" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :top_p) == 0.9
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            top_p: 0.9
          },
          %{}
        )
    end

    test "passes stop sequences" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :stop) == ["END", "STOP"]
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            stop: ["END", "STOP"]
          },
          %{}
        )
    end

    test "passes frequency_penalty and presence_penalty" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :frequency_penalty) == 0.5
        assert Keyword.get(opts, :presence_penalty) == 0.3
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            frequency_penalty: 0.5,
            presence_penalty: 0.3
          },
          %{}
        )
    end

    test "uses default values when parameters not provided" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :temperature) == 0.7
        assert Keyword.get(opts, :max_tokens) == 1000
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
    end
  end

  describe "tool calling" do
    test "returns tool calls in response" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "What's the weather?")

      response =
        mock_chat_response("I'll check the weather",
          tool_calls: [
            %{name: "get_weather", arguments: %{"location" => "Tokyo"}}
          ]
        )

      mock_generate_text(response)

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "I'll check the weather"
      assert length(result.tool_results) == 1
      [tool] = result.tool_results
      assert tool.name == "get_weather"
      assert tool.arguments == %{"location" => "Tokyo"}
    end

    test "handles multiple tool calls" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Search and calculate")

      response =
        mock_chat_response("Running tools",
          tool_calls: [
            %{name: "search", arguments: %{"query" => "test"}},
            %{name: "calculate", arguments: %{"expression" => "2+2"}}
          ]
        )

      mock_generate_text(response)

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert length(result.tool_results) == 2
      names = Enum.map(result.tool_results, & &1.name)
      assert "search" in names
      assert "calculate" in names
    end

    test "handles response with no tool calls" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Just chat")

      mock_generate_text(mock_chat_response("Just a chat response"))

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.tool_results == []
    end
  end

  describe "streaming" do
    test "returns stream when stream: true" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Tell me a story")
      chunks = mock_stream_chunks(["Once", " upon", " a", " time"])

      mock_stream_text(chunks)

      {:ok, stream} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            stream: true
          },
          %{}
        )

      assert is_struct(stream, Stream) or is_function(stream)
    end

    test "stream contains expected chunks" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Count to 3")
      chunks = mock_stream_chunks(["1", " 2", " 3"])

      mock_stream_text(chunks)

      {:ok, stream} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            stream: true
          },
          %{}
        )

      collected = Enum.to_list(stream)
      assert length(collected) == 3
    end

    test "passes stream option to ReqLLM" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      stub(ReqLLM, :stream_text, fn _model, _messages, opts ->
        assert Keyword.get(opts, :stream) == true
        {:ok, Stream.map([], & &1)}
      end)

      {:ok, _stream} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            stream: true
          },
          %{}
        )
    end

    test "handles streaming errors" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      mock_stream_text_error(%{reason: :connection_error})

      {:error, error} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            stream: true
          },
          %{}
        )

      assert error.reason == :connection_error
    end
  end

  describe "error handling" do
    test "returns error from ReqLLM" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      stub(ReqLLM, :generate_text, fn _model, _messages, _opts ->
        {:error, %{reason: :rate_limit, message: "Too many requests"}}
      end)

      {:error, error} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert error.reason == :rate_limit
    end

    test "returns error for invalid model specification" do
      prompt = Prompt.new(:user, "Test")

      result =
        ChatCompletion.run(
          %{
            model: "not-a-valid-model",
            prompt: prompt
          },
          %{}
        )

      assert match?({:error, _}, result)
    end

    test "handles missing provider" do
      result =
        ChatCompletion.run(
          %{
            model: %Model{provider: :nonexistent, model: "test"},
            prompt: Prompt.new(:user, "Hello")
          },
          %{}
        )

      assert {:error, _} = result
    end
  end

  describe "response formatting" do
    test "formats response with content only" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(%{content: "Simple response"})

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "Simple response"
      assert result.tool_results == []
    end

    test "handles response with string keys" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(%{"content" => "String key response"})

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "String key response"
    end

    test "handles tool calls with string keys" do
      model = {:openai, [model: "gpt-4"]}
      prompt = Prompt.new(:user, "Test")

      response = %{
        content: "Using tool",
        tool_calls: [
          %{"name" => "test_tool", "arguments" => %{"arg" => "value"}}
        ]
      }

      mock_generate_text(response)

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert length(result.tool_results) == 1
      [tool] = result.tool_results
      assert tool.name == "test_tool"
    end
  end

  describe "multimodal support" do
    test "handles base64 image content" do
      model = {:openai, [model: "gpt-4-vision-preview"]}

      # Construct multimodal message
      image_data =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

      messages = [
        %{
          role: :user,
          content: [
            %{type: :text, text: "Describe this image"},
            %{type: :image_url, image_url: image_data}
          ]
        }
      ]

      prompt = Prompt.new(%{messages: messages})

      expect_generate_text(fn _model, context, _opts ->
        messages = context.messages
        [message] = messages
        # ReqLLM.Context.user returns struct, we need to inspect its content
        assert is_list(message.content)
        assert length(message.content) == 2

        [text_part, image_part] = message.content

        # Verify text part
        assert match?(%ReqLLM.Message.ContentPart{type: :text}, text_part)

        # Verify image part (base64 converted to binary)
        assert match?(%ReqLLM.Message.ContentPart{type: :image}, image_part)

        assert is_binary(image_part.data)
        assert image_part.media_type == "image/png"

        {:ok, mock_chat_response("It's a red dot")}
      end)

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
      assert result.content == "It's a red dot"
    end

    test "handles network image url" do
      model = {:openai, [model: "gpt-4-vision-preview"]}

      image_url = "https://picsum.photos/id/237/200/300"

      messages = [
        %{
          role: :user,
          content: [
            %{type: :text, text: "Describe this image"},
            %{type: :image_url, image_url: image_url}
          ]
        }
      ]

      prompt = Prompt.new(%{messages: messages})

      expect_generate_text(fn _model, context, _opts ->
        messages = context.messages
        [message] = messages
        [_, image_part] = message.content

        # Verify image url part
        assert match?(%ReqLLM.Message.ContentPart{type: :image_url}, image_part)
        # IO.inspect(image_part, label: "IMAGE_URL_PART_DEBUG", structs: false)
        assert image_part.url == image_url

        {:ok, mock_chat_response("It's an example image")}
      end)

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
      assert result.content == "It's an example image"
    end

    test "handles invalid base64 gracefully" do
      model = {:openai, [model: "gpt-4-vision-preview"]}

      # Invalid data url
      invalid_data = "data:image/png;base64,invalid-base64"

      messages = [
        %{
          role: :user,
          content: [
            %{type: :image_url, image_url: invalid_data}
          ]
        }
      ]

      prompt = Prompt.new(%{messages: messages})

      expect_generate_text(fn _model, context, _opts ->
        messages = context.messages
        [message] = messages
        [part] = message.content

        # Should return as map/original structure if parsing fails
        assert is_map(part)
        assert part["type"] == "image_url"
        assert part["image_url"]["url"] == invalid_data

        {:ok, mock_chat_response("Error processing image")}
      end)

      {:ok, _result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
    end
  end

  describe "different providers" do
    test "works with OpenAI" do
      model = {:openai, [model: "gpt-4-turbo"]}
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(mock_chat_response("OpenAI response"))

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
      assert result.content == "OpenAI response"
    end

    test "works with Anthropic" do
      model = {:anthropic, [model: "claude-3-5-sonnet"]}
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(mock_chat_response("Anthropic response"))

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
      assert result.content == "Anthropic response"
    end

    test "works with Google" do
      model = {:google, [model: "gemini-pro"]}
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(mock_chat_response("Google response"))

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
      assert result.content == "Google response"
    end

    test "works with OpenRouter" do
      model = {:openrouter, [model: "anthropic/claude-3-opus"]}
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(mock_chat_response("OpenRouter response"))

      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
      assert result.content == "OpenRouter response"
    end
  end
end
