defmodule Jido.AI.Model.ModalityValidationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Model.Registry

  @moduletag :modality_validation

  describe "modality detection" do
    test "detects vision-capable models" do
      {:ok, models} = Registry.discover_models(modality: :image)

      assert length(models) > 0, "Should find vision-capable models"

      # Verify models have image in input modalities
      Enum.each(models, fn model ->
        modalities = Map.get(model, :modalities, %{})
        input_mods = Map.get(modalities, :input, [])

        assert :image in input_mods or "image" in input_mods,
               "Vision model #{model.id} should have image in input modalities"
      end)
    end

    test "detects audio-capable models" do
      {:ok, models} = Registry.discover_models(modality: :audio)

      # Audio models may or may not exist depending on providers
      if length(models) > 0 do
        # Verify models have audio in input modalities
        Enum.each(models, fn model ->
          modalities = Map.get(model, :modalities, %{})
          input_mods = Map.get(modalities, :input, [])

          assert :audio in input_mods or "audio" in input_mods,
                 "Audio model #{model.id} should have audio in input modalities"
        end)
      end
    end

    test "detects text-only models" do
      {:ok, all_models} = Registry.list_models()
      {:ok, text_models} = Registry.discover_models(modality: :text)

      assert length(text_models) > 0, "Should find text-only models"
      # Most models should support text
      assert length(text_models) >= length(all_models) * 0.8,
             "Most models should support text input"
    end

    test "multi-modal models have multiple input modalities" do
      {:ok, all_models} = Registry.list_models()

      multimodal_models =
        Enum.filter(all_models, fn model ->
          modalities = Map.get(model, :modalities, %{})
          input_mods = Map.get(modalities, :input, [:text])
          length(input_mods) >= 2
        end)

      # Verify multi-modal models
      if length(multimodal_models) > 0 do
        Enum.each(multimodal_models, fn model ->
          modalities = Map.get(model, :modalities, %{})
          input_mods = Map.get(modalities, :input, [])

          assert length(input_mods) >= 2,
                 "Multi-modal model #{model.id} should have 2+ input modalities"
        end)
      end
    end
  end

  describe "modality metadata structure" do
    test "models have properly formatted modalities field" do
      {:ok, models} = Registry.list_models()

      # Sample a few models
      sample_models = Enum.take(models, 10)

      Enum.each(sample_models, fn model ->
        modalities = Map.get(model, :modalities)

        if modalities do
          assert is_map(modalities), "Modalities should be a map for #{model.id}"

          input_mods = Map.get(modalities, :input)
          output_mods = Map.get(modalities, :output)

          if input_mods do
            assert is_list(input_mods), "Input modalities should be a list for #{model.id}"
          end

          if output_mods do
            assert is_list(output_mods), "Output modalities should be a list for #{model.id}"
          end
        end
      end)
    end

    test "known vision models are detected correctly" do
      known_vision_keywords = [
        "vision",
        "gpt-4o",
        "claude-3",
        "gemini-1.5",
        "gemini-2.0",
        "nova"
      ]

      {:ok, vision_models} = Registry.discover_models(modality: :image)
      vision_ids = Enum.map(vision_models, & &1.id) |> Enum.map(&String.downcase/1)

      # At least some known vision models should be detected
      detected_keywords =
        Enum.count(known_vision_keywords, fn keyword ->
          Enum.any?(vision_ids, &String.contains?(&1, keyword))
        end)

      assert detected_keywords > 0,
             "Should detect at least some known vision model patterns"
    end
  end

  describe "modality filtering" do
    test "filtering by modality returns only matching models" do
      {:ok, vision_models} = Registry.discover_models(modality: :image)

      # All returned models should support image input
      Enum.each(vision_models, fn model ->
        modalities = Map.get(model, :modalities, %{})
        input_mods = Map.get(modalities, :input, [])

        has_image = :image in input_mods or "image" in input_mods

        assert has_image,
               "Filtered model #{model.id} should have image modality"
      end)
    end

    test "handles missing modalities gracefully" do
      # Should not crash when models lack modality data
      assert {:ok, _models} = Registry.discover_models(modality: :text)
    end
  end
end
