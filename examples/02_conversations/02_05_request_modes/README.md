# Request modes

Run the Session Agent with AgentServer `call` and `submit`/`await`. AgentServer
owns request execution and cancellation. Session remains an immutable state
value and receives only complete turns from the route Action. The route reply
projection delivers the correlated Signal to the request owner after commit.
