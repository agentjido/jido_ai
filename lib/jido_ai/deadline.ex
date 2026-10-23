defmodule Jido.AI.Deadline do
  @moduledoc false

  @enforce_keys [:at, :timeout]
  defstruct [:at, :timeout]

  @type t :: %__MODULE__{
          at: integer(),
          timeout: pos_integer()
        }

  @spec new(pos_integer()) :: t()
  def new(timeout) when is_integer(timeout) and timeout > 0 do
    %__MODULE__{
      at: System.monotonic_time(:millisecond) + timeout,
      timeout: timeout
    }
  end

  @spec valid?(term()) :: boolean()
  def valid?(%{at: at, timeout: timeout})
      when is_integer(at) and is_integer(timeout) and timeout > 0,
      do: true

  def valid?(_deadline), do: false

  @spec remaining(t() | map()) :: {:ok, pos_integer()} | {:error, {:request_timeout, pos_integer()}}
  def remaining(%{at: at, timeout: timeout}) do
    case at - System.monotonic_time(:millisecond) do
      remaining when remaining > 0 -> {:ok, remaining}
      _expired -> {:error, {:request_timeout, timeout}}
    end
  end

  @spec cap(t() | map() | nil, pos_integer()) ::
          {:ok, pos_integer()} | {:error, {:request_timeout, pos_integer()}}
  def cap(nil, timeout) when is_integer(timeout) and timeout > 0, do: {:ok, timeout}

  def cap(deadline, timeout) when is_integer(timeout) and timeout > 0 do
    with {:ok, remaining} <- remaining(deadline) do
      {:ok, min(timeout, remaining)}
    end
  end
end
