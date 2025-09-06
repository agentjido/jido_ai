defmodule ReqAI.Provider.Spec do
  @moduledoc """
  Provider specification struct defining provider metadata and configuration.
  """

  use TypedStruct

  typedstruct do
    @typedoc "Provider specification containing metadata and auth configuration"

    field(:id, atom(), enforce: true)
    field(:base_url, String.t(), enforce: true)
    field(:auth, {atom(), String.t(), atom() | function()}, enforce: true)
    field(:default_model, String.t())
    field(:default_temperature, float())
    field(:default_max_tokens, pos_integer())
    field(:models, map(), default: %{})
  end

  @doc """
  Creates a new provider specification.

  ## Examples

      iex> ReqAI.Provider.Spec.new(
      ...>   id: :anthropic,
      ...>   base_url: "https://api.anthropic.com",
      ...>   auth: {:header, "x-api-key", :plain}
      ...> )
      %ReqAI.Provider.Spec{
        id: :anthropic,
        base_url: "https://api.anthropic.com",
        auth: {:header, "x-api-key", :plain}
      }

  """
  @spec new(keyword()) :: t()
  def new(opts) do
    struct!(__MODULE__, opts)
  end
end
