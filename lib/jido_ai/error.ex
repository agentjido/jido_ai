defmodule Jido.AI.Error do
  @moduledoc """
  Custom error type for Jido.AI operations.
  """

  defexception [:message, :type]

  @type t :: %__MODULE__{
          message: String.t(),
          type: atom() | nil
        }

  def new(message, type \\ nil) do
    %__MODULE__{message: message, type: type}
  end

  @impl true
  def message(%__MODULE__{message: message}), do: message
end
