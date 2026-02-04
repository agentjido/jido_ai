import Config

config :git_hooks,
  auto_install: false,
  verbose: true,
  hooks: [
    commit_msg: [
      tasks: [
        {:cmd, "mix git_ops.check_message", include_hook_args: true}
      ]
    ],
    pre_push: [
      tasks: [
        {:mix_task, :format, ["--check-formatted"]}
      ]
    ]
  ]
