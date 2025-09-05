defmodule JidoTest.AI.Actions.OpenaiEx.TranscriptionTest do
  use ExUnit.Case, async: false
  use Mimic
  require Logger
  alias Jido.AI.Actions.OpenaiEx.Transcription
  alias Jido.AI.Model
  alias OpenaiEx

  @moduletag :capture_log

  # Add global mock setup
  setup :set_mimic_global

  describe "run/2" do
    setup do
      # Copy the modules we need to mock
      Mimic.copy(OpenaiEx)
      Mimic.copy(OpenaiEx.Audio.Transcription)

      # Create a mock model
      {:ok, model} =
        Model.from({:openai, [model: "whisper-1", api_key: "test-api-key"]})

      # Create valid params with binary audio data
      params = %{
        model: model,
        file: "mock_audio_binary_content",
        filename: "audio.mp3"
      }

      # Create context
      context = %{state: %{}}

      {:ok, %{model: model, params: params, context: context}}
    end

    test "successfully transcribes audio with default parameters", %{
      params: params,
      context: context
    } do
      # Create expected request
      expected_req =
        OpenaiEx.Audio.Transcription.new(
          model: "whisper-1",
          file: {"audio.mp3", "mock_audio_binary_content"}
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Audio.Transcription, :create, fn _client, ^expected_req ->
        {:ok, %{"text" => "This is a test transcription", "duration" => 2.5}}
      end)

      assert {:ok, %{text: "This is a test transcription", duration: 2.5}} =
               Transcription.run(params, context)
    end

    test "successfully transcribes audio with text response format", %{
      params: params,
      context: context
    } do
      # Update params with text format
      params = Map.put(params, :response_format, "text")

      # Create expected request
      expected_req =
        OpenaiEx.Audio.Transcription.new(
          model: "whisper-1",
          file: {"audio.mp3", "mock_audio_binary_content"},
          response_format: "text"
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Audio.Transcription, :create, fn _client, ^expected_req ->
        {:ok, "This is a test transcription"}
      end)

      assert {:ok, %{text: "This is a test transcription"}} =
               Transcription.run(params, context)
    end

    test "successfully transcribes audio with additional parameters", %{
      params: params,
      context: context
    } do
      # Add additional parameters
      params =
        Map.merge(params, %{
          language: "en",
          prompt: "This is a technical discussion about AI.",
          response_format: "verbose_json",
          temperature: 0.2,
          timestamp_granularities: ["segment", "word"]
        })

      # Create expected request
      expected_req =
        OpenaiEx.Audio.Transcription.new(
          model: "whisper-1",
          file: {"audio.mp3", "mock_audio_binary_content"},
          language: "en",
          prompt: "This is a technical discussion about AI.",
          response_format: "verbose_json",
          temperature: 0.2,
          timestamp_granularities: ["segment", "word"]
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Audio.Transcription, :create, fn _client, ^expected_req ->
        {:ok,
         %{
           "text" => "This is a test transcription",
           "duration" => 3.0,
           "segments" => [
             %{
               "id" => 0,
               "start" => 0.0,
               "end" => 2.5,
               "text" => "This is a test transcription",
               "tokens" => [1, 2, 3],
               "temperature" => 0.2,
               "avg_logprob" => -0.5,
               "compression_ratio" => 1.2,
               "no_speech_prob" => 0.1
             }
           ],
           "words" => [
             %{"word" => "This", "start" => 0.0, "end" => 0.5},
             %{"word" => "is", "start" => 0.5, "end" => 0.8}
           ]
         }}
      end)

      assert {:ok,
              %{
                text: "This is a test transcription",
                duration: 3.0,
                segments: [%{id: 0, start: 0.0, end: 2.5, text: "This is a test transcription"}],
                words: [
                  %{word: "This", start: 0.0, end: 0.5},
                  %{word: "is", start: 0.5, end: 0.8}
                ]
              }} = Transcription.run(params, context)
    end

    test "successfully transcribes audio with SRT format", %{
      params: params,
      context: context
    } do
      # Update params with SRT format
      params = Map.put(params, :response_format, "srt")

      # Create expected request
      expected_req =
        OpenaiEx.Audio.Transcription.new(
          model: "whisper-1",
          file: {"audio.mp3", "mock_audio_binary_content"},
          response_format: "srt"
        )

      srt_content = """
      1
      00:00:00,000 --> 00:00:02,500
      This is a test transcription
      """

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Audio.Transcription, :create, fn _client, ^expected_req ->
        {:ok, srt_content}
      end)

      assert {:ok, %{content: ^srt_content}} = Transcription.run(params, context)
    end

    test "successfully transcribes audio with OpenRouter model", %{
      params: params,
      context: context
    } do
      # Update params to use OpenRouter model
      {:ok, model} =
        Model.from({:openrouter, [model: "openai/whisper-1", api_key: "test-api-key"]})

      # Update params with the OpenRouter model
      params = %{params | model: model}

      # Create expected request
      expected_req =
        OpenaiEx.Audio.Transcription.new(
          model: "openai/whisper-1",
          file: {"audio.mp3", "mock_audio_binary_content"}
        )

      # Mock the OpenRouter client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)
      expect(OpenaiEx, :with_base_url, fn client, _url -> client end)
      expect(OpenaiEx, :with_additional_headers, fn client, _headers -> client end)

      expect(OpenaiEx.Audio.Transcription, :create, fn _client, ^expected_req ->
        {:ok, %{"text" => "This is a test transcription", "duration" => 2.5}}
      end)

      assert {:ok, %{text: "This is a test transcription", duration: 2.5}} =
               Transcription.run(params, context)
    end

    test "successfully transcribes audio with custom base URL", %{
      params: params,
      context: context
    } do
      # Create model with custom base URL
      custom_model = %Model{
        provider: :openai,
        model: "whisper-1",
        api_key: "test-api-key",
        base_url: "https://custom-api.example.com/v1",
        name: "Custom OpenAI Model",
        id: "custom-openai-whisper-1",
        description: "Custom OpenAI model",
        created: System.system_time(:second),
        architecture: %Model.Architecture{
          modality: "text",
          tokenizer: "unknown",
          instruct_type: nil
        },
        endpoints: []
      }

      # Update params with custom model
      params = %{params | model: custom_model}

      # Create expected request
      expected_req =
        OpenaiEx.Audio.Transcription.new(
          model: "whisper-1",
          file: {"audio.mp3", "mock_audio_binary_content"}
        )

      # Mock the custom endpoint client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx, :with_base_url, fn client, "https://custom-api.example.com/v1" ->
        client
      end)

      expect(OpenaiEx.Audio.Transcription, :create, fn _client, ^expected_req ->
        {:ok, %{"text" => "This is a test transcription", "duration" => 2.5}}
      end)

      assert {:ok, %{text: "This is a test transcription", duration: 2.5}} =
               Transcription.run(params, context)
    end

    test "returns error for invalid model specification", %{params: params, context: context} do
      params = %{params | model: "invalid_model"}

      assert {:error, "Invalid model specification. Must be a map or {provider, opts} tuple."} =
               Transcription.run(params, context)
    end

    test "returns error for invalid provider", %{params: params, context: context} do
      params = %{
        params
        | model: %Model{
            provider: :invalid_provider,
            model: "whisper-1",
            api_key: "test-api-key",
            name: "Test Model",
            id: "test-model",
            description: "Test Model",
            created: System.system_time(:second),
            architecture: %Model.Architecture{
              modality: "text",
              tokenizer: "unknown",
              instruct_type: nil
            },
            endpoints: []
          }
      }

      assert {:error,
              "Invalid provider: :invalid_provider. Must be one of: [:openai, :openrouter, :google]"} =
               Transcription.run(params, context)
    end

    test "returns error for missing filename with binary data", %{model: model, context: context} do
      params = %{
        model: model,
        file: "binary_audio_data"
      }

      assert {:error, "filename parameter is required when file is binary data"} =
               Transcription.run(params, context)
    end

    test "returns error for unsupported file format", %{model: model, context: context} do
      params = %{
        model: model,
        file: "audio_data",
        filename: "audio.xyz"
      }

      assert {:error, "Unsupported file format: xyz. Supported formats: " <> _} =
               Transcription.run(params, context)
    end

    test "returns error for invalid file parameter type", %{model: model, context: context} do
      params = %{
        model: model,
        file: 123
      }

      assert {:error, "Invalid file parameter"} =
               Transcription.run(params, context)
    end
  end
end
