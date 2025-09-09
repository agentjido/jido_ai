# Ensure providers are loaded for testing
Application.ensure_all_started(:req_llm)

ExUnit.start(capture_log: true)

# Global Mimic setup - only copy modules that are actually mocked in tests
Mimic.copy(ReqLLM)
Mimic.copy(ReqLLM.Model)
Mimic.copy(ReqLLM.Capability)
Mimic.copy(ReqLLM.Capability.Reporter)
Mimic.copy(Application)
Mimic.copy(Mix.Task)
Mimic.copy(File)
Mimic.copy(Jason)
Mimic.copy(System)
Mimic.copy(IO)
