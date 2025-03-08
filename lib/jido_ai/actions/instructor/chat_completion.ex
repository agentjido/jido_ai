defmodule Jido.AI.Actions.Instructor.ChatCompletion do
  @moduledoc """
  A low-level thunk that provides direct access to Instructor's chat completion functionality.
  Supports most Instructor options and integrates with Jido's Model and Prompt structures.
  """
  use Jido.Action,
    name: "instructor_chat_completion",
    description: "Makes a raw chat completion call using Instructor with structured prompting",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc:
          "The AI model to use (e.g., {:anthropic, [model_id: \"claude-3-sonnet-20240229\"]} or %Jido.AI.Model{})"
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: true,
        doc: "The prompt to use for the response"
      ],
      response_model: [
        type: :any,
        required: true,
        doc: "Ecto schema or type definition for structured response"
      ],
      max_retries: [
        type: :integer,
        default: 0,
        doc: "Number of retries for validation failures"
      ],
      temperature: [type: :float, default: 0.7, doc: "Temperature for response randomness"],
      max_tokens: [type: :integer, default: 1000, doc: "Maximum tokens in response"],
      top_p: [type: :float, doc: "Top p sampling parameter"],
      stop: [type: {:list, :string}, doc: "Stop sequences"],
      timeout: [type: :integer, default: 60_000, doc: "Request timeout in milliseconds"]
    ]

  alias Jido.AI.Model
  alias Jido.AI.Prompt
  require Logger

  @impl true
  def on_before_validate_params(params) do
    Logger.info("ChatCompletion validation params: #{inspect(params)}")

    with {:ok, model} <- validate_model(params.model),
         {:ok, prompt} <- Prompt.validate_prompt_opts(params.prompt) do
      {:ok, %{params | model: model, prompt: prompt}}
    else
      {:error, reason} ->
        Logger.error("ChatCompletion validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def run(params, _context) do
    # Create a map with all optional parameters set to nil by default
    params_with_defaults =
      Map.merge(
        %{
          top_p: nil,
          stop: nil,
          stream: false,
          partial: false,
          max_retries: 0,
          temperature: 0.7,
          max_tokens: 1000
        },
        params
      )

    # Get the rendered messages from the prompt and convert role atoms to strings
    messages =
      Prompt.render(params.prompt)
      |> Enum.map(fn msg -> %{msg | role: Atom.to_string(msg.role)} end)

    # Build the Instructor options
    model_id = get_model_id(params.model)

    # Configure Instructor with the appropriate adapter and API key
    config = [
      adapter: Instructor.Adapters.Anthropic,
      api_key: params.model.api_key
    ]

    opts =
      [
        model: model_id,
        messages: messages,
        response_model: get_response_model(params_with_defaults),
        temperature: params_with_defaults.temperature,
        max_tokens: params_with_defaults.max_tokens,
        max_retries: params_with_defaults.max_retries,
        stream: params_with_defaults.stream
      ]
      |> add_if_present(:top_p, params_with_defaults.top_p)
      |> add_if_present(:stop, params_with_defaults.stop)

    case Instructor.chat_completion(opts, config) do
      {:ok, response} ->
        {:ok, %{result: response}, %{}}

      {:error, reason} ->
        Logger.error("Chat completion failed: #{inspect(reason)}")
        {:error, reason, %{}}

      nil ->
        Logger.error("Chat completion returned nil")
        {:error, "Instructor chat completion returned nil", %{}}

      other ->
        Logger.error("Unexpected response: #{inspect(other)}")
        {:error, "Unexpected response from Instructor: #{inspect(other)}", %{}}
    end
  end

  # Helper to validate model input
  defp validate_model(%Model{} = model), do: {:ok, model}

  defp validate_model(spec) when is_tuple(spec), do: Model.from(spec)

  defp validate_model(other) do
    Logger.error("Invalid model specification: #{inspect(other)}")
    {:error, "Invalid model specification: #{inspect(other)}"}
  end

  # Helper to get the model ID from our Model struct
  defp get_model_id(%Model{model_id: model_id}), do: model_id
  defp get_model_id(_), do: nil

  # Helper to handle array and partial response models
  defp get_response_model(%{response_model: model, stream: true, partial: true}),
    do: {:partial, model}

  defp get_response_model(%{response_model: model, stream: true}), do: {:array, model}
  defp get_response_model(%{response_model: model}), do: model

  defp add_if_present(opts, _key, nil), do: opts
  defp add_if_present(opts, key, value), do: Keyword.put(opts, key, value)
end
