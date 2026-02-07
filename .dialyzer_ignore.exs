[
  # Mix.Task behaviour info not available in PLT - false positive
  ~r/lib\/mix\/tasks\/jido_ai\..*\.ex.*callback_info_missing/,
  ~r/lib\/mix\/tasks\/jido_ai\..*\.ex.*unknown_function.*Mix\.Task/,

  # Mix tasks with System.halt(1) in error paths report no_return - expected behavior
  ~r/lib\/mix\/tasks\/jido_ai\..*\.ex.*no_return/,

  # plugin_specs/0 contract mismatch - the Zoi-generated type spec in jido's Agent
  # macro doesn't match Dialyzer's success typing for the concrete struct values.
  {"lib/jido_ai/agents/api_smoke_test_agent.ex", :invalid_contract},
  {"lib/jido_ai/agents/issue_triage_agent.ex", :invalid_contract},
  {"lib/jido_ai/agents/react_demo_agent.ex", :invalid_contract},
  {"lib/jido_ai/agents/release_notes_agent.ex", :invalid_contract},
  {"lib/jido_ai/agents/weather_agent.ex", :invalid_contract},

  # MapSet opaque type warnings - dialyzer doesn't handle MapSet's opaque internal
  # structure correctly when passed through recursive functions or across module boundaries
  ~r/lib\/jido_ai\/strategies\/graph_of_thoughts\/machine\.ex.*call_without_opaque/,

  # Executor pattern_match at module level - false positive from type narrowing
  ~r/lib\/jido_ai\/executor\.ex:1:pattern_match/,

  # Jido dependency callback_type_mismatch - issues in deps/jido not jido_ai
  ~r/deps\/jido\/lib\/jido\/agent\.ex.*callback_type_mismatch/,
  ~r/deps\/jido\/lib\/jido\/agent\.ex.*pattern_match/,

  # Directive exec callback type mismatch - sync tuple return vs expected ok/async/stop
  ~r/lib\/jido_ai\/directive\.ex.*callback_type_mismatch/,

  # Guard fail for binary checks on structs - expected for defensive programming
  ~r/lib\/jido_ai\.ex.*guard_fail/,
  ~r/lib\/jido_ai\/directive\.ex.*guard_fail/,

  # Pattern match coverage - fallback clauses for defensive programming
  ~r/lib\/jido_ai\/agents\/orchestrator_agent\.ex.*pattern_match_cov/,

  # Example agent plugin_specs contract mismatch - same as agents above
  {"lib/jido_ai/examples/calculator_agent.ex", :invalid_contract},
  {"lib/jido_ai/examples/skills_demo_agent.ex", :invalid_contract},

  # TUI module - blanket ignore all issues
  ~r/lib\/jido_ai\/cli\/tui\.ex/,

  # Chat mix task pattern_match caused by TUI return type
  ~r/lib\/mix\/tasks\/jido_ai\.chat\.ex.*pattern_match/
]
