[
  # Upstream warning noise from jido dependency typing.
  ~r"deps/jido/lib/jido/agent.ex:",

  # CoT delegated worker migration warnings.
  ~r"lib/jido_ai/reasoning/chain_of_thought/compat/worker_agent.ex:",
  ~r"lib/jido_ai/reasoning/chain_of_thought/strategy.ex:",
  ~r"lib/jido_ai/reasoning/chain_of_thought/worker/agent.ex:",
  ~r"lib/jido_ai/reasoning/chain_of_thought/worker/strategy.ex:",

  # GoT compat shim contract mismatch.
  ~r"lib/jido_ai/reasoning/graph_of_thoughts/compat/machine.ex:",

  # ReAct delegated runtime/worker migration warnings.
  ~r"lib/jido_ai/reasoning/react/actions/helpers.ex:",
  ~r"lib/jido_ai/reasoning/react/compat/worker_agent.ex:",
  ~r"lib/jido_ai/reasoning/react/runner.ex:",
  ~r"lib/jido_ai/reasoning/react/strategy.ex:",
  ~r"lib/jido_ai/reasoning/react/worker/agent.ex:",
  ~r"lib/jido_ai/reasoning/react/worker/strategy.ex:"
]
