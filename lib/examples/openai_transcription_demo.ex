defmodule OpenAITranscriptionDemo do
  @moduledoc """
  Demo module showcasing OpenAI transcription capabilities using Jido AI.

  This module demonstrates various ways to use the transcription action:
  - Basic transcription from audio files
  - Different response formats (text, json, srt, vtt)
  - Using custom language and prompt parameters
  - Error handling patterns
  - Integration with Jido workflows

  ## Prerequisites

  Set your OpenAI API key:
  ```bash
  export OPENAI_API_KEY="your-openai-api-key"
  ```

  ## Sample Usage

  ```elixir
  # Basic transcription
  OpenAITranscriptionDemo.basic_transcription("/path/to/audio.mp3")

  # Advanced transcription with parameters
  OpenAITranscriptionDemo.advanced_transcription("/path/to/audio.wav")

  # Different response formats
  OpenAITranscriptionDemo.srt_transcription("/path/to/audio.mp3")

  # Binary audio data
  OpenAITranscriptionDemo.binary_transcription(audio_binary, "meeting.wav")

  # Using OpenRouter
  OpenAITranscriptionDemo.openrouter_transcription("/path/to/audio.mp3")
  ```
  """

  alias Jido.AI.Actions.OpenaiEx.Transcription
  alias Jido.AI.Model
  require Logger

  @doc """
  Performs basic transcription using OpenAI Whisper.
  """
  def basic_transcription(audio_file_path) do
    {:ok, model} = Model.from({:openai, [model: "whisper-1"]})

    params = %{
      model: model,
      file: audio_file_path
    }

    case Transcription.run(params, %{}) do
      {:ok, result} ->
        IO.puts("=== Basic Transcription ===")
        IO.puts("File: #{audio_file_path}")
        IO.puts("Transcript: #{result.transcript}")
        IO.puts("")
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ Transcription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Advanced transcription with language specification, prompt, and temperature control.
  """
  def advanced_transcription(audio_file_path) do
    {:ok, model} = Model.from({:openai, [model: "whisper-1"]})

    params = %{
      model: model,
      file: audio_file_path,
      language: "en",
      prompt:
        "This is a technical discussion about AI, machine learning, and software engineering.",
      response_format: "verbose_json",
      temperature: 0.2
    }

    case Transcription.run(params, %{}) do
      {:ok, result} ->
        IO.puts("=== Advanced Transcription ===")
        IO.puts("File: #{audio_file_path}")
        IO.puts("Transcript: #{result.transcript}")

        if Map.has_key?(result, :response) do
          response = result.response

          if Map.has_key?(response, :language) do
            IO.puts("Detected Language: #{response.language}")
          end

          if Map.has_key?(response, :duration) do
            IO.puts("Duration: #{response.duration} seconds")
          end

          if Map.has_key?(response, :segments) do
            IO.puts("Number of segments: #{length(response.segments)}")

            # Show first few segments
            response.segments
            |> Enum.take(3)
            |> Enum.with_index(1)
            |> Enum.each(fn {segment, index} ->
              IO.puts(
                "  Segment #{index}: #{segment.start}s - #{segment.end}s: \"#{segment.text}\""
              )
            end)
          end
        end

        IO.puts("")
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ Advanced transcription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Transcription with SRT subtitle format output.
  """
  def srt_transcription(audio_file_path) do
    {:ok, model} = Model.from({:openai, [model: "whisper-1"]})

    params = %{
      model: model,
      file: audio_file_path,
      response_format: "srt"
    }

    case Transcription.run(params, %{}) do
      {:ok, result} ->
        IO.puts("=== SRT Transcription ===")
        IO.puts("File: #{audio_file_path}")
        IO.puts("SRT Content:")
        IO.puts(result.content)
        IO.puts("")

        # Optionally save to file
        srt_filename = Path.basename(audio_file_path, Path.extname(audio_file_path)) <> ".srt"
        File.write(srt_filename, result.content)
        IO.puts("✅ SRT saved to: #{srt_filename}")
        IO.puts("")

        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ SRT transcription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Transcription with VTT (WebVTT) subtitle format output.
  """
  def vtt_transcription(audio_file_path) do
    {:ok, model} = Model.from({:openai, [model: "whisper-1"]})

    params = %{
      model: model,
      file: audio_file_path,
      response_format: "vtt"
    }

    case Transcription.run(params, %{}) do
      {:ok, result} ->
        IO.puts("=== VTT Transcription ===")
        IO.puts("File: #{audio_file_path}")
        IO.puts("VTT Content:")
        IO.puts(result.content)
        IO.puts("")

        # Optionally save to file
        vtt_filename = Path.basename(audio_file_path, Path.extname(audio_file_path)) <> ".vtt"
        File.write(vtt_filename, result.content)
        IO.puts("✅ VTT saved to: #{vtt_filename}")
        IO.puts("")

        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ VTT transcription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Transcription using binary audio data instead of file path.
  """
  def binary_transcription(audio_binary, filename) do
    {:ok, model} = Model.from({:openai, [model: "whisper-1"]})

    params = %{
      model: model,
      file: audio_binary,
      filename: filename,
      response_format: "json"
    }

    case Transcription.run(params, %{}) do
      {:ok, result} ->
        IO.puts("=== Binary Transcription ===")
        IO.puts("Binary size: #{byte_size(audio_binary)} bytes")
        IO.puts("Filename: #{filename}")
        IO.puts("Transcript: #{result.transcript}")
        IO.puts("")
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ Binary transcription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Transcription using OpenRouter provider.
  """
  def openrouter_transcription(audio_file_path) do
    {:ok, model} = Model.from({:openrouter, [model: "openai/whisper-large-v3"]})

    params = %{
      model: model,
      file: audio_file_path,
      response_format: "verbose_json"
    }

    case Transcription.run(params, %{}) do
      {:ok, result} ->
        IO.puts("=== OpenRouter Transcription ===")
        IO.puts("Provider: OpenRouter")
        IO.puts("Model: openai/whisper-large-v3")
        IO.puts("File: #{audio_file_path}")
        IO.puts("Transcript: #{result.transcript}")
        IO.puts("")
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ OpenRouter transcription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Demonstrates multilingual transcription with different languages.
  """
  def multilingual_transcription(audio_file_path, language_code, context_prompt \\ nil) do
    {:ok, model} = Model.from({:openai, [model: "whisper-1"]})

    params = %{
      model: model,
      file: audio_file_path,
      language: language_code,
      response_format: "verbose_json"
    }

    params =
      if context_prompt do
        Map.put(params, :prompt, context_prompt)
      else
        params
      end

    case Transcription.run(params, %{}) do
      {:ok, result} ->
        IO.puts("=== Multilingual Transcription ===")
        IO.puts("File: #{audio_file_path}")
        IO.puts("Language Code: #{language_code}")
        if context_prompt, do: IO.puts("Context Prompt: #{context_prompt}")
        IO.puts("Transcript: #{result.transcript}")

        if Map.has_key?(result, :response) and Map.has_key?(result.response, :language) do
          IO.puts("Detected Language: #{result.response.language}")
        end

        IO.puts("")
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ Multilingual transcription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Transcription using custom API endpoint and key.
  """
  def custom_endpoint_transcription(audio_file_path, custom_api_key, custom_base_url) do
    {:ok, model} =
      Model.from(
        {:openai,
         [
           model: "whisper-1",
           api_key: custom_api_key,
           base_url: custom_base_url
         ]}
      )

    params = %{
      model: model,
      file: audio_file_path,
      response_format: "json"
    }

    case Transcription.run(params, %{}) do
      {:ok, result} ->
        IO.puts("=== Custom Endpoint Transcription ===")
        IO.puts("Custom API Key: #{String.slice(custom_api_key, 0..10)}...")
        IO.puts("Custom Base URL: #{custom_base_url}")
        IO.puts("File: #{audio_file_path}")
        IO.puts("Transcript: #{result.transcript}")
        IO.puts("")
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ Custom endpoint transcription failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Demonstrates batch processing multiple audio files.
  """
  def batch_transcription(audio_files) do
    IO.puts("=== Batch Transcription ===")
    IO.puts("Processing #{length(audio_files)} files...")
    IO.puts("")

    results =
      audio_files
      |> Enum.with_index(1)
      |> Enum.map(fn {file, index} ->
        IO.puts("Processing file #{index}/#{length(audio_files)}: #{Path.basename(file)}")

        case basic_transcription(file) do
          {:ok, result} -> {file, {:ok, result}}
          {:error, reason} -> {file, {:error, reason}}
        end
      end)

    # Summary
    successful = Enum.count(results, fn {_, result} -> match?({:ok, _}, result) end)
    failed = length(results) - successful

    IO.puts("=== Batch Summary ===")
    IO.puts("✅ Successful: #{successful}")
    IO.puts("❌ Failed: #{failed}")

    results
  end

  @doc """
  Comprehensive demo showcasing all features.
  """
  def comprehensive_demo(audio_file_path) do
    IO.puts("🎙️  OpenAI Transcription Comprehensive Demo")
    IO.puts("==========================================")
    IO.puts("")

    # Check if file exists
    unless File.exists?(audio_file_path) do
      IO.puts("❌ Error: Audio file not found: #{audio_file_path}")
      IO.puts("Please provide a valid audio file path.")
      IO.puts("")
      IO.puts("Supported formats: mp3, mp4, mpeg, mpga, m4a, wav, webm, flac")
      {:error, :file_not_found}
    end

    # Basic transcription
    basic_transcription(audio_file_path)

    # Advanced transcription
    advanced_transcription(audio_file_path)

    # SRT format
    srt_transcription(audio_file_path)

    # VTT format  
    vtt_transcription(audio_file_path)

    # Multilingual with Spanish
    multilingual_transcription(
      audio_file_path,
      "es",
      "Esta es una conversación sobre tecnología."
    )

    # Example with custom endpoint (using OpenAI-compatible endpoint)
    IO.puts("Example custom endpoint usage:")

    IO.puts(
      "custom_endpoint_transcription(\"/path/to/audio.mp3\", \"your-api-key\", \"https://your-endpoint.com/v1\")"
    )

    IO.puts("🎉 Demo completed!")
  end

  @doc """
  Error handling demonstration.
  """
  def error_handling_demo do
    IO.puts("=== Error Handling Demo ===")

    # Test 1: Invalid file format
    IO.puts("Test 1: Invalid file format")
    {:ok, model} = Model.from({:openai, [model: "whisper-1"]})

    params = %{
      model: model,
      file: "audio_data",
      filename: "audio.invalid"
    }

    case Transcription.run(params, %{}) do
      {:error, reason} ->
        IO.puts("✅ Expected error caught: #{reason}")

      result ->
        IO.puts("❌ Unexpected result: #{inspect(result)}")
    end

    # Test 2: Missing filename for binary data
    IO.puts("\nTest 2: Missing filename for binary data")

    params = %{
      model: model,
      file: "some_binary_data"
    }

    case Transcription.run(params, %{}) do
      {:error, reason} ->
        IO.puts("✅ Expected error caught: #{reason}")

      result ->
        IO.puts("❌ Unexpected result: #{inspect(result)}")
    end

    # Test 3: Invalid model
    IO.puts("\nTest 3: Invalid model specification")

    params = %{
      model: "invalid_model",
      file: "/path/to/audio.mp3"
    }

    case Transcription.run(params, %{}) do
      {:error, reason} ->
        IO.puts("✅ Expected error caught: #{reason}")

      result ->
        IO.puts("❌ Unexpected result: #{inspect(result)}")
    end

    IO.puts("\n✅ Error handling demo completed")
  end

  @doc """
  Helper function to load and transcribe audio from a URL (downloads first).
  """
  def transcribe_from_url(audio_url, temp_filename \\ nil) do
    filename = temp_filename || Path.basename(URI.parse(audio_url).path)
    temp_path = Path.join(System.tmp_dir!(), filename)

    IO.puts("🌐 Downloading audio from URL: #{audio_url}")

    case download_file(audio_url, temp_path) do
      :ok ->
        IO.puts("✅ Downloaded to: #{temp_path}")
        result = basic_transcription(temp_path)

        # Clean up
        File.rm(temp_path)
        result

      {:error, reason} ->
        IO.puts("❌ Download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper function to download file
  defp download_file(url, path) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        File.write(path, body)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
