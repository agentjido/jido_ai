# Conversation history

Project committed request and reply Signal pairs into ReqLLM messages. The
projection is local to this example and does not change the Thread.

The route Action uses the SignalAction to generate an answer from the projected
history. It then commits the new request and reply.
