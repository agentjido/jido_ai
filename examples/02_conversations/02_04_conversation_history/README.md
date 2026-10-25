# Conversation history

Use `Jido.AI.Context` to project committed request and reply Signal pairs into
ReqLLM messages. The projection does not change the Session or Thread.

The request gives its Session and an explicit Agent route reference to Jido AI.
Only complete correlated pairs enter model context. Unrelated Signals and an
incomplete request stay in the Thread but do not enter the model request.

The route Action receives a completed `Jido.AI.Result`. It then builds the new
Session and reply data as one route output. Core Jido commits the Session and
builds the correlated Reply Directive.
