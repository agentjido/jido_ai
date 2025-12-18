defmodule JSV.Helpers.Math do
  @moduledoc false

  # This will not work with large numbers
  @spec fractional_is_zero?(float) :: boolean
  def fractional_is_zero?(n) when is_float(n) do
    diff = n - Kernel.trunc(n)
    diff === 0.0 || diff === -0.0
  end

  # This will not work with large numbers
  @spec trunc(number) :: integer
  def trunc(n) when is_float(n) do
    Kernel.trunc(n)
  end
end
