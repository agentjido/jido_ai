defprotocol JSV.Normalizer.Normalize do
  @moduledoc """
  Protocol used by `JSV.Normalizer` to transform structs into JSON-compatible
  data structures when normalizing a schema.

  When implementing this protocol you do not need to run any specific
  normalization by yourself, but rather just return a map with all or a
  selection of keys. Keys can be atoms or binaries, and values will be
  normalized recursively.
  """
  @spec normalize(term) :: term
  def normalize(t)
end
