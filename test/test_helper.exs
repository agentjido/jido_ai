Mimic.copy(ReqLLM)
Mimic.copy(ReqLLM.Generation)
Mimic.copy(ReqLLM.Embedding)
Mimic.copy(ReqLLM.Providers.OpenAI)
Mimic.copy(ReqLLM.Providers.OpenAICodex)
Mimic.copy(ReqLLM.StreamResponse)
Mimic.copy(Jido.AgentServer)
Mimic.copy(Jido.AI.CLI.Adapter)

coverage_active? =
  :ets.whereis(:excoveralls_conf_server) != :undefined and
    ExCoveralls.ConfServer.get() != []

coverage_exclusions = if coverage_active?, do: [:coverage_external_vm], else: []

ExUnit.start(
  exclude: [:flaky, :example, :legacy_v2] ++ coverage_exclusions,
  capture_log: true
)
