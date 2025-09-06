defmodule ReqAI.Provider do
  @moduledoc """
  Simple provider struct for ReqAI providers.

  Represents an AI provider with basic configuration. Simplified version
  of the jido_ai Provider without environment variable handling or Keyring integration.
  """
  use TypedStruct

  @doc """
  Defines the behavior for AI provider modules.

  All provider modules must implement these callbacks to provide a consistent
  interface for AI text generation.
  """
  @callback provider_info() :: t()
  @callback generate_text(ReqAI.Model.t(), String.t() | [ReqAI.Message.t()], keyword()) ::
              {:ok, String.t()} | {:error, ReqAI.Error.t()}
  @callback stream_text(ReqAI.Model.t(), String.t() | [ReqAI.Message.t()], keyword()) ::
              {:ok, Enumerable.t()} | {:error, ReqAI.Error.t()}

  typedstruct do
    field(:id, atom(), enforce: true)
    field(:name, String.t(), enforce: true)
    field(:base_url, String.t(), enforce: true)
    field(:models, %{String.t() => ReqAI.Model.t()}, default: %{})
  end

  @doc """
  Creates a new provider struct.

  ## Parameters

  - `id` - The provider identifier (atom)
  - `name` - The provider display name (string)
  - `base_url` - The API base URL (string)
  - `models` - A map of model ID to Model structs (optional, defaults to empty map)

  ## Examples

      iex> ReqAI.Provider.new(:anthropic, "Anthropic", "https://api.anthropic.com")
      %ReqAI.Provider{id: :anthropic, name: "Anthropic", base_url: "https://api.anthropic.com", models: %{}}

  """
  @spec new(atom(), String.t(), String.t(), %{String.t() => ReqAI.Model.t()}) :: t()
  def new(id, name, base_url, models \\ %{}) do
    %__MODULE__{
      id: id,
      name: name,
      base_url: base_url,
      models: models
    }
  end
end
