defmodule Jido.Tools.AI.GenerateObject do
  @moduledoc """
  Generates structured objects using AI models with full validation and error handling.

  Simple action wrapper around Jido.AI.generate_object/4 that provides
  validated parameters and structured responses.

  ## Parameters

  - `:messages` (required) - Text prompt or list of Message structs
  - `:object_schema` (required) - Keyword list defining the object structure
  - `:model` - AI model specification (default: "openai:gpt-4o")
  - `:output_type` - Type of output to generate (:object, :array, :enum, :no_schema)
  - `:enum_values` - List of allowed values when output_type is :enum
  - `:temperature` - Temperature for randomness (0.0-2.0)
  - `:max_tokens` - Maximum tokens to generate
  - `:system_prompt` - Optional system prompt
  - `:actions` - List of Jido Action modules for tools

  ## Examples

      # Basic usage
      {:ok, result} = Jido.Exec.run(GenerateObject, %{
        messages: "Generate a person profile",
        object_schema: [
          name: [type: :string, required: true],
          age: [type: :integer, required: true]
        ]
      })
      result.response  #=> %{name: "John Doe", age: 30}

      # With actions
      {:ok, result} = Jido.Exec.run(GenerateObject, %{
        messages: "Calculate and format result",
        object_schema: [value: [type: :number, required: true]],
        actions: [Calculator]
      })
  """

  use Jido.Action,
    name: "generate_object",
    description: "Generates structured objects using AI models",
    schema: [
      messages: [
        type: :any,
        required: true,
        doc: "Text prompt or list of Message structs"
      ],
      # Validated by Jido.AI.Messages.validate/1 in generate_object
      object_schema: [
        type: :keyword_list,
        required: true,
        doc: "Keyword list defining the object structure"
      ],
      model: [
        type: :string,
        default: "openai:gpt-4o",
        doc: "AI model specification"
      ],
      output_type: [
        type: {:in, [:object, :array, :enum, :no_schema]},
        default: :object,
        doc: "Type of output to generate"
      ],
      enum_values: [
        type: {:list, :string},
        default: [],
        doc: "List of allowed values when output_type is :enum"
      ],
      temperature: [
        type: {:custom, Jido.AI.Util, :validate_temperature, []},
        doc: "Temperature for randomness (0.0-2.0)"
      ],
      max_tokens: [
        type: :pos_integer,
        doc: "Maximum tokens to generate"
      ],
      system_prompt: [
        type: {:or, [:string, nil]},
        doc: "Optional system prompt"
      ],
      actions: [
        type: {:custom, Jido.Util, :validate_actions, []},
        default: [],
        doc: "List of Jido Action modules for tools"
      ]
    ]

  import Jido.AI.Util, only: [maybe_put: 3]

  # Override macro-generated specs to match actual implementation
  @spec on_before_validate_params(map()) :: {:ok, map()}
  @spec on_after_validate_params(map()) :: {:ok, map()}
  @spec on_before_validate_output(map()) :: {:ok, map()}
  @spec on_after_validate_output(map()) :: {:ok, map()}
  @spec on_after_run({:ok, map()} | {:error, any()}) :: {:ok, {:ok, map()} | {:error, any()}}
  @spec on_error(map(), any(), map(), keyword()) :: {:ok, map()}

  @impl true
  @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
  def run(%{messages: messages, object_schema: object_schema, model: model} = params, _ctx) do
    # Build options from parameters
    opts =
      []
      |> maybe_put(:output_type, Map.get(params, :output_type))
      |> maybe_put(:enum_values, Map.get(params, :enum_values))
      |> maybe_put(:temperature, Map.get(params, :temperature))
      |> maybe_put(:max_tokens, Map.get(params, :max_tokens))
      |> maybe_put(:system_prompt, Map.get(params, :system_prompt))
      |> maybe_put(:actions, Map.get(params, :actions, []))

    with {:ok, response} <- Jido.AI.generate_object(model, messages, object_schema, opts) do
      {:ok, Map.put(params, :response, response)}
    end
  end
end
