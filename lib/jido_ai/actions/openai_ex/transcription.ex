defmodule Jido.AI.Actions.OpenaiEx.Transcription do
  @moduledoc """
  Action module for audio transcription using OpenAI Ex.

  This module supports audio transcription with both OpenAI and OpenRouter providers.
  It uses the Whisper models to convert audio to text with various customization 
  options for improved accuracy and different output formats.

  ## Features

  - Support for both OpenAI and OpenRouter providers  
  - Audio file transcription via file path or binary data
  - Multiple response formats (text, json, srt, verbose_json, vtt)
  - Language specification for improved accuracy
  - Custom prompts for context and guidance
  - Temperature control for output randomness
  - Timestamp granularities (segment and word level)

  ## Usage

  ```elixir
  # Basic transcription from file path
  {:ok, result} = Jido.AI.Actions.OpenaiEx.Transcription.run(
    %{
      model: %Jido.AI.Model{provider: :openai, model: "whisper-1", api_key: "key"},
      file: "/path/to/audio.mp3"
    },
    %{}
  )

  # Advanced transcription with custom parameters
  {:ok, result} = Jido.AI.Actions.OpenaiEx.Transcription.run(
    %{
      model: %Jido.AI.Model{provider: :openai, model: "whisper-1", api_key: "key"},
      file: "/path/to/audio.wav",
      language: "en",
      prompt: "This is a technical discussion about AI and machine learning.",
      response_format: "verbose_json",
      temperature: 0.2,
      timestamp_granularities: ["segment", "word"]
    },
    %{}
  )

  # Transcription with binary audio data
  {:ok, result} = Jido.AI.Actions.OpenaiEx.Transcription.run(
    %{
      model: %Jido.AI.Model{provider: :openai, model: "whisper-1", api_key: "key"},
      file: audio_binary,
      filename: "audio.mp3"
    },
    %{}
  )
  ```
  """
  use Jido.Action,
    name: "openai_ex_transcription",
    description: "Transcribe audio files using OpenAI Ex with support for OpenRouter",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc: "The AI model to use (e.g., {:openai, [model: \"whisper-1\"]} or %Jido.AI.Model{})"
      ],
      file: [
        type: {:or, [:string, :binary]},
        required: true,
        doc: "Audio file path (string) or binary audio data"
      ],
      filename: [
        type: :string,
        required: false,
        doc: "Filename for binary audio data (required when file is binary)"
      ],
      language: [
        type: :string,
        required: false,
        doc: "ISO-639-1 language code (e.g., 'en', 'es', 'fr') for improved accuracy"
      ],
      prompt: [
        type: :string,
        required: false,
        doc: "Optional text to guide the model's style or continue a previous segment"
      ],
      response_format: [
        type: {:in, ["json", "text", "srt", "verbose_json", "vtt"]},
        required: false,
        default: "json",
        doc: "Format of the transcript output"
      ],
      temperature: [
        type: :float,
        required: false,
        doc: "Sampling temperature between 0 and 1 for output randomness"
      ],
      timestamp_granularities: [
        type: {:list, {:in, ["segment", "word"]}},
        required: false,
        doc: "Timestamp granularities for verbose_json format"
      ]
    ]

  require Logger
  alias Jido.AI.Model
  alias OpenaiEx.Audio.Transcription, as: AudioTranscription

  @valid_providers [:openai, :openrouter, :google]
  @supported_formats ~w[mp3 mp4 mpeg mpga m4a wav webm flac]

  @doc """
  Transcribes audio using OpenAI Ex.

  ## Parameters
    - params: Map containing:
      - model: Either a %Jido.AI.Model{} struct or a tuple of {provider, opts}
      - file: Audio file path (string) or binary audio data  
      - filename: Required filename when file is binary data
      - language: Optional ISO-639-1 language code
      - prompt: Optional guidance text for the model
      - response_format: Optional output format
      - temperature: Optional sampling temperature (0-1)
      - timestamp_granularities: Optional list for verbose_json format
    - context: The action context containing state and other information

  ## Returns
    - {:ok, %{text: text}} for text format
    - {:ok, %{text: text, duration: duration}} for json format
    - {:ok, %{text: text, duration: duration, segments: segments, words: words}} for verbose_json format
    - {:ok, %{content: content}} for srt/vtt formats
    - {:error, reason} on failure
  """
  @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def run(params, context) do
    Logger.info("Running OpenAI Ex transcription with params: #{inspect(params)}")
    Logger.info("Context: #{inspect(context)}")

    with {:ok, model} <- validate_and_get_model(params),
         {:ok, file_data} <- validate_and_get_file(params),
         {:ok, req} <- build_request(model, file_data, params) do
      make_request(model, req, params[:response_format] || "json")
    end
  end

  # Private functions

  @spec validate_and_get_model(map()) :: {:ok, Model.t()} | {:error, String.t()}
  defp validate_and_get_model(%{model: model}) when is_map(model) do
    case Model.from(model) do
      {:ok, model} -> validate_provider(model)
      error -> error
    end
  end

  defp validate_and_get_model(%{model: {provider, opts}})
       when is_atom(provider) and is_list(opts) do
    case Model.from({provider, opts}) do
      {:ok, model} -> validate_provider(model)
      error -> error
    end
  end

  defp validate_and_get_model(_) do
    {:error, "Invalid model specification. Must be a map or {provider, opts} tuple."}
  end

  @spec validate_provider(Model.t()) :: {:ok, Model.t()} | {:error, String.t()}
  defp validate_provider(%Model{provider: provider} = model) when provider in @valid_providers do
    {:ok, model}
  end

  defp validate_provider(%Model{provider: provider}) do
    {:error,
     "Invalid provider: #{inspect(provider)}. Must be one of: #{inspect(@valid_providers)}"}
  end

  @spec validate_and_get_file(map()) :: {:ok, map()} | {:error, String.t()}
  defp validate_and_get_file(%{file: file_path, filename: filename})
       when is_binary(file_path) and is_binary(filename) do
    # Check if it's a file path first, even if filename is provided
    if File.exists?(file_path) do
      with :ok <- validate_file_format(filename),
           {:ok, content} <- File.read(file_path) do
        {:ok, %{content: content, filename: ensure_filename_extension(filename)}}
      else
        {:error, reason} when is_binary(reason) -> {:error, reason}
        {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
      end
    else
      # Binary data with filename provided
      validate_binary_file(%{file: file_path}, %{filename: filename})
    end
  end

  defp validate_and_get_file(%{file: file_path}) when is_binary(file_path) do
    if File.exists?(file_path) do
      with :ok <- validate_file_format(file_path),
           {:ok, content} <- File.read(file_path) do
        {:ok, %{content: content, filename: ensure_filename_extension(Path.basename(file_path))}}
      else
        {:error, reason} when is_binary(reason) -> {:error, reason}
        {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
      end
    else
      # Binary data without filename - return error
      {:error, "filename parameter is required when file is binary data"}
    end
  end

  defp validate_and_get_file(params) when is_map(params) do
    validate_binary_file(params, params)
  end

  defp validate_and_get_file(_) do
    {:error, "File must be a file path string or binary data"}
  end

  @spec validate_binary_file(map(), map()) :: {:ok, map()} | {:error, String.t()}
  defp validate_binary_file(%{file: content}, %{filename: filename})
       when is_binary(content) and is_binary(filename) do
    case validate_file_format(filename) do
      :ok -> {:ok, %{content: content, filename: ensure_filename_extension(filename)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_binary_file(%{file: content}, _) when is_binary(content) do
    {:error, "filename parameter is required when file is binary data"}
  end

  defp validate_binary_file(_, _) do
    {:error, "Invalid file parameter"}
  end

  @spec ensure_filename_extension(String.t()) :: String.t()
  defp ensure_filename_extension(filename) do
    if String.contains?(filename, ".") do
      filename
    else
      # Default to .webm for browser recordings
      "#{filename}.webm"
    end
  end

  @spec validate_file_format(String.t()) :: :ok | {:error, String.t()}
  defp validate_file_format(filename) do
    # Ensure filename has extension before validation
    filename_with_ext = ensure_filename_extension(filename)
    extension = filename_with_ext |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    if extension in @supported_formats do
      :ok
    else
      {:error,
       "Unsupported file format: #{extension}. Supported formats: #{Enum.join(@supported_formats, ", ")}"}
    end
  end

  @spec build_request(Model.t(), map(), map()) :: {:ok, map()}
  defp build_request(model, file_data, params) do
    req =
      AudioTranscription.new(
        model: Map.get(model, :model),
        file: {file_data.filename, file_data.content}
      )

    req =
      req
      |> maybe_add_param(:language, params[:language])
      |> maybe_add_param(:prompt, params[:prompt])
      |> maybe_add_param(:response_format, params[:response_format])
      |> maybe_add_param(:temperature, params[:temperature])
      |> maybe_add_param(:timestamp_granularities, params[:timestamp_granularities])

    {:ok, req}
  end

  @spec maybe_add_param(map(), atom(), any()) :: map()
  defp maybe_add_param(req, _key, nil), do: req
  defp maybe_add_param(req, key, value), do: Map.put(req, key, value)

  @spec make_request(Model.t(), map(), String.t()) :: {:ok, map()} | {:error, any()}
  defp make_request(model, req, response_format) do
    client =
      OpenaiEx.new(model.api_key)
      |> maybe_add_base_url(model)
      |> maybe_add_headers(model)

    case AudioTranscription.create(client, req) do
      {:ok, response} ->
        {:ok, format_response(response, response_format)}

      error ->
        Logger.error("Transcription request failed: #{inspect(error)}")
        error
    end
  end

  @spec format_response(any(), String.t()) :: map()
  defp format_response(response, "text") when is_binary(response) do
    %{text: response}
  end

  defp format_response(response, format) when format in ["srt", "vtt"] and is_binary(response) do
    %{content: response}
  end

  defp format_response(response, "json") when is_map(response) do
    %{
      text: response["text"],
      duration: response["duration"]
    }
  end

  defp format_response(response, "verbose_json") when is_map(response) do
    %{
      text: response["text"],
      duration: response["duration"],
      segments: format_segments(response["segments"]),
      words: format_words(response["words"])
    }
  end

  defp format_response(response, _format)
       when is_map(response) and is_map_key(response, "text") do
    %{text: response["text"]}
  end

  defp format_response(response, _format) when is_binary(response) do
    %{text: response}
  end

  defp format_response(response, _format) do
    %{response: response}
  end

  # Helper functions to format nested structures with atom keys
  defp format_segments(segments) when is_list(segments) do
    Enum.map(segments, fn segment ->
      %{
        id: segment["id"],
        seek: segment["seek"],
        start: segment["start"],
        end: segment["end"],
        text: segment["text"],
        tokens: segment["tokens"],
        temperature: segment["temperature"],
        avg_logprob: segment["avg_logprob"],
        compression_ratio: segment["compression_ratio"],
        no_speech_prob: segment["no_speech_prob"]
      }
    end)
  end

  defp format_segments(_), do: []

  defp format_words(words) when is_list(words) do
    Enum.map(words, fn word ->
      %{
        word: word["word"],
        start: word["start"],
        end: word["end"]
      }
    end)
  end

  defp format_words(_), do: []

  @spec maybe_add_base_url(OpenaiEx.t(), Model.t()) :: OpenaiEx.t()
  defp maybe_add_base_url(client, %Model{base_url: base_url})
       when is_binary(base_url) and base_url != "" do
    OpenaiEx.with_base_url(client, base_url)
  end

  defp maybe_add_base_url(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_base_url(client, Jido.AI.Provider.OpenRouter.base_url())
  end

  defp maybe_add_base_url(client, %Model{provider: :google}) do
    OpenaiEx.with_base_url(client, Jido.AI.Provider.Google.base_url())
  end

  defp maybe_add_base_url(client, _), do: client

  @spec maybe_add_headers(OpenaiEx.t(), Model.t()) :: OpenaiEx.t()
  defp maybe_add_headers(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_additional_headers(client, Jido.AI.Provider.OpenRouter.request_headers([]))
  end

  defp maybe_add_headers(client, %Model{provider: :google}) do
    OpenaiEx.with_additional_headers(client, Jido.AI.Provider.Google.request_headers([]))
  end

  defp maybe_add_headers(client, _), do: client
end
