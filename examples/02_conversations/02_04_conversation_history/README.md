# Conversation history

Project committed request and reply Signal pairs into ReqLLM messages. The
projection is local to this example and does not change the Thread.

The route Flow generates an answer from the projected history. Its
`complete_turn` step then commits the new request and reply through an inline
Action.
