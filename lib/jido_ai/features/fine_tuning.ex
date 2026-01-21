defmodule Jido.AI.Features.FineTuning do
  @moduledoc """
  Fine-tuned model detection and management.

  Provides utilities for working with fine-tuned model variants,
  including model ID parsing, base model resolution, and discovery.

  ## Supported Providers

  - **OpenAI**: Fine-tuned models with `ft:` prefix
  - **Google**: Vertex AI fine-tuned models with `/models/` path
  - **Cohere**: Custom model endpoints
  - **Together**: Fine-tuned variants

  ## Model ID Formats

  Different providers use different naming schemes:

  - **OpenAI**: `ft:gpt-4-0613:org:suffix:id`
  - **Google**: `projects/PROJECT/locations/LOCATION/models/MODEL`
  - **Cohere**: Custom endpoint URLs
  - **Together**: Model names with organization prefix

  ## Usage

      # Check if model is fine-tuned
      FineTuning.is_fine_tuned?(model)

      # Parse fine-tuned model ID
      {:ok, info} = FineTuning.parse_model_id(model_id)

      # Get base model
      {:ok, base} = FineTuning.get_base_model(model)
  """

  alias Jido.AI.Model

  # Validation limits
  @max_model_id_length 512

  @type fine_tune_info :: %{
          provider: atom(),
          base_model: String.t(),
          organization: String.t() | nil,
          suffix: String.t() | nil,
          fine_tune_id: String.t()
        }

  @doc """
  Check if a model is a fine-tuned variant.

  Determines if a model ID represents a custom fine-tuned model
  rather than a base provider model.

  ## Parameters
    - model: Jido.AI.Model struct or model ID string

  ## Returns
    Boolean indicating if model is fine-tuned

  ## Examples

      iex> FineTuning.fine_tuned?("ft:gpt-4-0613:org:suffix:id")
      true

      iex> FineTuning.fine_tuned?("gpt-4")
      false
  """
  @spec fine_tuned?(Model.t() | String.t()) :: boolean()
  def fine_tuned?(%Model{model: model_id, provider: provider}) do
    case provider do
      :openai ->
        String.starts_with?(model_id, "ft:")

      :google ->
        String.contains?(model_id, "/models/") and String.contains?(model_id, "projects/")

      :cohere ->
        String.starts_with?(model_id, "custom-")

      :together ->
        String.contains?(model_id, "/")

      _ ->
        false
    end
  end

  def fine_tuned?(model_id) when is_binary(model_id) do
    cond do
      String.starts_with?(model_id, "ft:") -> true
      String.contains?(model_id, "projects/") and String.contains?(model_id, "/models/") -> true
      String.starts_with?(model_id, "custom-") -> true
      true -> false
    end
  end

  @doc """
  Parse a fine-tuned model ID into components.

  Extracts base model, organization, suffix, and fine-tune ID from
  provider-specific model ID formats.

  ## Parameters
    - model_id: Model ID string
    - provider: Provider atom

  ## Returns
    - `{:ok, fine_tune_info}` with parsed components
    - `{:error, :not_fine_tuned}` if not a fine-tuned model
    - `{:error, :invalid_format}` if parsing fails

  ## Examples

      iex> FineTuning.parse_model_id("ft:gpt-4-0613:org:suffix:id", :openai)
      {:ok, %{base_model: "gpt-4-0613", organization: "org", ...}}
  """
  @spec parse_model_id(String.t(), atom()) :: {:ok, fine_tune_info()} | {:error, atom()}
  def parse_model_id(model_id, provider) when is_binary(model_id) do
    with :ok <- validate_model_id(model_id) do
      do_parse_model_id(model_id, provider)
    end
  end

  def parse_model_id(_model_id, _provider), do: {:error, :invalid_model_id}

  defp do_parse_model_id(model_id, :openai) do
    if String.starts_with?(model_id, "ft:") do
      # Format: ft:BASE_MODEL:ORG:SUFFIX:ID
      parts = String.split(model_id, ":")

      case parts do
        ["ft", base_model, org, suffix, id] ->
          {:ok,
           %{
             provider: :openai,
             base_model: base_model,
             organization: org,
             suffix: suffix,
             fine_tune_id: id
           }}

        ["ft", base_model, org, id] ->
          {:ok,
           %{
             provider: :openai,
             base_model: base_model,
             organization: org,
             suffix: nil,
             fine_tune_id: id
           }}

        _ ->
          {:error, :invalid_format}
      end
    else
      {:error, :not_fine_tuned}
    end
  end

  defp do_parse_model_id(model_id, :google) do
    # Format: projects/PROJECT/locations/LOCATION/models/MODEL
    if String.contains?(model_id, "projects/") and String.contains?(model_id, "/models/") do
      parts = String.split(model_id, "/")
      model_name = List.last(parts)

      {:ok,
       %{
         provider: :google,
         base_model: extract_google_base_model(model_name),
         organization: Enum.at(parts, 1),
         suffix: nil,
         fine_tune_id: model_name
       }}
    else
      {:error, :not_fine_tuned}
    end
  end

  defp do_parse_model_id(model_id, :cohere) do
    if String.starts_with?(model_id, "custom-") do
      {:ok,
       %{
         provider: :cohere,
         base_model: "command",
         # Default assumption
         organization: nil,
         suffix: nil,
         fine_tune_id: model_id
       }}
    else
      {:error, :not_fine_tuned}
    end
  end

  defp do_parse_model_id(model_id, :together) do
    if String.contains?(model_id, "/") do
      [org | rest] = String.split(model_id, "/")
      model_name = Enum.join(rest, "/")

      {:ok,
       %{
         provider: :together,
         base_model: model_name,
         organization: org,
         suffix: nil,
         fine_tune_id: model_id
       }}
    else
      {:error, :not_fine_tuned}
    end
  end

  defp do_parse_model_id(_model_id, _provider) do
    {:error, :not_fine_tuned}
  end

  @doc """
  Get the base model for a fine-tuned model.

  Resolves the underlying base model that was fine-tuned.

  ## Parameters
    - model: Jido.AI.Model struct

  ## Returns
    - `{:ok, base_model_id}` on success
    - `{:error, :not_fine_tuned}` if not a fine-tuned model

  ## Examples

      iex> FineTuning.get_base_model(fine_tuned_model)
      {:ok, "gpt-4-0613"}
  """
  @spec get_base_model(Model.t()) :: {:ok, String.t()} | {:error, atom()}
  def get_base_model(%Model{model: model_id, provider: provider} = _model) do
    case parse_model_id(model_id, provider) do
      {:ok, %{base_model: base}} -> {:ok, base}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Discover fine-tuned models for a provider.

  Lists available fine-tuned models (requires API access).

  Note: This is a placeholder. Actual implementation would require
  API calls to list fine-tuned models, which is provider-specific.

  ## Parameters
    - provider: Provider atom
    - api_key: API key for authentication

  ## Returns
    - `{:ok, [model_ids]}` on success
    - `{:error, reason}` on failure

  ## Examples

      iex> FineTuning.discover(:openai, api_key)
      {:ok, ["ft:gpt-4:org:model1:id1", "ft:gpt-4:org:model2:id2"]}
  """
  @spec discover(atom(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def discover(_provider, _api_key) do
    # Placeholder - would need actual API integration
    {:error, :not_implemented}
  end

  @doc """
  Check if fine-tuned model has specific capabilities.

  Fine-tuned models generally inherit capabilities from their base model.

  ## Parameters
    - model: Jido.AI.Model struct
    - capability: Capability atom

  ## Returns
    Boolean indicating if capability is supported

  ## Examples

      iex> FineTuning.supports_capability?(model, :streaming)
      true  # Inherited from base model
  """
  @spec supports_capability?(Model.t(), atom()) :: boolean()
  def supports_capability?(%Model{} = model, capability) do
    # Fine-tuned models inherit capabilities from base model
    case get_base_model(model) do
      {:ok, base_model_id} ->
        # Check if base model supports the capability
        # This would integrate with the main capability system
        case Model.from("#{model.provider}:#{base_model_id}") do
          {:ok, base_model} ->
            # Use ReqLLM's capability system
            ReqLLM.Capability.supports?(base_model, capability)

          {:error, _} ->
            false
        end

      {:error, _} ->
        # Not a fine-tuned model, check directly
        false
    end
  end

  # Private helpers

  # Validation

  defp validate_model_id(model_id) when is_binary(model_id) do
    cond do
      String.length(model_id) == 0 ->
        {:error, :empty_model_id}

      String.length(model_id) > @max_model_id_length ->
        {:error,
         "Model ID too long: maximum is #{@max_model_id_length} characters, got #{String.length(model_id)}"}

      not String.match?(model_id, ~r/^[a-zA-Z0-9:_\-\/\.]+$/) ->
        {:error, "Model ID contains invalid characters"}

      true ->
        :ok
    end
  end

  defp validate_model_id(_), do: {:error, :invalid_model_id}

  # Helper functions

  defp extract_google_base_model(model_name) do
    # Google fine-tuned models often have base model in the name
    cond do
      String.contains?(model_name, "gemini") -> "gemini-pro"
      String.contains?(model_name, "text-bison") -> "text-bison"
      String.contains?(model_name, "chat-bison") -> "chat-bison"
      true -> "unknown"
    end
  end
end
