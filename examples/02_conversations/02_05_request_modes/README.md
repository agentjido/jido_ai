# Request modes

Run the Session Agent with AgentServer `call` and `submit`/`await`. AgentServer
owns request execution and cancellation. Session remains an immutable state
value and receives only complete turns from the route Flow.
