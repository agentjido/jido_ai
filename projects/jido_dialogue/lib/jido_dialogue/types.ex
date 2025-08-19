defmodule Jido.Dialogue.Types do
  @moduledoc """
  Common types used across the dialogue system.
  """

  @type speaker :: :human | :agent | :system | :unknown
  @type state :: :initial | :active | :waiting | :completed
  @type turn_id :: String.t()
  @type timestamp :: DateTime.t()
end
