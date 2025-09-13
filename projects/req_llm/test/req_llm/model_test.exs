defmodule ReqLLM.ModelTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias ReqLLM.Model

  doctest ReqLLM.Model

  setup do
    {:ok, sample_models: load_sample_models()}
  end

  describe "new/3" do
    test "creates model with required fields" do
      model = Model.new(:anthropic, "claude-3-5-sonnet")
      assert %Model{provider: :anthropic, model: "claude-3-5-sonnet", max_retries: 3} = model
      assert model.max_tokens == nil
    end

    test "creates model with runtime and metadata options" do
      model =
        Model.new(:anthropic, "claude-3-sonnet",
          max_tokens: 1000,
          max_retries: 5,
          limit: %{context: 200_000, output: 8192},
          capabilities: %{reasoning: true, tool_call: true},
          cost: %{input: 3.0, output: 15.0}
        )

      assert model.max_tokens == 1000 and model.max_retries == 5
      assert model.limit.context == 200_000 and model.capabilities.reasoning == true
      assert model.cost.input == 3.0
    end
  end

  describe "from/1 - model struct passthrough" do
    test "returns existing model unchanged" do
      original = Model.new(:anthropic, "claude-3-5-sonnet", max_tokens: 4096)
      assert {:ok, ^original} = Model.from(original)
    end
  end

  describe "from/1 - 3-tuple format" do
    test "parses basic and complex 3-tuples" do
      {:ok, model1} = Model.from({:anthropic, "claude-3-5-sonnet", []})
      assert model1.provider == :anthropic and model1.model == "claude-3-5-sonnet"
      assert model1.max_retries == 3

      {:ok, model2} =
        Model.from({:anthropic, "claude-3-5-sonnet", max_tokens: 1000})

      assert model2.max_tokens == 1000
    end

    test "rejects invalid model in 3-tuple" do
      {:error, error} = Model.from({:anthropic, :invalid, []})
      assert error.class == :validation and error.tag == :invalid_model_spec
    end
  end

  describe "from/1 - legacy 2-tuple format" do
    test "parses legacy tuple with model in options" do
      {:ok, model} = Model.from({:anthropic, model: "claude-3-5-sonnet", max_tokens: 1000})
      assert model.provider == :anthropic and model.model == "claude-3-5-sonnet"
      assert model.max_tokens == 1000
    end

    test "rejects legacy tuple with missing or invalid model" do
      {:error, error1} = Model.from({:anthropic, [max_tokens: 1000]})
      assert error1.tag == :missing_model

      {:error, error2} = Model.from({:anthropic, [model: :invalid]})
      assert error2.tag == :invalid_model_type
    end
  end

  describe "from/1 - string format" do
    test "parses provider:model strings" do
      {:ok, model1} = Model.from("anthropic:claude-3-5-sonnet")
      assert model1.provider == :anthropic and model1.model == "claude-3-5-sonnet"

      {:ok, model2} = Model.from("cloudflare-workers-ai:test-model")
      assert model2.provider == :cloudflare_workers_ai and model2.model == "test-model"
    end

    test "loads metadata when available in registry" do
      {:ok, model} = Model.from("anthropic:claude-3-5-haiku-20241022")
      assert model.provider == :anthropic and model.model == "claude-3-5-haiku-20241022"
      assert model.limit != nil and model.cost != nil and model.capabilities != nil
    end

    test "creates basic model when metadata unavailable" do
      {:ok, model} = Model.from("anthropic:nonexistent-model")
      assert model.provider == :anthropic and model.model == "nonexistent-model"
      assert model.limit == nil and model.cost == nil and model.capabilities == nil
    end

    test "rejects unknown provider and malformed strings" do
      {:error, error1} = Model.from("unknown:model")
      assert error1.tag == :invalid_provider

      malformed = ["no-colon", ":missing-provider", "provider:", "provider:model:extra", ""]

      for spec <- malformed do
        {:error, error} = Model.from(spec)

        assert error.class == :validation and
                 error.tag in [:invalid_model_spec, :invalid_provider]
      end
    end
  end

  describe "from/1 - error cases" do
    test "rejects invalid input types" do
      for input <- [123, [], %{}, nil, self()] do
        {:error, error} = Model.from(input)
        assert error.class == :validation and error.tag == :invalid_model_spec
      end
    end
  end

  describe "from!/1" do
    test "returns model on success and raises on error" do
      model = Model.from!("anthropic:claude-3-5-sonnet")
      assert model.provider == :anthropic and model.model == "claude-3-5-sonnet"

      assert_raise ReqLLM.Error.Validation.Error, fn -> Model.from!("invalid:provider") end
      assert_raise ReqLLM.Error.Validation.Error, fn -> Model.from!(123) end
    end
  end

  describe "valid?/1" do
    test "validates correct and rejects invalid models" do
      valid_models = [
        Model.new(:anthropic, "claude-3-5-sonnet"),
        Model.new(:openai, "gpt-4", temperature: 0.7),
        %Model{provider: :anthropic, model: "test", max_retries: 0}
      ]

      assert Enum.all?(valid_models, &Model.valid?/1)

      invalid_models = [
        # Not a Model struct
        %{provider: :anthropic, model: "test"},
        # Provider not atom
        %Model{provider: "anthropic", model: "test", max_retries: 3},
        # Model not string
        %Model{provider: :anthropic, model: :test, max_retries: 3},
        # Empty model
        %Model{provider: :anthropic, model: "", max_retries: 3},
        # Negative retries
        %Model{provider: :anthropic, model: "test", max_retries: -1},
        # Retries not integer
        %Model{provider: :anthropic, model: "test", max_retries: "3"}
      ]

      refute Enum.any?(invalid_models, &Model.valid?/1)
    end
  end

  describe "with_defaults/1" do
    test "adds default metadata and preserves existing" do
      model = Model.new(:anthropic, "claude-3-5-sonnet")
      result = Model.with_defaults(model)

      assert result.limit == %{context: 128_000, output: 4_096}
      assert result.modalities == %{input: [:text], output: [:text]}

      assert result.capabilities == %{
               reasoning: false,
               tool_call: false,
               temperature: true,
               attachment: false
             }

      # Test merging with existing metadata
      model_with_partial =
        Model.new(:anthropic, "claude-3-sonnet",
          limit: %{context: 200_000, output: 8192},
          capabilities: %{reasoning: true}
        )

      merged = Model.with_defaults(model_with_partial)

      # Preserved
      assert merged.limit.context == 200_000
      # Preserved
      assert merged.capabilities.reasoning == true
      # Added default
      assert merged.capabilities.temperature == true
    end
  end

  describe "with_metadata/1" do
    test "loads full metadata from JSON files" do
      {:ok, model} = Model.with_metadata("anthropic:claude-3-5-haiku-20241022")
      assert model.provider == :anthropic and model.model == "claude-3-5-haiku-20241022"
      assert is_map(model.limit) and is_map(model.cost)
      assert is_map(model.capabilities) and is_map(model.modalities)
    end

    test "returns error for nonexistent model and provider" do
      {:error, reason1} = Model.with_metadata("anthropic:totally-fake-model")
      assert is_binary(reason1) and String.contains?(reason1, "not found")

      {:error, _reason2} = Model.with_metadata("fake-provider:model")
    end
  end

  describe "comprehensive model parsing" do
    @tag timeout: 30_000
    test "all sample models parse successfully", %{sample_models: models} do
      capture_io(fn ->
        capture_log(fn ->
          {failures, success_count} =
            Enum.reduce(models, {[], 0}, fn {provider, model_data}, {fails, count} ->
              spec = "#{provider}:#{model_data["id"]}"

              case Model.from(spec) do
                {:ok, parsed} when is_struct(parsed, Model) ->
                  if Model.valid?(parsed),
                    do: {fails, count + 1},
                    else: {[{spec, "validation failed"} | fails], count + 1}

                {:error, reason} ->
                  {[{spec, inspect(reason)} | fails], count + 1}
              end
            end)

          success_rate = success_count / (success_count + length(failures)) * 100

          if failures != [] do
            IO.puts("\n=== FAILED MODELS (#{length(failures)}) ===")
            Enum.each(failures, fn {spec, reason} -> IO.puts("#{spec}: #{reason}") end)
          end

          IO.puts(
            "Parse success rate: #{Float.round(success_rate, 1)}% (#{success_count} successful)"
          )

          assert success_rate >= 95.0, "Parse success rate too low: #{success_rate}%"
        end)
      end)
    end

    test "models with metadata have proper field types", %{sample_models: models} do
      models_with_metadata =
        models
        |> Enum.take(20)
        |> Enum.map(fn {provider, data} ->
          {"#{provider}:#{data["id"]}", Model.from!("#{provider}:#{data["id"]}")}
        end)
        |> Enum.filter(fn {_, model} -> model.cost != nil or model.limit != nil end)

      for {spec, model} <- models_with_metadata do
        # Validate cost structure
        if model.cost do
          assert is_map(model.cost), "#{spec}: cost should be map"
          assert is_number(Map.get(model.cost, :input, 0)), "#{spec}: cost.input should be number"

          assert is_number(Map.get(model.cost, :output, 0)),
                 "#{spec}: cost.output should be number"
        end

        # Validate limit structure
        if model.limit do
          assert is_map(model.limit), "#{spec}: limit should be map"

          assert is_integer(Map.get(model.limit, :context, 0)),
                 "#{spec}: limit.context should be integer"

          assert is_integer(Map.get(model.limit, :output, 0)),
                 "#{spec}: limit.output should be integer"
        end

        # Validate capabilities structure
        if model.capabilities do
          assert is_map(model.capabilities), "#{spec}: capabilities should be map"

          for key <- [:reasoning, :tool_call, :temperature, :attachment] do
            assert is_boolean(Map.get(model.capabilities, key, false)),
                   "#{spec}: #{key} should be boolean"
          end
        end

        # Validate modalities structure
        if model.modalities do
          assert is_map(model.modalities), "#{spec}: modalities should be map"

          assert is_list(Map.get(model.modalities, :input, [])),
                 "#{spec}: modalities.input should be list"

          assert is_list(Map.get(model.modalities, :output, [])),
                 "#{spec}: modalities.output should be list"
        end
      end

      assert not Enum.empty?(models_with_metadata), "Should have models with metadata"
    end

    test "provider name parsing handles hyphens correctly" do
      hyphenated_providers = [
        {"cloudflare-workers-ai", :cloudflare_workers_ai},
        {"google-vertex", :google_vertex},
        {"amazon-bedrock", :amazon_bedrock}
      ]

      for {hyphenated, expected_atom} <- hyphenated_providers do
        {:ok, model} = Model.from("#{hyphenated}:test-model")
        assert model.provider == expected_atom
      end
    end
  end

  # Helper to load a sample of models for testing
  defp load_sample_models do
    priv_dir = Application.app_dir(:req_llm, "priv")
    models_dir = Path.join(priv_dir, "models_dev")

    case File.ls(models_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        # Sample files for performance
        |> Enum.take(5)
        |> Enum.flat_map(&load_models_from_file(models_dir, &1))
        # Limit total models
        |> Enum.take(50)

      {:error, _} ->
        []
    end
  end

  defp load_models_from_file(models_dir, filename) do
    provider_atom =
      filename |> String.trim_trailing(".json") |> String.replace("-", "_") |> String.to_atom()

    file_path = Path.join(models_dir, filename)

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"models" => models}} ->
            models |> Enum.take(10) |> Enum.map(&{provider_atom, &1})

          {:ok, single_model} ->
            [{provider_atom, single_model}]

          {:error, _} ->
            []
        end

      {:error, _} ->
        []
    end
  end
end
