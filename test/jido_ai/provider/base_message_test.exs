defmodule Jido.AI.Provider.BaseMessageTest do
  use Jido.AI.TestSupport.HTTPCase

  import Jido.AI.TestSupport.Assertions

  alias Jido.AI.Provider.Base
  alias Jido.AI.Provider.Util.Options
  alias Jido.AI.Test.Fixtures.ModelFixtures
  alias Jido.AI.{ContentPart, Message}

  describe "encode_messages/1" do
    test "encodes string prompt to user message" do
      messages = Base.encode_messages("Hello world")

      assert [%{role: "user", content: "Hello world"}] = messages
    end

    test "encodes message list to OpenAI format" do
      input_messages = [
        Message.new(:system, "You are helpful"),
        Message.new(:user, "Hello"),
        Message.new(:assistant, "Hi there")
      ]

      messages = Base.encode_messages(input_messages)

      assert [
               %{"role" => "system", "content" => "You are helpful"},
               %{"role" => "user", "content" => "Hello"},
               %{"role" => "assistant", "content" => "Hi there"}
             ] = messages
    end
  end

  describe "encode_message/1" do
    test "encodes basic message with string content" do
      message = Message.new(:user, "Hello world")
      encoded = Base.encode_message(message)

      assert %{"role" => "user", "content" => "Hello world"} = encoded
    end

    test "encodes message with text content parts" do
      content_parts = [ContentPart.text("Hello world")]
      message = Message.new(:user, content_parts)
      encoded = Base.encode_message(message)

      assert %{
               "role" => "user",
               "content" => [%{type: "text", text: "Hello world"}]
             } = encoded
    end

    test "encodes message with mixed multi-modal content" do
      content_parts = [
        ContentPart.text("Describe this image:"),
        ContentPart.image_url("https://example.com/image.png"),
        ContentPart.image_data(<<137, 80, 78, 71>>, "image/png"),
        ContentPart.file(<<37, 80, 68, 70>>, "application/pdf", "doc.pdf")
      ]

      message = Message.new(:user, content_parts)
      encoded = Base.encode_message(message)

      expected_base64_image = Elixir.Base.encode64(<<137, 80, 78, 71>>)
      expected_image_data_url = "data:image/png;base64,#{expected_base64_image}"
      expected_base64_file = Elixir.Base.encode64(<<37, 80, 68, 70>>)

      assert %{
               "role" => "user",
               "content" => [
                 %{type: "text", text: "Describe this image:"},
                 %{type: "image_url", image_url: %{url: "https://example.com/image.png"}},
                 %{type: "image_url", image_url: %{url: ^expected_image_data_url}},
                 %{
                   type: "file",
                   file: %{
                     data: ^expected_base64_file,
                     media_type: "application/pdf",
                     filename: "doc.pdf"
                   }
                 }
               ]
             } = encoded
    end

    test "encodes message with optional fields" do
      message =
        Message.new(:assistant, "Hi",
          name: "assistant",
          tool_call_id: "call_123",
          tool_calls: [%{id: "call_123", function: %{name: "test"}}]
        )

      encoded = Base.encode_message(message)

      assert %{
               "role" => "assistant",
               "content" => "Hi",
               "name" => "assistant",
               "tool_call_id" => "call_123",
               "tool_calls" => [%{id: "call_123", function: %{name: "test"}}]
             } = encoded
    end

    test "omits nil optional fields" do
      message = Message.new(:user, "Hello")
      encoded = Base.encode_message(message)

      assert %{"role" => "user", "content" => "Hello"} = encoded
      refute Map.has_key?(encoded, "name")
      refute Map.has_key?(encoded, "tool_call_id")
      refute Map.has_key?(encoded, "tool_calls")
    end
  end

  describe "build_chat_completion_body/4 with messages" do
    test "builds request body with string prompt" do
      model = ModelFixtures.gpt4()
      opts = [api_key: "test-key"]

      body = Base.build_chat_completion_body(model, "Hello", nil, opts)

      assert %{
               model: "gpt-4",
               messages: [%{role: "user", content: "Hello"}]
             } = body
    end

    test "builds request body with message list" do
      model = ModelFixtures.gpt4()
      opts = [api_key: "test-key"]

      messages = [
        Message.new(:system, "You are helpful"),
        Message.new(:user, "Hello")
      ]

      body = Base.build_chat_completion_body(model, messages, nil, opts)

      assert %{
               model: "gpt-4",
               messages: [
                 %{"role" => "system", "content" => "You are helpful"},
                 %{"role" => "user", "content" => "Hello"}
               ]
             } = body
    end

    test "builds request body with multi-modal content" do
      model = ModelFixtures.gpt4()
      opts = [api_key: "test-key"]

      messages = [
        Message.user_with_image("Describe this image:", "https://example.com/image.png")
      ]

      body = Base.build_chat_completion_body(model, messages, nil, opts)

      assert %{
               model: "gpt-4",
               messages: [
                 %{
                   "role" => "user",
                   "content" => [
                     %{type: "text", text: "Describe this image:"},
                     %{type: "image_url", image_url: %{url: "https://example.com/image.png"}}
                   ]
                 }
               ]
             } = body
    end

    test "builds request body with complex multi-modal content" do
      model = ModelFixtures.gpt4()
      opts = [api_key: "test-key"]

      content_parts = [
        ContentPart.text("Analyze this image and document:"),
        ContentPart.image_data(<<137, 80, 78, 71>>, "image/png"),
        ContentPart.file(<<37, 80, 68, 70>>, "application/pdf", "report.pdf")
      ]

      messages = [Message.user_multimodal(content_parts)]

      body = Base.build_chat_completion_body(model, messages, nil, opts)

      expected_base64_image = Elixir.Base.encode64(<<137, 80, 78, 71>>)
      expected_image_data_url = "data:image/png;base64,#{expected_base64_image}"
      expected_base64_file = Elixir.Base.encode64(<<37, 80, 68, 70>>)

      assert %{
               model: "gpt-4",
               messages: [
                 %{
                   "role" => "user",
                   "content" => [
                     %{type: "text", text: "Analyze this image and document:"},
                     %{type: "image_url", image_url: %{url: ^expected_image_data_url}},
                     %{
                       type: "file",
                       file: %{
                         data: ^expected_base64_file,
                         media_type: "application/pdf",
                         filename: "report.pdf"
                       }
                     }
                   ]
                 }
               ]
             } = body
    end
  end

  describe "backward compatibility" do
    test "default_generate_text works with string prompts", %{test_name: test_name} do
      model = ModelFixtures.gpt4()

      stub_success(
        %{
          choices: [%{message: %{content: "Hello there!"}}]
        },
        test_name
      )

      result =
        Base.default_generate_text(Jido.AI.Provider.BaseMessageTest.FakeProvider, model, "Hello", api_key: "test-key")

      text = assert_ok(result)

      assert text == "Hello there!"
    end

    test "default_generate_text works with message lists", %{test_name: test_name} do
      model = ModelFixtures.gpt4()
      messages = [Message.new(:user, "Hello")]

      stub_success(
        %{
          choices: [%{message: %{content: "Hi there!"}}]
        },
        test_name
      )

      result =
        Base.default_generate_text(Jido.AI.Provider.BaseMessageTest.FakeProvider, model, messages, api_key: "test-key")

      text = assert_ok(result)

      assert text == "Hi there!"
    end

    test "default_generate_text works with multi-modal message lists", %{test_name: test_name} do
      model = ModelFixtures.gpt4()
      messages = [Message.user_with_image("Describe this image:", "https://example.com/image.png")]

      stub_success(
        %{
          choices: [%{message: %{content: "I can see an image of..."}}]
        },
        test_name
      )

      result =
        Base.default_generate_text(Jido.AI.Provider.BaseMessageTest.FakeProvider, model, messages, api_key: "test-key")

      text = assert_ok(result)

      assert text == "I can see an image of..."
    end
  end

  # Fake provider module for testing
  defmodule FakeProvider do
    def api_url, do: "https://api.fake.com/v1"
    def chat_completion_opts, do: Options.default()
    def stream_event_type, do: :openai
  end
end
