Mimic.copy(ReqLLM)
Mimic.copy(ReqLLM.Generation)
Mimic.copy(ReqLLM.Embedding)
Mimic.copy(ReqLLM.StreamResponse)

ExUnit.start(exclude: [:flaky], capture_log: true)
