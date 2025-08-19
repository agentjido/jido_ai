defmodule JidoWorkbenchWeb.SEO do
  use JidoWorkbenchWeb, :verified_routes

  use SEO,
    json_library: Jason,
    # a function reference will be called with a conn during render
    # arity 1 will be passed the conn, arity 0 is also supported.
    site: &__MODULE__.site_config/1,
    open_graph:
      SEO.OpenGraph.build(
        description: "Agent Jido is the Elixir Autonomous Agent Framework",
        site_name: "Agent Jido",
        locale: "en_US"
      ),
    twitter:
      SEO.Twitter.build(
        site: "@agentjido",
        # site_id: "27704724",
        creator: "@mikehostetler",
        # creator_id: "27704724",
        card: :summary
      )

  # Or arity 0 is also supported, which can be great if you're using
  # Phoenix verified routes and don't need the conn to generate paths.
  def site_config(conn) do
    SEO.Site.build(
      default_title: "Agent Jido",
      description: "Agent Jido is the Elixir Autonomous Agent Framework",
      title_suffix: " · Agent Jido"
      # theme_color: "#663399",
      # windows_tile_color: "#663399",
      # mask_icon_color: "#663399",
      # mask_icon_url: static_url(conn, "/images/safari-pinned-tab.svg"),
      # manifest_url: url(conn, ~p"/site.webmanifest")
    )
  end
end
