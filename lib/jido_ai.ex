defmodule Jido.AI do
  @moduledoc """
  High-level API for accessing AI provider keys.
  """

  alias Jido.AI.Keyring

  defdelegate get(key), to: Keyring
  defdelegate set_session_value(key, value), to: Keyring
  defdelegate get_session_value(key), to: Keyring
  defdelegate clear_session_value(key), to: Keyring
  defdelegate clear_all_session_values, to: Keyring
end
