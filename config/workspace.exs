import Config

config :jido_workspace,
  projects: [
    %{
      name: "jido",
      upstream_url: "https://github.com/agentjido/jido",
      branch: "main",
      type: :library,
      path: "projects/jido"
    },
    %{
      name: "jido_action",
      upstream_url: "https://github.com/agentjido/jido_action",
      branch: "main",
      type: :library,
      path: "projects/jido_action"
    },
    %{
      name: "jido_signal",
      upstream_url: "https://github.com/agentjido/jido_signal",
      branch: "main",
      type: :library,
      path: "projects/jido_signal"
    }
  ]
