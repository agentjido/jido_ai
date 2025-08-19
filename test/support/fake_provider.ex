defmodule Jido.AI.Test.FakeProvider do
  @moduledoc """
  Fake provider for testing the AI interface.

  This provider can be used across test suites to simulate AI provider behavior
  without making real API calls.
  """

  @behaviour Jido.AI.Provider.Behaviour

  alias Jido.AI.Provider.Util.Options
  alias Jido.AI.{Model, Provider}

  @impl true
  def provider_info do
    %Provider{
      id: :fake,
      name: "Fake Provider",
      base_url: "https://fake.test/v1",
      env: [:fake_api_key],
      doc: "Test provider for unit tests",
      models: %{
        "fake-model" => %Model{
          provider: :fake,
          model: "fake-model",
          id: "fake-model",
          name: "Fake Model",
          attachment: false,
          reasoning: false,
          supports_temperature: true,
          tool_call: false,
          release_date: "2024-01",
          last_updated: "2024-01",
          modalities: %{input: [:text], output: [:text]},
          open_weights: false,
          limit: %{context: 128_000, output: 4096}
        }
      }
    }
  end

  @impl true
  def api_url, do: "https://fake.test/v1"

  @impl true
  def supports_json_mode?, do: true

  @impl true
  def chat_completion_opts, do: Options.default()

  @impl true
  def stream_event_type, do: :openai

  @impl true
  def generate_text(%Model{} = model, prompt, opts \\ []) do
    # Use the new implementation's option merging for testing
    merged_opts = Options.merge_model_options(__MODULE__, model, opts)
    system_prompt = Keyword.get(opts, :system_prompt)
    system_part = if system_prompt, do: "system:#{system_prompt}:", else: ""
    prompt_str = if is_list(prompt), do: "messages", else: prompt
    {:ok, "#{system_part}#{model.model}:#{prompt_str}:#{inspect(merged_opts)}"}
  end

  @impl true
  def stream_text(%Model{} = _model, _prompt, _opts \\ []) do
    {:ok, Stream.iterate(1, &(&1 + 1)) |> Stream.take(3) |> Stream.map(&"chunk_#{&1}")}
  end

  @impl true
  def generate_object(%Model{} = model, prompt, schema, opts \\ []) do
    # Use the new implementation's option merging for testing
    merged_opts = Options.merge_model_options(__MODULE__, model, opts)
    system_prompt = Keyword.get(opts, :system_prompt)
    system_part = if system_prompt, do: "system:#{system_prompt}:", else: ""
    prompt_str = if is_list(prompt), do: "messages", else: prompt

    # Generate schema-compliant fake data
    case schema.output_type do
      :object ->
        fake_object = generate_fake_object(schema.properties || [])
        {:ok, fake_object}

      :array ->
        fake_object = generate_fake_object(schema.properties || [])
        # Return array with 2 items
        {:ok, [fake_object, fake_object]}

      :enum ->
        # Return first enum value or "fake_value" if no values
        enum_value =
          case schema.enum_values do
            [first | _] -> first
            [] -> "fake_value"
          end

        {:ok, enum_value}

      :no_schema ->
        response = "#{system_part}#{model.model}:#{prompt_str}:no_schema:#{inspect(merged_opts)}"
        {:ok, response}

      _ ->
        {:ok, %{"response" => "Unknown schema type"}}
    end
  end

  # Helper function to generate fake object data based on properties
  defp generate_fake_object(properties) do
    properties
    |> Enum.reduce(%{}, fn {key, config}, acc ->
      fake_value =
        case Keyword.get(config, :type) do
          :string -> "fake_#{key}"
          :pos_integer -> 42
          :integer -> 42
          :float -> 3.14
          :boolean -> true
          {:list, :string} -> ["fake_item"]
          {:list, _} -> ["fake_item"]
          _ -> "fake_#{key}"
        end

      Map.put(acc, to_string(key), fake_value)
    end)
  end

  @impl true
  def stream_object(%Model{} = _model, _prompt, _schema, _opts \\ []) do
    fake_objects = [
      %{"partial" => "chunk_1"},
      %{"partial" => "chunk_2"},
      %{"partial" => "chunk_3", "complete" => true}
    ]

    {:ok, fake_objects |> Stream.map(& &1)}
  end
end
