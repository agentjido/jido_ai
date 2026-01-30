# Dialyzer ignore patterns
# These are false positives due to incomplete PLT information from req_llm

[
  # Mix.Task behaviour info not available in PLT - false positive
  ~r/lib\/mix\/tasks\/jido_ai\..*\.ex.*callback_info_missing/,
  ~r/lib\/mix\/tasks\/jido_ai\..*\.ex.*unknown_function.*Mix\.Task/,

  # Mix tasks with System.halt(1) in error paths report no_return - expected behavior
  ~r/lib\/mix\/tasks\/jido_ai\..*\.ex.*no_return/,

  # skill_specs/0 contract mismatch - the Zoi-generated type spec in jido's Agent
  # macro doesn't match Dialyzer's success typing for the concrete struct values.
  # This is a false positive due to Zoi's type generation approach.
  {"lib/jido_ai/agents/api_smoke_test_agent.ex", :invalid_contract},
  {"lib/jido_ai/agents/issue_triage_agent.ex", :invalid_contract},
  {"lib/jido_ai/agents/react_demo_agent.ex", :invalid_contract},
  {"lib/jido_ai/agents/release_notes_agent.ex", :invalid_contract},
  {"lib/jido_ai/agents/weather_agent.ex", :invalid_contract},

  # Skills with ReqLLM dependencies have incomplete type info
  # The unused_fun warnings occur because dialyzer doesn't see the full call chain
  # through ReqLLM.Generation.generate_text/3 and streaming functions
  ~r/lib\/jido_ai\/skills\/.*\.ex.*unused_fun/,
  ~r/lib\/jido_ai\/skills\/.*\.ex.*no_return/,

  # StateOp.delete_path type info missing from jido PLT
  ~r/lib\/jido_ai\/strategy\/state_ops_helpers\.ex.*no_return/,
  ~r/lib\/jido_ai\/strategy\/state_ops_helpers\.ex.*invalid_contract/,

  # MapSet opaque type warnings - dialyzer doesn't handle MapSet's opaque internal
  # structure correctly when passed through recursive functions or across module boundaries
  ~r/lib\/jido_ai\/strategies\/graph_of_thoughts\/machine\.ex.*call_without_opaque/,
  ~r/lib\/jido_ai\/cli\/tui\.ex.*call_without_opaque/,

  # GEPA extract_output fallback clauses - guard_fail is expected for catch-all patterns
  ~r/lib\/mix\/tasks\/jido_ai\.gepa\.ex.*guard_fail/,

  # TUI run/1 uses System.halt(1) on error path, which dialyzer treats as no_return
  ~r/lib\/jido_ai\/cli\/tui\.ex.*no_return/,

  # Executor format_error guards are unreachable in some type-narrowed contexts
  # This is a false positive - the guards cover all realistic error types
  ~r/lib\/jido_ai\/tools\/executor\.ex.*guard_fail/,
  ~r/lib\/jido_ai\/tools\/executor\.ex.*pattern_match_cov/
]
