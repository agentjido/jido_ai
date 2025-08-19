import Config

config :jido_workspace,
  projects: [
    %{
      name: "jido",
      upstream_url: "git@github.com:agentjido/jido.git",
      branch: "main",
      type: :library,
      path: "projects/jido"
    },
    %{
      name: "jido_action",
      upstream_url: "git@github.com:agentjido/jido_action.git",
      branch: "main",
      type: :library,
      path: "projects/jido_action"
    },
    %{
      name: "jido_signal",
      upstream_url: "git@github.com:agentjido/jido_signal.git",
      branch: "main",
      type: :library,
      path: "projects/jido_signal"
    },
    %{
      name: "jido_presentations",
      upstream_url: "git@github.com:agentjido/jido_presentations.git",
      branch: "main",
      type: :docs,
      path: "presentations"
    },
    %{
      name: "ash_jido",
      upstream_url: "git@github.com:agentjido/ash_jido.git",
      branch: "main",
      type: :library,
      path: "projects/ash_jido"
    },
    %{
      name: "jido_ai",
      upstream_url: "git@github.com:agentjido/jido_ai.git",
      branch: "refactor/models",
      type: :library,
      path: "projects/jido_ai"
    }


  ]
