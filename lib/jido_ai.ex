defmodule Jido.AI do
  @moduledoc """
  High-level API for accessing AI provider keys.
  """

  alias Jido.AI.Keyring

  defdelegate get_key(provider), to: Keyring
  defdelegate set_session_key(provider, key), to: Keyring
  defdelegate get_session_key(provider), to: Keyring
  defdelegate clear_session_key(provider), to: Keyring
  defdelegate clear_all_session_keys, to: Keyring
end
