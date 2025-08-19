defmodule AshJido.Resource.JidoAction do
  @moduledoc """
  Represents a Jido action configuration from the DSL.
  """

  defstruct [
    :action,
    :name,
    :module_name,
    :description,
    :tags,
    output_map?: true,
    pagination?: true
  ]

  @type t :: %__MODULE__{
          action: atom(),
          name: String.t() | nil,
          module_name: atom() | nil,
          description: String.t() | nil,
          tags: [String.t()] | nil,
          output_map?: boolean(),
          pagination?: boolean()
        }
end
