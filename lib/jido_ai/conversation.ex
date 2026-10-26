defmodule Jido.AI.Conversation do
  @moduledoc false

  @doc "Returns a canonical Session from Agent state or a portable graph value."
  @spec decode!(Jido.Session.t() | map()) :: Jido.Session.t()
  def decode!(%Jido.Session{} = session), do: session

  def decode!(value) when is_map(value) do
    case Jido.Session.decode(value) do
      {:ok, session} -> session
      {:error, reason} -> raise ArgumentError, "invalid graph session: #{inspect(reason)}"
    end
  end

  @doc "Returns the portable graph form of a canonical Session."
  @spec encode(Jido.Session.t()) :: map()
  def encode(%Jido.Session{} = session), do: Jido.Session.encode(session)
end
