# 02 Conversations

These examples start with an AI Agent that owns a Thread directly. A Thread
holds committed Signals. A Session then adds identity and lifecycle state.

Each complete AI turn is a Flow. One Action generates the answer. A second
Action commits the request and reply. The AgentServer owns request execution.
Session and Thread remain immutable state values.
