defmodule Jido.AI.Actions.OpenaiEx.ResponseRetrieve do
  use Jido.Action,
    name: "openai_ex_response_retrieve",
    description: "Retrieve an asynchronous response using OpenAI Ex",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc: "The AI model to use (e.g., {:openai, [model: \"gpt-4\"]} or %Jido.AI.Model{})"
      ],
      response_id: [
        type: :string,
        required: true,
        doc: "The ID of the response to retrieve"
      ]
    ]

  require Logger
  alias Jido.AI.Model
  alias OpenaiEx.Responses

  @valid_providers [:openai]

  @doc """
  Retrieves an asynchronous response using OpenAI Responses API.

  ## Parameters
    - params: Map containing:
      - model: Either a %Jido.AI.Model{} struct or a tuple of {provider, opts}
      - response_id: The ID of the response to retrieve
    - context: The action context containing state and other information

  ## Returns
    - {:ok, %{
        id: response_id,
        model: model_name,
        content: response_content,
        tool_results: [optional_tool_results],
        status: "completed" | "processing" | "error",
        created_at: timestamp
      }} on success
    - {:error, reason} on failure
  """
  def run(params, context) do
    Logger.info("Retrieving OpenAI Ex response with params: #{inspect(params)}")
    Logger.info("Context: #{inspect(context)}")

    with {:ok, model} <- validate_and_get_model(params),
         {:ok, response_id} <- validate_response_id(params) do
      case make_request(model, response_id) do
        {:ok, response} ->
          format_response(response)

        error ->
          error
      end
    end
  end

  # Private functions

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

  defp validate_provider(%Model{provider: provider} = model) when provider in @valid_providers do
    {:ok, model}
  end

  defp validate_provider(%Model{provider: provider}) do
    {:error,
     "Invalid provider: #{inspect(provider)}. Must be one of: #{inspect(@valid_providers)}"}
  end

  defp validate_response_id(%{response_id: response_id})
       when is_binary(response_id) and response_id != "" do
    {:ok, response_id}
  end

  defp validate_response_id(%{response_id: response_id}) when is_binary(response_id) do
    {:error, "Response ID cannot be empty"}
  end

  defp validate_response_id(_) do
    {:error, "Response ID is required and must be a string"}
  end

  defp make_request(model, response_id) do
    client =
      OpenaiEx.new(model.api_key)
      |> maybe_add_base_url(model)
      |> maybe_add_headers(model)

    Responses.retrieve(client, response_id)
  end

  defp maybe_add_base_url(client, %Model{base_url: base_url}) when is_binary(base_url) do
    OpenaiEx.with_base_url(client, base_url)
  end

  defp maybe_add_base_url(client, _), do: client

  defp maybe_add_headers(client, %{headers: headers})
       when is_map(headers) and map_size(headers) > 0 do
    OpenaiEx.with_additional_headers(client, headers)
  end

  defp maybe_add_headers(client, _), do: client

  defp format_response(response) do
    # Extract main content (message text)
    content =
      case response["content"] do
        [%{"text" => %{"value" => value}} | _] -> value
        _ -> nil
      end

    # Extract tool results if available
    tool_results =
      response["tool_outputs"] || []

    # Format the response
    formatted_response = %{
      id: response["id"],
      model: response["model"],
      content: content,
      status: response["status"],
      created_at: response["created_at"]
    }

    # Add tool results if present
    formatted_response =
      if Enum.empty?(tool_results) do
        formatted_response
      else
        Map.put(formatted_response, :tool_results, tool_results)
      end

    {:ok, formatted_response}
  end
end
