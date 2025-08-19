defmodule JidoWorkbenchWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :jido_workbench

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_jido_workbench_key",
    signing_salt: "fodlg9j/",
    same_site: "Lax"
  ]

  plug JidoWorkbenchWeb.Plug.Heartbeat
  plug(:canonical_host)

  defp canonical_host(conn, _opts) do
    :jido_workbench
    |> Application.get_env(:canonical_host)
    |> case do
      host when is_binary(host) ->
        opts = PlugCanonicalHost.init(canonical_host: host)
        PlugCanonicalHost.call(conn, opts)

      _ ->
        conn
    end
  end

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :jido_workbench,
    gzip: false,
    only: JidoWorkbenchWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :jido_workbench
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug JidoWorkbenchWeb.Router
end
