[
  # Mix task callback info is not available - this is expected for mix tasks
  {"lib/mix/tasks/model_sync.ex", :callback_info_missing},
  # ExUnit functions are runtime-only in capability verifier context
  {"lib/req_llm/capability_verifier.ex", :unknown_function},
  # Pattern match warning appears to be false positive - guards make patterns reachable
  {"lib/req_llm/capabilities/chat.ex", :pattern_match}
]
