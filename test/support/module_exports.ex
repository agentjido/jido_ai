defmodule Jido.AI.Test.ModuleExports do
  @moduledoc false

  @spec exported?(module(), atom(), non_neg_integer()) :: boolean()
  def exported?(module, function, arity)
      when is_atom(module) and is_atom(function) and is_integer(arity) and arity >= 0 do
    Code.ensure_loaded!(module)
    function_exported?(module, function, arity)
  end
end
