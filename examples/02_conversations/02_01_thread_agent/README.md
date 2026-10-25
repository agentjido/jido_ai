# Thread Agent

Define an AI Agent with a portable Thread in its declared state. A successful
route appends the request and its correlated reply to the Thread as one batch.
A failed model call does not change the Thread.

The route Action checks the Thread, runs the configured reasoning Flow, and
returns state and reply data. The route projects the new Thread state and
builds the correlated reply.

This example records one completed turn. Later examples use committed Thread
Signals as model conversation history.
