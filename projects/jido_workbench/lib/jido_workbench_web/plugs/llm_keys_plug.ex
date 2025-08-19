defmodule JidoWorkbenchWeb.Plugs.LLMKeysPlug do
  @moduledoc """
  Plug that assigns LLM API keys from the session to the connection.
  """

  import Plug.Conn
  alias JidoWorkbenchWeb.LLMKeys

  def init(opts), do: opts

  def call(conn, _opts) do
    session = get_session(conn)

    # Assign all configured keys to the connection
    Enum.reduce(LLMKeys.settings(), conn, fn setting, conn ->
      value = LLMKeys.get_key(setting.key, session)

      conn
      |> assign(:"#{setting.key}_api_key", value)
      |> assign(:"has_#{setting.key}_key?", LLMKeys.has_valid_key?(value))
    end)
  end
end
