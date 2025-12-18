defmodule JSV.FormatValidator.Default.Optional do
  @moduledoc false

  @doc false
  @spec optional_support(binary, boolean) :: [binary]
  def optional_support(format, supported?) when is_boolean(supported?) do
    if supported? do
      List.wrap(format)
    else
      []
    end
  end
end
