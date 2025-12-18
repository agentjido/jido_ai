defmodule JSV.Root do
  alias JSV.Validator

  @moduledoc """
  Internal representation of a JSON schema built with `JSV.build/2`.

  The original schema, in its string-keys form, can be retrieved in the `:raw`
  key of the struct.
  """

  defstruct validators: %{},
            root_key: nil,
            raw: nil

  @type t :: %__MODULE__{raw: map | boolean | nil, validators: Validator.validators()}
end
