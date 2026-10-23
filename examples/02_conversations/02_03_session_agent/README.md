# Session Agent

The route Flow calls the model, builds the typed reply Signal, and commits the
request and reply to Session state together. The `complete_turn` Flow extension
adds the inline commit Action. A failed model call returns no new Agent state or
directive.
