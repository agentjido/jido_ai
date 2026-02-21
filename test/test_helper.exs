Mimic.copy(ReqLLM)
Mimic.copy(ReqLLM.Generation)
Mimic.copy(ReqLLM.Embedding)
Mimic.copy(ReqLLM.StreamResponse)
Mimic.copy(Jido.AgentServer)

ExUnit.start(exclude: [:flaky], capture_log: true)
