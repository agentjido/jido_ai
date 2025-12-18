defmodule JSV.Validator.Error do
  @moduledoc """
  Representation of an error encountered during validation.
  """

  @enforce_keys [:kind, :data, :args, :formatter, :data_path, :eval_path, :schema_path]
  defstruct @enforce_keys

  @opaque t :: %__MODULE__{}
end
