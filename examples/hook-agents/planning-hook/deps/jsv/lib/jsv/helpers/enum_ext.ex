defmodule JSV.Helpers.EnumExt do
  @type result :: {:ok, term} | {:error, term}
  @type result(t) :: {:ok, t} | {:error, term}
  import Kernel, except: [trunc: 1]

  @moduledoc false

  @doc false
  @spec reduce_ok(Enumerable.t(), term, (term, term -> result)) :: result
  def reduce_ok(enum, initial, f) when is_function(f, 2) do
    Enum.reduce_while(enum, {:ok, initial}, fn item, {:ok, acc} ->
      case f.(item, acc) do
        {:ok, new_acc} -> {:cont, {:ok, new_acc}}
        {:error, _} = err -> {:halt, err}
        other -> raise ArgumentError, "bad return from reduce_ok callback: #{inspect(other)}"
      end
    end)
  end
end
