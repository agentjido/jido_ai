defmodule JSV.Helpers.StringExt do
  @moduledoc false

  @doc """
  Returns the given string converted to an atom as a result tuple.
  """
  @spec safe_string_to_existing_module(String.t()) :: {:ok, atom} | {:error, {:unknown_module, String.t()}}
  def safe_string_to_existing_module(string) do
    module = String.to_existing_atom(string)
    Code.ensure_loaded!(module)
    {:ok, module}
  rescue
    _ in ArgumentError -> {:error, {:unknown_module, string}}
  end
end
