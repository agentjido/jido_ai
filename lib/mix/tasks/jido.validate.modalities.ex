defmodule Mix.Tasks.Jido.Validate.Modalities do
  @moduledoc """
  Validates multi-modal support across all providers.

  This task validates vision, audio, and document processing capabilities
  and generates a comprehensive modality compatibility matrix.

  ## Usage

      mix jido.validate.modalities
      mix jido.validate.modalities --modality vision
      mix jido.validate.modalities --provider anthropic
      mix jido.validate.modalities --export notes/modality-matrix.md
      mix jido.validate.modalities --verbose

  ## Options

    * `--modality` - Validate only a specific modality (vision, audio, document)
    * `--provider` - Validate only a specific provider
    * `--export` - Export compatibility matrix to file
    * `--verbose` - Show detailed validation results
  """

  use Mix.Task
  require Logger

  alias Jido.AI.Model.Registry

  @shortdoc "Validates multi-modal support across all providers"

  @known_vision_models [
    "gpt-4-vision-preview",
    "gpt-4-turbo",
    "gpt-4o",
    "claude-3-opus",
    "claude-3-sonnet",
    "claude-3-5-sonnet",
    "claude-3-haiku",
    "gemini-pro-vision",
    "gemini-1.5-pro",
    "gemini-1.5-flash",
    "gemini-2.0-flash"
  ]

  @known_audio_models [
    "whisper",
    "gpt-4o-audio"
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [modality: :string, provider: :string, export: :string, verbose: :boolean],
        aliases: [m: :modality, p: :provider, e: :export, v: :verbose]
      )

    modality_filter = opts[:modality] && String.to_atom(opts[:modality])
    provider = opts[:provider] && String.to_atom(opts[:provider])
    export_path = opts[:export]
    verbose = opts[:verbose] || false

    Mix.shell().info("=== Multi-Modal Support Validation ===\n")

    case Registry.list_models(provider) do
      {:ok, models} ->
        results = validate_all_modalities(models, modality_filter, verbose)
        print_summary(results, provider)

        if export_path do
          export_matrix(results, export_path)
        end

      {:error, reason} ->
        Mix.shell().error("Failed to list models: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp validate_all_modalities(models, modality_filter, verbose) do
    total = length(models)
    Mix.shell().info("Analyzing #{total} models for multi-modal support...\n")

    # Group models by modality support
    modality_groups = group_by_modalities(models)

    # Run validation for each modality type
    results = %{
      total_models: total,
      vision:
        if(!modality_filter || modality_filter == :vision,
          do: validate_vision(models, verbose),
          else: nil
        ),
      audio:
        if(!modality_filter || modality_filter == :audio,
          do: validate_audio(models, verbose),
          else: nil
        ),
      document:
        if(!modality_filter || modality_filter == :document,
          do: validate_document(models, verbose),
          else: nil
        ),
      modality_groups: modality_groups,
      multimodal_models: identify_multimodal_models(models),
      provider_stats: calculate_provider_stats(models)
    }

    results
  end

  defp group_by_modalities(models) do
    Enum.reduce(models, %{}, fn model, acc ->
      modalities = get_model_modalities(model)
      input_mods = Map.get(modalities, :input, [:text])
      output_mods = Map.get(modalities, :output, [:text])

      Enum.reduce(input_mods, acc, fn mod, inner_acc ->
        Map.update(inner_acc, {:input, mod}, 1, &(&1 + 1))
      end)
      |> then(fn inner_acc ->
        Enum.reduce(output_mods, inner_acc, fn mod, final_acc ->
          Map.update(final_acc, {:output, mod}, 1, &(&1 + 1))
        end)
      end)
    end)
  end

  defp validate_vision(models, verbose) do
    Mix.shell().info("=== Validating Vision Capabilities ===\n")

    vision_models = Enum.filter(models, &has_modality?(&1, :input, :image))

    known_detected = count_known_models_detected(vision_models, @known_vision_models)
    total_known = length(@known_vision_models)

    if verbose do
      Mix.shell().info("Vision-capable models:")

      Enum.each(vision_models, fn model ->
        model_id = get_model_id(model)
        provider = get_model_provider(model)
        Mix.shell().info("  ✅ #{provider}:#{model_id}")
      end)

      Mix.shell().info("")
    end

    accuracy =
      if total_known > 0, do: Float.round(known_detected / total_known * 100, 1), else: 0.0

    %{
      total: length(vision_models),
      models: vision_models,
      known_detected: known_detected,
      total_known: total_known,
      accuracy: accuracy
    }
  end

  defp validate_audio(models, verbose) do
    Mix.shell().info("=== Validating Audio Capabilities ===\n")

    audio_models = Enum.filter(models, &has_modality?(&1, :input, :audio))

    known_detected = count_known_models_detected(audio_models, @known_audio_models)
    total_known = length(@known_audio_models)

    if verbose do
      Mix.shell().info("Audio-capable models:")

      Enum.each(audio_models, fn model ->
        model_id = get_model_id(model)
        provider = get_model_provider(model)
        Mix.shell().info("  ✅ #{provider}:#{model_id}")
      end)

      Mix.shell().info("")
    end

    accuracy =
      if total_known > 0, do: Float.round(known_detected / total_known * 100, 1), else: 0.0

    %{
      total: length(audio_models),
      models: audio_models,
      known_detected: known_detected,
      total_known: total_known,
      accuracy: accuracy
    }
  end

  defp validate_document(models, verbose) do
    Mix.shell().info("=== Validating Document Processing Capabilities ===\n")

    # Look for document modality or document-related patterns
    document_models =
      Enum.filter(models, fn model ->
        has_modality?(model, :input, :document) ||
          has_document_indicators?(model)
      end)

    if verbose do
      Mix.shell().info("Document-capable models:")

      Enum.each(document_models, fn model ->
        model_id = get_model_id(model)
        provider = get_model_provider(model)
        indicators = get_document_indicators(model)
        Mix.shell().info("  ✅ #{provider}:#{model_id} - #{indicators}")
      end)

      Mix.shell().info("")
    end

    %{
      total: length(document_models),
      models: document_models
    }
  end

  defp identify_multimodal_models(models) do
    models
    |> Enum.filter(fn model ->
      modalities = get_model_modalities(model)
      input_mods = Map.get(modalities, :input, [:text])
      # Multi-modal = 2+ input modalities
      length(input_mods) >= 2
    end)
    |> Enum.map(fn model ->
      model_id = get_model_id(model)
      provider = get_model_provider(model)
      modalities = get_model_modalities(model)

      %{
        id: model_id,
        provider: provider,
        input_modalities: Map.get(modalities, :input, [:text]),
        output_modalities: Map.get(modalities, :output, [:text])
      }
    end)
  end

  defp calculate_provider_stats(models) do
    models
    |> Enum.group_by(&get_model_provider/1)
    |> Enum.map(fn {provider, provider_models} ->
      vision_count = Enum.count(provider_models, &has_modality?(&1, :input, :image))
      audio_count = Enum.count(provider_models, &has_modality?(&1, :input, :audio))

      multimodal_count =
        Enum.count(provider_models, fn model ->
          modalities = get_model_modalities(model)
          input_mods = Map.get(modalities, :input, [:text])
          length(input_mods) >= 2
        end)

      {provider,
       %{
         total: length(provider_models),
         vision: vision_count,
         audio: audio_count,
         multimodal: multimodal_count
       }}
    end)
    |> Enum.into(%{})
  end

  defp print_summary(results, provider_filter) do
    Mix.shell().info("\n=== Validation Summary ===")
    Mix.shell().info("Total models analyzed: #{results.total_models}")

    if provider_filter do
      Mix.shell().info("Provider filter: #{provider_filter}")
    end

    Mix.shell().info("")

    # Vision summary
    if results.vision do
      Mix.shell().info("Vision Capabilities:")
      Mix.shell().info("  Models with vision: #{results.vision.total}")

      Mix.shell().info(
        "  Known vision models detected: #{results.vision.known_detected}/#{results.vision.total_known}"
      )

      Mix.shell().info("  Detection accuracy: #{results.vision.accuracy}%")

      if results.vision.accuracy >= 90.0 do
        Mix.shell().info("  ✅ Vision detection meets target (>90%)")
      else
        Mix.shell().info("  ⚠️  Vision detection below target (>90%)")
      end

      Mix.shell().info("")
    end

    # Audio summary
    if results.audio do
      Mix.shell().info("Audio Capabilities:")
      Mix.shell().info("  Models with audio: #{results.audio.total}")

      Mix.shell().info(
        "  Known audio models detected: #{results.audio.known_detected}/#{results.audio.total_known}"
      )

      Mix.shell().info("  Detection accuracy: #{results.audio.accuracy}%")

      if results.audio.accuracy >= 90.0 do
        Mix.shell().info("  ✅ Audio detection meets target (>90%)")
      else
        Mix.shell().info("  ⚠️  Audio detection below target (>90%)")
      end

      Mix.shell().info("")
    end

    # Document summary
    if results.document do
      Mix.shell().info("Document Processing:")
      Mix.shell().info("  Models with document capabilities: #{results.document.total}")
      Mix.shell().info("")
    end

    # Multi-modal summary
    Mix.shell().info("Multi-Modal Models:")
    Mix.shell().info("  Total multi-modal models: #{length(results.multimodal_models)}")

    if length(results.multimodal_models) > 0 do
      Mix.shell().info("\n  Top multi-modal models:")

      results.multimodal_models
      |> Enum.take(10)
      |> Enum.each(fn model ->
        input_str = Enum.map_join(model.input_modalities, ", ", &to_string/1)
        output_str = Enum.map_join(model.output_modalities, ", ", &to_string/1)
        Mix.shell().info("    #{model.provider}:#{model.id}")
        Mix.shell().info("      Input: #{input_str}")
        Mix.shell().info("      Output: #{output_str}")
      end)
    end

    Mix.shell().info("\n=== Provider Statistics ===")

    results.provider_stats
    |> Enum.sort_by(fn {provider, _} -> provider end)
    |> Enum.each(fn {provider, stats} ->
      Mix.shell().info("  #{provider}:")
      Mix.shell().info("    Total models: #{stats.total}")
      Mix.shell().info("    Vision models: #{stats.vision}")
      Mix.shell().info("    Audio models: #{stats.audio}")
      Mix.shell().info("    Multi-modal models: #{stats.multimodal}")
    end)

    Mix.shell().info("\n=== Modality Distribution ===")

    results.modality_groups
    |> Enum.sort()
    |> Enum.each(fn {{direction, modality}, count} ->
      Mix.shell().info("  #{direction} #{modality}: #{count} models")
    end)
  end

  defp export_matrix(results, path) do
    content = generate_matrix_markdown(results)

    File.write!(path, content)
    Mix.shell().info("\n✅ Modality compatibility matrix exported to: #{path}")
  end

  defp generate_matrix_markdown(results) do
    """
    # Multi-Modal Support Compatibility Matrix

    **Generated**: #{DateTime.utc_now() |> DateTime.to_string()}
    **Total Models Analyzed**: #{results.total_models}

    ## Executive Summary

    - **Vision-capable models**: #{if results.vision, do: results.vision.total, else: "N/A"}
    - **Audio-capable models**: #{if results.audio, do: results.audio.total, else: "N/A"}
    - **Document-capable models**: #{if results.document, do: results.document.total, else: "N/A"}
    - **Multi-modal models** (2+ input modalities): #{length(results.multimodal_models)}

    ## Validation Results

    ### Vision Capabilities
    #{if results.vision do
      """
      - Total vision models: #{results.vision.total}
      - Known models detected: #{results.vision.known_detected}/#{results.vision.total_known}
      - Detection accuracy: #{results.vision.accuracy}%
      - Status: #{if results.vision.accuracy >= 90.0, do: "✅ Meets target", else: "⚠️  Below target"}
      """
    else
      "Not validated"
    end}

    ### Audio Capabilities
    #{if results.audio do
      """
      - Total audio models: #{results.audio.total}
      - Known models detected: #{results.audio.known_detected}/#{results.audio.total_known}
      - Detection accuracy: #{results.audio.accuracy}%
      - Status: #{if results.audio.accuracy >= 90.0, do: "✅ Meets target", else: "⚠️  Below target"}
      """
    else
      "Not validated"
    end}

    ### Document Processing
    #{if results.document do
      "- Total document-capable models: #{results.document.total}"
    else
      "Not validated"
    end}

    ## Multi-Modal Models

    Models supporting 2 or more input modalities:

    #{Enum.map_join(results.multimodal_models, "\n", fn model ->
      input_str = Enum.map_join(model.input_modalities, ", ", &to_string/1)
      output_str = Enum.map_join(model.output_modalities, ", ", &to_string/1)
      "- **#{model.provider}:#{model.id}**\n  - Input: #{input_str}\n  - Output: #{output_str}"
    end)}

    ## Provider Statistics

    | Provider | Total Models | Vision | Audio | Multi-Modal |
    |----------|--------------|--------|-------|-------------|
    #{Enum.map_join(results.provider_stats |> Enum.sort(), "\n", fn {provider, stats} -> "| #{provider} | #{stats.total} | #{stats.vision} | #{stats.audio} | #{stats.multimodal} |" end)}

    ## Modality Distribution

    #{Enum.map_join(results.modality_groups |> Enum.sort(), "\n", fn {{direction, modality}, count} -> "- **#{direction} #{modality}**: #{count} models" end)}

    ## Notes

    This matrix was generated by validating modality metadata from the Model Registry.
    Accuracy is calculated based on known vision and audio models from major providers.

    **Prepared for**: Phase 3 Multi-Modal Implementation
    """
  end

  # Helper functions

  defp get_model_modalities(model) do
    Map.get(model, :modalities) || Map.get(model, "modalities") || %{}
  end

  defp get_model_id(model) do
    Map.get(model, :id) || Map.get(model, "id") || "unknown"
  end

  defp get_model_provider(model) do
    Map.get(model, :provider) || Map.get(model, "provider") || :unknown
  end

  defp has_modality?(model, direction, modality) do
    modalities = get_model_modalities(model)
    direction_mods = Map.get(modalities, direction, [])

    # Handle both atom and string modalities
    modality in direction_mods || to_string(modality) in direction_mods
  end

  defp has_document_indicators?(model) do
    model_id = get_model_id(model) |> String.downcase()

    description =
      (Map.get(model, :description) || Map.get(model, "description") || "") |> String.downcase()

    # Check for document-related keywords
    Enum.any?(["document", "pdf", "ocr", "vision"], fn keyword ->
      String.contains?(model_id, keyword) || String.contains?(description, keyword)
    end)
  end

  defp get_document_indicators(model) do
    has_doc_modality = has_modality?(model, :input, :document)
    has_vision = has_modality?(model, :input, :image)

    cond do
      has_doc_modality -> "document modality"
      has_vision -> "vision (potential document processing)"
      true -> "keyword match"
    end
  end

  defp count_known_models_detected(detected_models, known_model_names) do
    detected_ids =
      detected_models
      |> Enum.map(&get_model_id/1)
      |> Enum.map(&String.downcase/1)

    Enum.count(known_model_names, fn known_name ->
      known_lower = String.downcase(known_name)

      Enum.any?(detected_ids, fn detected_id ->
        String.contains?(detected_id, known_lower)
      end)
    end)
  end
end
