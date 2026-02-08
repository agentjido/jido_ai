ExUnit.start(
  exclude: [:flaky, :requires_api, :requires_python, :requires_live_agent_cli],
  capture_log: true
)
