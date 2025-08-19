defmodule JidoWorkbenchWeb.Router do
  use JidoWorkbenchWeb, :router

  # Build documentation routes at compile time
  @menu_tree JidoWorkbench.Documentation.menu_tree()

  @doc_routes [
                {"/docs", LivebookDemoLive, :index, %{tag: :docs}},
                {"/cookbook", LivebookDemoLive, :index, %{tag: :cookbook}}
              ] ++
                ((for doc <- JidoWorkbench.Documentation.all_documents() do
                    path_without_category =
                      case String.trim_leading(doc.path, "/") |> String.split("/", parts: 2) do
                        [_category, rest] -> rest
                        _ -> nil
                      end

                    if path_without_category do
                      case doc.category do
                        :docs ->
                          {"/docs/#{path_without_category}", LivebookDemoLive, :show, %{tag: :docs}}

                        :cookbook ->
                          {"/cookbook/#{path_without_category}", LivebookDemoLive, :show, %{tag: :cookbook}}

                        _ ->
                          nil
                      end
                    end
                  end)
                 |> Enum.reject(&is_nil/1))

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {JidoWorkbenchWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(JidoWorkbenchWeb.Plugs.LLMKeysPlug)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", JidoWorkbenchWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    live("/settings", SettingsLive, :index)
    get("/settings/clear", LLMKeyController, :clear_session)
    post("/settings/save", LLMKeyController, :save_settings)

    get("/blog", BlogController, :index)
    get("/blog/tags/:tag", BlogController, :tag)
    get("/blog/search", BlogController, :search)
    get("/blog/:slug", BlogController, :show)
    get("/feed", BlogController, :feed)

    # live("/jido", JidoLive, :index)
    # live("/jido2", JidoLive2, :index)
    # live("/team", TeamLive, :index)

    for {path, live_view, action, metadata} <- @doc_routes do
      live path, live_view, action, metadata: metadata
    end

    # Jido Catalog
    live("/catalog", CatalogLive, :index)
    live("/catalog/actions", CatalogActionsLive, :index)
    live("/catalog/actions/:slug", CatalogActionsLive, :show)
    live("/catalog/agents", CatalogAgentsLive, :index)
    live("/catalog/sensors", CatalogSensorsLive, :index)
    live("/catalog/skills", CatalogSkillsLive, :index)

    # Petal Boilerplate Helpers
    # live("/form", FormLive, :index)
    # live("/live", PageLive, :index)
    # live("/live/modal/:size", PageLive, :modal)
    # live("/live/slide_over/:origin", PageLive, :slide_over)
    # live("/live/pagination/:page", PageLive, :pagination)
  end

  # Other scopes may use custom stacks.
  # scope "/api", JidoWorkbenchWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:jido_workbench, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: JidoWorkbenchWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
