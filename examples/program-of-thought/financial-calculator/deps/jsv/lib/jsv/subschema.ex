defmodule JSV.Subschema do
  alias JSV.Vocabulary
  @enforce_keys [:validators, :schema_path, :cast]
  defstruct @enforce_keys

  @moduledoc """
  Build result for a raw map schema.
  """

  @type validators :: [{module, Vocabulary.collection()}]

  @type t :: %__MODULE__{validators: validators, schema_path: [String.t()], cast: term}
end
