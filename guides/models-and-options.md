# Models and Options

Every model call in Jido AI goes through [ReqLLM](https://hexdocs.pm/req_llm).
You choose the model, its fallbacks, and the ReqLLM options in three places:
the reasoning Flow's input schema, your Agent's `reasoning` defaults, and each
request. This guide covers how those layers combine, how ReqLLM finds
credentials, and what request options can't change. Read
[Define an AI Agent](define-an-ai-agent.livemd) first.

```elixir
defmodule MyApp.SupportAgent do
  use Jido.AI.Agent,
    id: "my_app/support_agent",
    vsn: 1,
    name: "support_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      fallback_models ["openai:gpt-4.1-mini"]
      options %{max_tokens: 256, temperature: 0.2}
    end

    tools do
      action MyApp.LookupOrder
    end
  end
end

# One request lowers the token limit
signal =
  MyApp.SupportAgent.request_signal!(%{
    input: "Where is order A-1001?",
    options: %{max_tokens: 64}
  })
```

This request calls `gpt-4o-mini` with `max_tokens: 64` and no `temperature`.
Request `options` replace the Agent's `options`. They don't merge.

## Model Names

A model name is a ReqLLM model spec, `"provider:model"`:

| Spec | Provider |
| --- | --- |
| `"openai:gpt-4o-mini"` | OpenAI |
| `"anthropic:claude-sonnet-4-5"` | Anthropic |
| `"openai:text-embedding-3-small"` | OpenAI embeddings |

ReqLLM resolves the spec against its model catalog when the call runs. The
schema checks only that `model` is a string. A bad spec fails the model call,
and the reply has `status: :failed` and `reason_code: :model`:

| Spec | `reason` |
| --- | --- |
| `"nope:model"` | `"unknown_provider"` |
| `"gpt-4o-mini"` | `"invalid_format"` |

The model must also support the operation.
`Jido.AI.Actions.Embed` with `"openai:gpt-4o-mini"` fails with
`"model: openai:gpt-4o-mini does not support embedding operations"`. See
[Embeddings](embeddings.livemd).

## Layered Defaults

The `jido.ai.request` route builds the Flow input in three layers. A later layer
replaces a top-level field from an earlier one:

| Layer | Set with | Example |
| --- | --- | --- |
| Flow schema default | The reasoning Flow module | ReAct `model` is `"openai:gpt-4o-mini"` |
| Agent default | The `reasoning ... do` block | `options %{max_tokens: 256, temperature: 0.2}` |
| Request field | The request Signal data | `%{options: %{max_tokens: 64}}` |

Replacement is per top-level field. A request `options` map replaces the whole
`options` map, including the Flow defaults. Put every option you need in it.

`explain/0` shows the Agent defaults. `preflight/1` shows the validated input
without running the Flow:

```elixir
MyApp.SupportAgent.explain().defaults
# => %{
#      model: "openai:gpt-4o-mini",
#      fallback_models: ["openai:gpt-4.1-mini"],
#      options: %{max_tokens: 256, temperature: 0.2}
#    }

{:ok, checked} = MyApp.SupportAgent.preflight(%{input: "Hi", options: %{max_tokens: 64}})
Map.take(checked.params, [:model, :fallback_models, :options, :stream])
# => %{
#      model: "openai:gpt-4o-mini",
#      fallback_models: ["openai:gpt-4.1-mini"],
#      options: %{max_tokens: 64},
#      stream: false
#    }
```

### Model Fields By Flow

Each Flow defines its own model fields and defaults. A request can set only the
fields its Flow defines. Any other key fails validation with
`"unrecognized key: <name>"`.

| Flow | `options` default | `fallback_models` | `stream` |
| --- | --- | --- | --- |
| `Jido.AI.Reasoning.ReAct` | `%{max_tokens: 128, receive_timeout: 30_000, temperature: 0.0}` | yes | yes |
| `Jido.AI.Reasoning.ChainOfThought` | `%{max_tokens: 512, receive_timeout: 30_000, temperature: 0.0}` | no | no |
| `Jido.AI.Reasoning.ChainOfDraft` | `%{max_tokens: 256, temperature: 0.0}` | no | no |
| `Jido.AI.Reasoning.AlgorithmOfThoughts` | `%{max_tokens: 1024, temperature: 0.0}` | no | no |
| `Jido.AI.Reasoning.TreeOfThoughts` | `%{max_tokens: 1536, temperature: 0.4}` | no | no |
| `Jido.AI.Reasoning.GraphOfThoughts` | `%{max_tokens: 1536, temperature: 0.3}` | no | no |
| `Jido.AI.Reasoning.TRM` | `%{max_tokens: 1536, temperature: 0.2}` | no | no |
| `Jido.AI.Reasoning.Adaptive` | none; passes `model` and `options` to the selected Flow | no | no |

Every built-in Flow defaults `model` to `"openai:gpt-4o-mini"`, except
Adaptive, whose `model` is optional. [Stream Model Output](stream-model-output.livemd)
covers `stream`.

## Options

`options` is a map of ReqLLM options. Jido AI converts it to a keyword list and
passes it to `ReqLLM.generate_text/3`, or to `ReqLLM.stream_text/3` when
`stream` is `true`. Common keys:

| Key | Meaning |
| --- | --- |
| `max_tokens` | Output token limit. ReqLLM maps it to the provider's field. |
| `temperature` | Sampling temperature. |
| `receive_timeout`, `total_timeout` | HTTP timeouts in milliseconds. |
| `max_retries` | ReqLLM's own HTTP retries. |
| `provider_options` | Provider-specific settings. |
| `api_key`, `base_url` | Credentials and endpoint for this call. |
| `req_http_options` | Options for the underlying Req request. |

ReqLLM validates the keys. An unknown key, such as `bogus_opt`, fails the
model call with a `NimbleOptions.ValidationError` message in `reason`.

Jido AI adjusts the options before each call:

| Key | What Jido AI does |
| --- | --- |
| `tools` | Sets the Agent's selected tools. |
| `tool_choice` | Removes your value. Sets one from the tool policy. |
| `output`, `output_validation` | Sets them from `output_schema`, with `:strict` validation. |
| `telemetry` | Adds `conversation_id`, the Thread ID. |
| `total_timeout` | Lowers it to the time left in `limits.elapsed_ms`. |
| `provider_options` | Adds prompt cache keys when `prompt_cache.enabled` is `true`. |

The prepared options are part of the Context snapshot in each entry of
`model_attempts`, with `api_key` replaced by `"[REDACTED]"`.
[Inspect Model Context](inspect-model-context.livemd) shows how to read it.

## Fallback Models

ReAct calls models in the order `[model | fallback_models]`. It moves to the
next model only after a retryable failure on the current one:

1. A model call fails. Jido AI marks it retryable for a timeout, a transport
   error, or HTTP status 408, 409, 425, 429, 500, 502, 503, or 504.
2. If the current model has used no more than `limits.retries` attempts
   (default `1`), ReAct calls the same model again.
3. Otherwise ReAct calls the next fallback model with a fresh attempt count.
4. A non-retryable failure, such as a 401, fails the request at once.

An output rejected by the output guard follows the same order: repair on the
same model, then the next model.

With the Agent above and two `503` responses from `gpt-4o-mini`, one request
records three attempts:

```elixir
Enum.map(reply.data.model_attempts, &{&1.model, &1.status, &1.outcome[:category]})
# => [
#      {"openai:gpt-4o-mini", :error, :unavailable},
#      {"openai:gpt-4o-mini", :error, :unavailable},
#      {"openai:gpt-4.1-mini", :ok, nil}
#    ]

{reply.data.status, reply.data.model_calls, reply.data.retries}
# => {:completed, 3, 2}
```

Every attempt counts against `limits.model_calls` (default `8`). All models
receive the same `options`, so keep provider-specific settings valid for every
model in the list. The other built-in Flows call one model and set
`fallback_models` to `[]`. [Budgets, Retries, and Fallbacks](budgets-retries-and-fallbacks.md)
covers limits and retry costs.

## Credentials

ReqLLM looks up the API key for the model's provider in this order:

1. The `api_key` option on the call.
2. Application config, such as `config :req_llm, openai_api_key: "..."`.
3. The environment variable, such as `OPENAI_API_KEY`. Under Mix, ReqLLM
   loads `.env` at startup. Releases skip `.env` unless you set
   `config :req_llm, load_dotenv: true`.

```elixir
# config/runtime.exs
config :req_llm,
  openai_api_key: System.fetch_env!("OPENAI_API_KEY"),
  anthropic_api_key: System.fetch_env!("ANTHROPIC_API_KEY")
```

`ReqLLM.put_key/2` sets a key at runtime, for example
`ReqLLM.put_key(:openai_api_key, key)`.

Keep keys in config, not in request `options`. A request Signal carries its
data wherever you queue, log, or store it.

With no key, `cmd/3` returns an error instead of a reply:

```elixir
{:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
  MyApp.SupportAgent.cmd(agent, signal)

message
# => "Invalid parameter: :api_key option, config :req_llm, openai_api_key, or OPENAI_API_KEY env var (.env via dotenvy)"
```

## Tools Stay Fixed

The Agent's `tools` block and trusted `Jido.AI.ToolSource` modules define the
tools a model can see. A request can't add or replace them:

- The ReAct schema has no `tools` field.
  `%{input: "Hi", tools: ["refund_everything"]}` fails with
  `"unrecognized key: tools"`.
- `options.tools` is replaced by the Agent's selected tools.
- `options.tool_choice` is removed. The `tool_policy.requirement` field sets
  the provider tool choice.

A request can narrow the Agent's tools with `tool_policy`. See
[Action Tools](action-tools.livemd) and
[Security and Portability](security-and-portability.md).

> #### Warning {: .warning}
>
> When a request selects no Agent tools, the current release passes
> `options.tools` through to ReqLLM unchanged. Don't accept `tools` in
> request options from untrusted callers.

## Offline Calls

The same `options` map points a request at a test double. These options send
the HTTP request to a `Req.Test` stub named `MyApp.LLM`:

```elixir
options = %{
  api_key: "offline-test-key",
  max_retries: 0,
  max_tokens: 128,
  req_http_options: [plug: {Req.Test, MyApp.LLM}]
}

MyApp.SupportAgent.request_signal!(%{input: "Where is order A-1001?", options: options})
```

Streaming uses Finch rather than Req, so it needs a `base_url` instead. See
[Mock Model Calls with ReqLLM](mock-model-calls-with-reqllm.livemd) and
[Stream Model Output](stream-model-output.livemd).
