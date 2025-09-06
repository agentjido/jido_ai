[
  # Mix task callback info is not available - this is expected for mix tasks
  {"lib/mix/tasks/model_sync.ex", :callback_info_missing},
  # ExUnit functions are runtime-only in capability verifier context
  {"lib/req_ai/capability_verifier.ex", :unknown_function},
  # Pattern match warning appears to be false positive - guards make patterns reachable
  {"lib/req_ai/capabilities/chat.ex", :pattern_match}
]
