defmodule Jido.AI.Provider.BaseTest do
  use ExUnit.Case, async: true
  use Jido.AI.TestMacros

  import Jido.AI.Test.Fixtures.ModelFixtures

  alias Jido.AI.Error.{API, Invalid}
  alias Jido.AI.Provider
  alias Jido.AI.Provider.Base
  alias Jido.AI.Provider.Util.Options
  alias Jido.AI.Test.FakeProvider
  alias Jido.AI.{ContentPart, Message}

  # Simple test provider for testing Base functionality
  defmodule TestProvider do
    @behaviour Jido.AI.Provider.Behaviour

    @impl true
    def provider_info do
      %Provider{
        id: :test_provider,
        name: "Test Provider",
        doc: "Provider for testing Base module",
        env: [:test_api_key],
        models: %{}
      }
    end

    @impl true
    def api_url, do: "https://test.example.com/v1"

    @impl true
    def supports_json_mode?, do: false

    @impl true
    def chat_completion_opts, do: Options.default()

    @impl true
    def stream_event_type, do: :openai

    @impl true
    def generate_text(model, prompt, opts) do
      Base.default_generate_text(__MODULE__, model, prompt, opts)
    end

    @impl true
    def stream_text(model, prompt, opts) do
      Base.default_stream_text(__MODULE__, model, prompt, opts)
    end

    @impl true
    def generate_object(model, prompt, schema, opts) do
      Base.default_generate_object(__MODULE__, model, prompt, schema, opts)
    end

    @impl true
    def stream_object(model, prompt, schema, opts) do
      Base.default_stream_object(__MODULE__, model, prompt, schema, opts)
    end
  end

  describe "extract_text_response/1" do
    test "extracts text from successful response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{"content" => "Generated text"}}
          ]
        }
      }

      assert {:ok, "Generated text"} = Base.extract_text_response(response)
    end

    test "handles error response" do
      response = %Req.Response{
        status: 400,
        body: %{"error" => %{"message" => "Bad request"}}
      }

      assert {:error, %API.Request{}} = Base.extract_text_response(response)
    end

    test "handles missing choices" do
      response = %Req.Response{
        status: 200,
        body: %{"choices" => []}
      }

      assert {:error, %API.Request{}} = Base.extract_text_response(response)
    end

    table_test(
      "handles different HTTP error codes",
      [
        bad_request: 400,
        unauthorized: 401,
        rate_limited: 429,
        server_error: 500
      ],
      fn {_name, status} ->
        response = %Req.Response{
          status: status,
          body: %{"error" => %{"message" => "Error #{status}"}}
        }

        assert {:error, %API.Request{}} = Base.extract_text_response(response)
      end
    )

    test "handles missing message content" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{}}
          ]
        }
      }

      assert {:ok, ""} = Base.extract_text_response(response)
    end

    test "handles unexpected response format" do
      response = %Req.Response{
        status: 200,
        body: %{"unexpected" => "format"}
      }

      assert {:error, %API.Request{}} = Base.extract_text_response(response)
    end
  end

  describe "build_chat_completion_body/4" do
    test "builds correct request body" do
      model = minimal(model: "test-model")
      opts = [temperature: 0.8, max_tokens: 1500]

      body = Base.build_chat_completion_body(model, "Hello", nil, opts)

      assert body[:model] == "test-model"
      assert body[:messages] == [%{role: "user", content: "Hello"}]
      assert body[:temperature] == 0.8
      assert body[:max_tokens] == 1500
    end

    test "converts prompt to messages format" do
      model = minimal()
      body = Base.build_chat_completion_body(model, "Test prompt", nil, [])

      assert body[:messages] == [%{role: "user", content: "Test prompt"}]
    end

    test "includes stream parameter when provided" do
      model = minimal()
      body = Base.build_chat_completion_body(model, "Hello", nil, stream: true)

      assert body[:stream] == true
    end

    test "excludes unsupported parameters" do
      model = minimal()
      body = Base.build_chat_completion_body(model, "Hello", nil, unsupported_param: "value", temperature: 0.5)

      assert body[:temperature] == 0.5
      refute Map.has_key?(body, :unsupported_param)
    end
  end

  describe "merge_model_options/3" do
    setup do
      Application.put_env(:jido_ai, :test_provider, api_key: "test-key-123")
      on_exit(fn -> Application.delete_env(:jido_ai, :test_provider) end)
      :ok
    end

    test "merges model configuration with request options" do
      model = minimal(provider: :test_provider, temperature: 0.7, max_tokens: 1000)
      opts = [temperature: 0.9, custom_option: "test"]

      merged = Base.merge_model_options(TestProvider, model, opts)

      # opts take precedence
      assert merged[:temperature] == 0.9
      # from model
      assert merged[:max_tokens] == 1000
      # from opts
      assert merged[:custom_option] == "test"
      # from config
      assert merged[:api_key] == "test-key-123"
      assert merged[:url] == "https://test.example.com/v1/chat/completions"
    end

    test "uses model defaults when opts don't override" do
      model = minimal(provider: :test_provider, temperature: 0.7, max_tokens: 1000, max_retries: 3)

      merged = Base.merge_model_options(TestProvider, model, [])

      assert merged[:temperature] == 0.7
      assert merged[:max_tokens] == 1000
      assert merged[:max_retries] == 3
    end

    test "opts take precedence over model config" do
      model = minimal(provider: :test_provider, temperature: 0.7, max_tokens: 1000)
      opts = [temperature: 1.0, max_tokens: 500, api_key: "override-key"]

      merged = Base.merge_model_options(TestProvider, model, opts)

      assert merged[:temperature] == 1.0
      assert merged[:max_tokens] == 500
      assert merged[:api_key] == "override-key"
    end
  end

  describe "default_generate_text/4" do
    setup do
      Application.put_env(:jido_ai, :test_provider, api_key: "test-key-123")
      on_exit(fn -> Application.delete_env(:jido_ai, :test_provider) end)
      :ok
    end

    test "returns error when prompt is nil" do
      model = minimal(provider: :test_provider)

      assert {:error, %Invalid.Parameter{parameter: "prompt"}} =
               Base.default_generate_text(TestProvider, model, nil, [])
    end

    test "returns error when prompt is empty string" do
      model = minimal(provider: :test_provider)

      assert {:error, %Invalid.Parameter{parameter: "prompt"}} =
               Base.default_generate_text(TestProvider, model, "", [])
    end
  end

  describe "default_stream_text/4" do
    setup do
      Application.put_env(:jido_ai, :test_provider, api_key: "test-key-123")
      on_exit(fn -> Application.delete_env(:jido_ai, :test_provider) end)
      :ok
    end

    test "returns error when prompt is nil" do
      model = minimal(provider: :test_provider)

      assert {:error, %Invalid.Parameter{parameter: "prompt"}} =
               Base.default_stream_text(TestProvider, model, nil, [])
    end

    test "returns error when prompt is empty string" do
      model = minimal(provider: :test_provider)

      assert {:error, %Invalid.Parameter{parameter: "prompt"}} =
               Base.default_stream_text(TestProvider, model, "", [])
    end
  end

  describe "merge_provider_options/4" do
    test "merges provider options with correct precedence" do
      model = fake()

      # Function level options
      function_opts = [provider_options: %{fake: %{param1: "function"}}]

      # Message level options (we'll use the message with parts)
      _message = %Message{
        role: :user,
        content: "Hello",
        metadata: %{provider_options: %{fake: %{param1: "message", param2: "message"}}}
      }

      # Content part level options (highest precedence)
      content_part = ContentPart.text("Hi", metadata: %{provider_options: %{fake: %{param1: "content"}}})

      message_with_parts = %Message{
        role: :user,
        content: [content_part],
        metadata: %{provider_options: %{fake: %{param1: "message", param2: "message"}}}
      }

      messages_with_parts = [message_with_parts]

      result = Base.merge_provider_options(model, messages_with_parts, function_opts, %{})

      # Content part should override message and function options
      assert result == %{fake: %{param1: "content", param2: "message"}}
    end

    test "returns empty map for string prompt" do
      model = fake()
      result = Base.merge_provider_options(model, "hello", [], %{})
      assert result == %{}
    end

    test "merges function level options" do
      model = fake()
      function_opts = [provider_options: %{fake: %{temperature: 0.7}}]

      result = Base.merge_provider_options(model, "hello", function_opts, %{})
      assert result == %{fake: %{temperature: 0.7}}
    end

    test "merges message level options" do
      model = fake()

      message = %Message{
        role: :user,
        content: "Hello",
        metadata: %{provider_options: %{fake: %{max_tokens: 100}}}
      }

      result = Base.merge_provider_options(model, [message], [], %{})
      assert result == %{fake: %{max_tokens: 100}}
    end

    test "merges content part level options" do
      model = fake()
      part = ContentPart.text("Hi", metadata: %{provider_options: %{fake: %{detail: "high"}}})
      message = %Message{role: :user, content: [part]}

      result = Base.merge_provider_options(model, [message], [], %{})
      assert result == %{fake: %{detail: "high"}}
    end

    test "deep merges nested provider options" do
      model = fake()

      function_opts = [provider_options: %{fake: %{nested: %{a: 1, b: 2}}}]

      message = %Message{
        role: :user,
        content: "Hello",
        metadata: %{provider_options: %{fake: %{nested: %{b: 3, c: 4}}}}
      }

      result = Base.merge_provider_options(model, [message], function_opts, %{})
      assert result == %{fake: %{nested: %{a: 1, b: 3, c: 4}}}
    end
  end

  describe "build_chat_completion_body/4 with provider options" do
    test "includes provider options in request body" do
      model = fake()

      opts = [
        temperature: 0.8,
        provider_options: %{fake: %{custom_param: "test_value"}}
      ]

      body = Base.build_chat_completion_body(model, "Hello", nil, opts)

      assert body[:model] == "fake-model"
      assert body[:messages] == [%{role: "user", content: "Hello"}]
      assert body[:temperature] == 0.8
      assert body[:custom_param] == "test_value"
    end

    test "message level provider options appear in request body" do
      model = fake()

      message = %Message{
        role: :user,
        content: "Hello",
        metadata: %{provider_options: %{fake: %{reasoning_effort: "low"}}}
      }

      body = Base.build_chat_completion_body(model, [message], nil, [])

      assert body[:reasoning_effort] == "low"
    end

    test "content part provider options override message options" do
      model = fake()
      part = ContentPart.text("Hi", metadata: %{provider_options: %{fake: %{param: "part"}}})

      message = %Message{
        role: :user,
        content: [part],
        metadata: %{provider_options: %{fake: %{param: "message"}}}
      }

      body = Base.build_chat_completion_body(model, [message], nil, [])

      assert body[:param] == "part"
    end
  end

  describe "FakeProvider integration" do
    test "FakeProvider works with Base callbacks" do
      model = fake()

      assert {:ok, result} = FakeProvider.generate_text(model, "test prompt", [])
      assert is_binary(result)
      assert String.contains?(result, "fake-model")
      assert String.contains?(result, "test prompt")
    end

    test "FakeProvider stream_text works" do
      model = fake()

      assert {:ok, stream} = FakeProvider.stream_text(model, "test prompt", [])

      result = Enum.to_list(stream)
      assert result == ["chunk_1", "chunk_2", "chunk_3"]
    end
  end
end
