defmodule JSV.Helpers.MapExt do
  @moduledoc """
  Helpers to work with maps.
  """

  @doc """
  Returns the given struct without its `:__struct__` key and any key whose value
  is `nil`.
  """
  @spec from_struct_no_nils(struct) :: map
  def from_struct_no_nils(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.filter(fn {_, v} -> v != nil end)
  end
end
