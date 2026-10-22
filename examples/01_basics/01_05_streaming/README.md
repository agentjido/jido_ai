# 01_05 — Streaming and cancellation

Start a ReqLLM stream with the Agent configuration.

## What you will learn

- Call `Agent.stream/2`.
- Read text with `ReqLLM.StreamResponse.tokens/1`.
- Close the response to cancel work and release its metadata process.

## Run it

```sh
mix test test/examples/01_basics/01_05_streaming --include example --seed 0
```

The test uses a local stream. It does not use the network.

## Files

- [Agent](agent.ex)
- [Test](../../../test/examples/01_basics/01_05_streaming/streaming_test.exs)
