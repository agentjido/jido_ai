defmodule JidoAi.Actions.Anthropic do
  @moduledoc """
  A collection of actions for working with the Instructor library.
  """

  defmodule ChatCompletion do
    @moduledoc """
    A low-level thunk that provides direct access to Instructor's chat completion functionality.
    Supports most Instructor options
    """
    use Jido.Action,
      name: "instructor_raw",
      description: "Makes a raw chat completion call using Instructor",
      schema: [
        model: [
          type: :string,
          required: true,
          doc: "The model to use (e.g., claude-3-5-haiku-latest)"
        ],
        messages: [type: {:list, :map}, required: true, doc: "The conversation messages"],
        response_model: [type: :any, required: true, doc: "Ecto schema or type definition"],
        # Not Supported Yet
        # stream: [type: :boolean, default: false, doc: "Whether to stream the response"],
        # partial: [type: :boolean, default: false, doc: "Whether to use partial streaming mode"],
        max_retries: [
          type: :integer,
          default: 0,
          doc: "Number of retries for validation failures"
        ],
        temperature: [type: :float, default: 0.7, doc: "Temperature for response randomness"],
        max_tokens: [type: :integer, default: 1000, doc: "Maximum tokens in response"],
        top_p: [type: :float, doc: "Top p sampling parameter"],
        stop: [type: {:list, :string}, doc: "Stop sequences"],
        timeout: [type: :integer, default: 30_000, doc: "Request timeout in milliseconds"]
      ]

    @models [
      "claude-3-5-sonnet-20241022",
      "claude-3-5-sonnet-latest",
      "claude-3-5-haiku-20241022",
      "claude-3-5-haiku-latest",
      "claude-3-opus-20240229",
      "claude-3-opus-latest",
      "claude-3-sonnet-20240229",
      "claude-3-haiku-20240307"
    ]

    def models, do: @models

    @impl true
    def on_before_validate_params(params) do
      # Validate the existence of an API key
      case Application.get_env(:instructor, :anthropic) do
        [api_key: key] when is_binary(key) and key != "" ->
          {:ok, params}

        _ ->
          {:error, "Anthropic API key is not properly configured"}
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
            partial: false
          },
          params
        )

      opts =
        [
          model: params.model,
          messages: params.messages,
          response_model: get_response_model(params_with_defaults),
          temperature: params.temperature,
          max_tokens: params.max_tokens,
          max_retries: params.max_retries,
          timeout: params.timeout
        ]
        |> add_if_present(:top_p, params_with_defaults.top_p)
        |> add_if_present(:stop, params_with_defaults.stop)

      case Instructor.chat_completion(opts) do
        {:ok, response} ->
          {:ok, %{result: response}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    # Helper to handle array and partial response models
    defp get_response_model(%{response_model: model, stream: true, partial: true}),
      do: {:partial, model}

    defp get_response_model(%{response_model: model, stream: true}),
      do: {:array, model}

    defp get_response_model(%{response_model: model}),
      do: model

    defp add_if_present(opts, _key, nil), do: opts
    defp add_if_present(opts, key, value), do: Keyword.put(opts, key, value)
  end
end
