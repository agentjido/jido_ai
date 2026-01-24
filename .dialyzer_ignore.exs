# Dialyzer ignore patterns
# These are false positives due to incomplete PLT information from req_llm

[
  # Skills with ReqLLM dependencies have incomplete type info
  # The unused_fun warnings occur because dialyzer doesn't see the full call chain
  # through ReqLLM.Generation.generate_text/3 and streaming functions
  ~r/lib\/jido_ai\/skills\/.*\.ex.*unused_fun/,
  ~r/lib\/jido_ai\/skills\/.*\.ex.*no_return/,

  # StateOp.delete_path type info missing from jido PLT
  ~r/lib\/jido_ai\/strategy\/state_ops_helpers\.ex.*no_return/,
  ~r/lib\/jido_ai\/strategy\/state_ops_helpers\.ex.*invalid_contract/
]
