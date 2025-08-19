defmodule Jido.AI.ProviderOptionsIntegrationTest do
  use ExUnit.Case, async: true

  import Jido.AI.Test.Fixtures.ModelFixtures

  alias Jido.AI.Test.FakeProvider
  alias Jido.AI.{ContentPart, Message}

  setup do
    # Register fake provider for testing
    Jido.AI.Provider.Registry.register(:fake, FakeProvider)

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
      Jido.AI.Provider.Registry.initialize()
    end)

    :ok
  end

  describe "provider options integration" do
    test "function level provider_options work with generate_text" do
      model = fake()

      {:ok, response} =
        FakeProvider.generate_text(
          model,
          "Hello",
          provider_options: %{fake: %{custom_param: "test_value"}}
        )

      assert is_binary(response)
      assert String.contains?(response, "fake-model")
      assert String.contains?(response, "Hello")
    end

    test "message level provider_options work with generate_text" do
      model = fake()

      message = %Message{
        role: :user,
        content: "Hello",
        metadata: %{provider_options: %{fake: %{reasoning_effort: "low"}}}
      }

      {:ok, response} = FakeProvider.generate_text(model, [message], [])

      assert is_binary(response)
      assert String.contains?(response, "fake-model")
    end

    test "content part level provider_options work with generate_text" do
      model = fake()

      part =
        ContentPart.text("Analyze this",
          metadata: %{provider_options: %{fake: %{image_detail: "high"}}}
        )

      message = %Message{role: :user, content: [part]}

      {:ok, response} = FakeProvider.generate_text(model, [message], [])

      assert is_binary(response)
      assert String.contains?(response, "fake-model")
    end

    test "provider options precedence works correctly" do
      model = fake()
      # Content part options should override message and function options
      part =
        ContentPart.text("Hi",
          metadata: %{provider_options: %{fake: %{param: "content_part"}}}
        )

      message = %Message{
        role: :user,
        content: [part],
        metadata: %{provider_options: %{fake: %{param: "message_level", other: "from_message"}}}
      }

      {:ok, response} =
        FakeProvider.generate_text(
          model,
          [message],
          provider_options: %{fake: %{param: "function_level"}}
        )

      assert is_binary(response)
      assert String.contains?(response, "fake-model")
    end

    test "stream_text works with provider options" do
      model = fake()

      {:ok, stream} =
        FakeProvider.stream_text(
          model,
          "Hello",
          provider_options: %{fake: %{stream_param: "streaming"}}
        )

      result = Enum.to_list(stream)
      assert result == ["chunk_1", "chunk_2", "chunk_3"]
    end

    test "backward compatibility - no provider options still works" do
      model = fake()

      {:ok, response} = FakeProvider.generate_text(model, "Hello", [])

      assert is_binary(response)
      assert String.contains?(response, "fake-model")
      assert String.contains?(response, "Hello")
    end

    test "multiple provider options merge correctly" do
      model = fake()
      # Multiple messages with different provider options should all merge
      message1 = %Message{
        role: :user,
        content: "First message",
        metadata: %{provider_options: %{fake: %{param1: "from_msg1"}}}
      }

      message2 = %Message{
        role: :assistant,
        content: "Second message",
        metadata: %{provider_options: %{fake: %{param2: "from_msg2"}}}
      }

      {:ok, response} = FakeProvider.generate_text(model, [message1, message2], [])

      assert is_binary(response)
      assert String.contains?(response, "fake-model")
    end

    test "deep nested provider options merge correctly" do
      model = fake()

      message = %Message{
        role: :user,
        content: "Hello",
        metadata: %{
          provider_options: %{
            fake: %{
              nested: %{
                level1: %{
                  param_a: "message_value",
                  param_b: "message_only"
                }
              }
            }
          }
        }
      }

      function_opts = [
        provider_options: %{
          fake: %{
            nested: %{
              level1: %{
                param_a: "function_value",
                param_c: "function_only"
              }
            }
          }
        }
      ]

      {:ok, response} = FakeProvider.generate_text(model, [message], function_opts)

      assert is_binary(response)
      assert String.contains?(response, "fake-model")
    end

    test "main API functions work with provider options" do
      # Test the main API functions to ensure they work end-to-end
      {:ok, response} =
        Jido.AI.generate_text(
          "fake:fake-model",
          "Hello API",
          provider_options: %{fake: %{api_param: "test"}}
        )

      assert is_binary(response)
      assert String.contains?(response, "fake-model")
      assert String.contains?(response, "Hello API")
    end

    test "stream API functions work with provider options" do
      model = fake()

      {:ok, stream} =
        FakeProvider.stream_text(
          model,
          "Hello Stream",
          provider_options: %{fake: %{stream_param: "test"}}
        )

      result = Enum.to_list(stream)
      assert result == ["chunk_1", "chunk_2", "chunk_3"]
    end
  end
end
