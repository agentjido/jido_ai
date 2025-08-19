defmodule Jido.Character.Persistence.Adapter do
  @moduledoc """
  Behaviour defining the persistence interface for Jido.Character storage.
  """

  @callback save(Jido.Character.t()) :: {:ok, Jido.Character.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, Jido.Character.t()} | {:error, :not_found}
  @callback delete(String.t()) :: :ok | {:error, term()}
end
