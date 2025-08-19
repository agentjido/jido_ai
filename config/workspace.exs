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
    },
    %{
      name: "jido_eval",
      upstream_url: "git@github.com:agentjido/jido_eval.git",
      branch: "main",
      type: :library,
      path: "projects/jido_eval"
    },
    %{
      name: "jido_workbench",
      upstream_url: "git@github.com:agentjido/jido_workbench.git",
      branch: "main",
      type: :library,
      path: "projects/jido_workbench"
    },
    %{
      name: "depot",
      upstream_url: "git@github.com:mikehostetler/depot.git",
      branch: "master",
      type: :library,
      path: "projects/depot"
    },
    %{
      name: "jido_behaviortree",
      upstream_url: "git@github.com:agentjido/jido_behaviortree.git",
      branch: "main",
      type: :library,
      path: "projects/jido_behaviortree"
    },
    %{
      name: "jido_chat",
      upstream_url: "git@github.com:agentjido/jido_chat.git",
      branch: "main",
      type: :library,
      path: "projects/jido_chat"
    },
    %{
      name: "sparq",
      upstream_url: "git@github.com:epic-creative/sparq.git",
      branch: "main",
      type: :library,
      path: "projects/sparq"
    },
    %{
      name: "jido_character",
      upstream_url: "git@github.com:epic-creative/jido_character.git",
      branch: "main",
      type: :library,
      path: "projects/jido_character"
    },
    %{
      name: "jido_dialogue",
      upstream_url: "git@github.com:epic-creative/jido_dialogue.git",
      branch: "main",
      type: :library,
      path: "projects/jido_dialogue"
    },
    %{
      name: "jido_htn",
      upstream_url: "git@github.com:epic-creative/jido_htn.git",
      branch: "main",
      type: :library,
      path: "projects/jido_htn"
    },
    %{
      name: "kodo",
      upstream_url: "git@github.com:epic-creative/kodo.git",
      branch: "main",
      type: :library,
      path: "projects/kodo"
    }




  ]
