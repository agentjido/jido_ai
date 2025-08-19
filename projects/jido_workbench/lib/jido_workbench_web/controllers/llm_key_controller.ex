defmodule JidoWorkbenchWeb.LLMKeyController do
  use JidoWorkbenchWeb, :controller
  alias JidoWorkbenchWeb.LLMKeys

  def clear_session(conn, _params) do
    # Clear all known LLM key session values
    conn =
      Enum.reduce(LLMKeys.settings(), conn, fn setting, conn ->
        delete_session(conn, setting.session_key)
      end)

    conn
    |> put_flash(:info, "Settings reset to environment defaults")
    |> redirect(to: ~p"/settings")
  end

  def save_settings(conn, %{"settings" => settings}) do
    # Update each key in the session
    conn =
      Enum.reduce(LLMKeys.settings(), conn, fn setting, conn ->
        key = Atom.to_string(setting.key)
        value = settings[key]
        put_session(conn, setting.session_key, value)
      end)

    conn
    |> put_flash(:info, "Settings saved successfully.")
    |> redirect(to: ~p"/settings")
  end
end
