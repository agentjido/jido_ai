ExUnit.start(
  exclude: [:flaky, :requires_api, :requires_python, :requires_claude_code_cli, :requires_codex_cli],
  capture_log: true
)
