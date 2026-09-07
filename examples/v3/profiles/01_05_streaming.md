# 01_05 — Streaming and cancellation

Task: show progress while model work is active, then commit one final answer.

- [Agent and streaming Flow](../lib/examples/01_authoring/01_05_streaming/agent.ex)
- [Acceptance tests](../test/examples/01_authoring/01_05_streaming_test.exs)

The HTTP server holds an SSE stream at a barrier. The test receives a token and
checks that the live state has not changed. Release allows one complete commit.
A second test cancels the live Turn. It checks the command error, prior state,
and termination of the provider connection worker with a process monitor.

Status: two passing integration tests. The shared mock suite also tests receive
timeout and disconnect cleanup. Caller wait timeout, AI request admission,
steering, terminal events, and durable resume remain separate migration work.
