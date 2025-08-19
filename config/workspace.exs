import Config

config :jido_workspace,
  projects: [
    %{
      name: "jido",
      upstream_url: "https://github.com/agentjido/jido",
      branch: "main",
      type: :library,
      path: "projects/jido"
    }
  ]
