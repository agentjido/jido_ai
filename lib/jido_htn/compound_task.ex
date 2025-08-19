defmodule Jido.HTN.CompoundTask do
  @moduledoc """
  Represents a compound task in the HTN planning system.
  """

  alias Jido.HTN.Method

  @type t :: %__MODULE__{
          name: String.t(),
          methods: [Method.t()]
        }

  defstruct [:name, methods: []]

  @doc """
  Creates a new compound task with the given name and optional list of methods.
  """
  @spec new(String.t(), [Method.t()]) :: t()
  def new(name, methods \\ []) when is_binary(name) do
    %__MODULE__{name: name, methods: methods}
  end

  @doc """
  Adds a method to the compound task.
  """
  @spec add_method(t(), Method.t()) :: t()
  def add_method(%__MODULE__{methods: methods} = task, method) do
    %{task | methods: methods ++ [method]}
  end
end
