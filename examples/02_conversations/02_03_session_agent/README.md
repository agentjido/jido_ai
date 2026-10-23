# Session Agent

The route Action calls the SignalAction and its configured reasoning Flow,
builds the typed reply Signal, and commits the request and reply to Session
state together. A failed model call returns no new Agent state or directive.
