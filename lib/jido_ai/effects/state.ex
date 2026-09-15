defmodule Jido.AI.Effects.State do
  @moduledoc "A complete proposed Agent state returned by a tool."
  @enforce_keys [:state]
  defstruct [:state]
  @type t :: %__MODULE__{state: map()}
end
