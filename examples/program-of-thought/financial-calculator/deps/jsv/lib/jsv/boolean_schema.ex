defmodule JSV.BooleanSchema do
  alias JSV.Builder

  @moduledoc """
  Represents a boolean schema. Boolean schemas accept or reject any data
  according to their boolean value.

  This is very often used with the `additionalProperties` keyword.
  """

  @enforce_keys [:valid?, :schema_path]
  defstruct @enforce_keys

  @type t :: %__MODULE__{valid?: boolean, schema_path: [Builder.path_segment()]}

  @doc """
  Returns a `#{inspect(__MODULE__)}` struct wrapping the given boolean.
  """
  @spec of(boolean, [Builder.path_segment()]) :: t
  def of(valid?, schema_path) when is_boolean(valid?) do
    %__MODULE__{valid?: valid?, schema_path: schema_path}
  end
end
