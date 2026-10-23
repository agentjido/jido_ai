# 02 Conversations

These examples start with an AI Agent that owns a Thread directly. A Thread
holds committed Signals. A Session then adds identity and lifecycle state.

Each Agent uses `initialize/2` to add fresh instance data when the candidate
state does not already supply it. A turn Action prepares the current state,
runs the configured reasoning Flow, and gives the completed result to
`Jido.AI.Turn.complete/4`. The AgentServer owns request execution and the final
commit. Session and Thread remain immutable values.

1. [Thread Agent](02_01_thread_agent/README.md)
2. [Session value](02_02_session_value/README.md)
3. [Session Agent](02_03_session_agent/README.md)
4. [Context projection](02_04_conversation_history/README.md)
5. [Request modes](02_05_request_modes/README.md)
