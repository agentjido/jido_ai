# Thread Agent

Define an AI Agent with a portable Thread in its declared state. A successful
route appends the request and its correlated reply to the Thread as one batch.
A failed model call does not change the Thread.

The route uses a Flow. Its first Action generates the answer. The
`complete_turn` Flow extension adds an inline Action that updates the Thread
and returns the reply directive.

This example records one completed turn. Later examples use committed Thread
Signals as model conversation history.
