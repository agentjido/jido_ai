Mimic.copy(ReqLLM)
Mimic.copy(ReqLLM.Generation)
Mimic.copy(ReqLLM.Embedding)
Mimic.copy(ReqLLM.Providers.OpenAI)
Mimic.copy(ReqLLM.Providers.OpenAICodex)
Mimic.copy(ReqLLM.StreamResponse)
Mimic.copy(Jido.AgentServer)

# Load the LLMDB model catalog before any test runs so that the first model
# lookup does not pay the one-time snapshot load inside a test's timeout
# budget. The isolated fast gate (`mix test.fast`) otherwise exceeds the
# 750 ms `RunStrategyFastTest` budget on hosts where the load is slow.
{:ok, _} = LLMDB.load()

ExUnit.start(exclude: [:flaky], capture_log: true)
