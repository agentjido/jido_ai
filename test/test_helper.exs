Mimic.copy(ReqLLM)
Mimic.copy(ReqLLM.Generation)
Mimic.copy(ReqLLM.StreamResponse)

ExUnit.start(exclude: [:flaky], capture_log: true)
