# Adding a New Provider to ReqLLM  
_A practical, end-to-end guide_

This document explains everything you need to ship a first–class provider (e.g. OpenAI, Gemini) **and test it** inside ReqLLM. Follow the sections in order; the checklist at the end summarises the steps.

---

## 1. Provider implementation architecture

### 1.1 Create the provider module

```
lib/req_llm/providers/openai.ex
```

```elixir
defmodule ReqLLM.Providers.OpenAI do
  @moduledoc "OpenAI provider (Chat Completions v1)."

  @behaviour ReqLLM.Provider          # ❶ required behaviour

  use ReqLLM.Provider.DSL,            # ❷ declarative metadata/registration
    id: :openai,
    base_url: "https://api.openai.com/v1",
    metadata: "priv/models_dev/openai.json"  # capability map, see §3

  defstruct [:context]                # ❸ lightweight struct that wraps Context

  @type t :: %__MODULE__{context: ReqLLM.Context.t()}

  # ❹ Behaviour callbacks ---------------------------------------------------

  # Wrap a ReqLLM.Context in your struct
  @impl ReqLLM.Provider
  def wrap_context(%ReqLLM.Context{} = ctx), do: %__MODULE__{context: ctx}

  # Attach request options, headers, URL, body…
  @impl ReqLLM.Provider
  def attach(request, %ReqLLM.Model{} = model, opts \\ []) do
    api_key = System.fetch_env!("OPENAI_API_KEY")
    ctx     = ReqLLM.Codec.Helpers.wrap(model, opts[:context] || default_ctx(request.body))

    body =
      ctx
      |> ReqLLM.Codec.encode()
      |> Map.merge(model_params(model, opts))
      |> Map.put(:stream, opts[:stream] || false)

    request
    |> Req.Request.put_header("authorization", "Bearer #{api_key}")
    |> Req.Request.put_header("content-type", "application/json")
    |> Req.Request.merge_options(base_url: opts[:base_url] || default_base_url())
    |> Map.put(:body, Jason.encode!(body))
    |> Map.put(:url, URI.parse("/chat/completions"))
    |> maybe_install_stream_steps(opts[:stream])
  end

  # Parse the final non-streaming response
  @impl ReqLLM.Provider
  def parse_response(%Req.Response{status: 200, body: body}, _model) do
    chunks = %__MODULE__{context: body} |> ReqLLM.Codec.decode()
    {:ok, chunks}
  end
  def parse_response(%Req.Response{status: status, body: body}, _), do:
    {:error, to_error("API error", body, status)}

  # Parse chunked Server-Sent-Events
  @impl ReqLLM.Provider
  def parse_stream(%Req.Response{status: 200, body: chunk}, _model) when is_binary(chunk) do
    {:ok, chunk |> parse_sse() |> Stream.reject(&is_nil/1)}
  end
  # …

  # Optional: usage extraction
  @impl ReqLLM.Provider
  def extract_usage(%Req.Response{body: %{"usage" => u}}, _), do: {:ok, u}
  def extract_usage(_, _), do: {:ok, %{}}

  # -------------------------------------------------------------------------
  # private helpers (model_params/parse_sse/to_error/…)
end
```

Key points:

1. **`@behaviour ReqLLM.Provider`** – forces you to implement all required callbacks.  
2. **`use ReqLLM.Provider.DSL`** –  
   • registers the provider under `:openai`  
   • injects compile-time metadata helpers (`default_base_url/0`, etc.)  
3. The struct is only a thin wrapper; do **not** keep API-specific state here.  
4. Keep `attach/3`, `parse_response/2`, `parse_stream/2`, `extract_usage/2` small; delegate heavy lifting to helper functions to keep them readable.

### 1.2 Implement the Codec

Codec translates between **ReqLLM's generic context/stream chunks** and the provider-specific wire format.

```
lib/req_llm/providers/openai/codec.ex
```

```elixir
defimpl ReqLLM.Codec, for: ReqLLM.Providers.OpenAI do
  # OUTBOUND  (Context → provider JSON)
  def encode(%ReqLLM.Providers.OpenAI{context: ctx}) do
    %{
      messages: Enum.map(ctx.messages, &encode_msg/1)
    }
  end

  # INBOUND (provider JSON → list(StreamChunk.t()))
  def decode(%ReqLLM.Providers.OpenAI{context: %{"choices" => choices}}) do
    choices
    |> Enum.flat_map(fn %{"message" => %{"content" => text}} ->
      [ReqLLM.StreamChunk.text(text)]
    end)
  end

  # helper(s)…
end
```

Start with **text only**; add images, tool calls, thinking tokens later.

---

## 2. Capability system

* Capabilities determine which high-level features a model supports (`:streaming`, `:tools`, `:temperature`, …).  
* The lookup is **data-driven**: `priv/models_dev/openai.json` contains a top-level `"provider"` section plus a `"models"` list.

Example snippet:

```json
{
  "provider": {
    "env": ["OPENAI_API_KEY"]
  },
  "models": [
    {
      "id": "gpt-4o-mini",
      "max_tokens": 8192,
      "temperature": true,
      "top_p": true,
      "streaming": true,
      "tool_call": true,
      "reasoning": false
    }
  ]
}
```

Rules:

1. Every boolean field maps to a capability inside `ReqLLM.Capability` (see mapping in `capability.ex`).  
2. Add **new JSON keys** if the feature is brand-new, then extend the mapping function so the new capability becomes discoverable.  
3. Put the file under `priv/models_dev/`; the `metadata:` path in the DSL must match.

---

## 3. Testing strategy with the LiveFixture system

### 3.1 Why two kinds of tests?

1. **Unit tests** – No network, pure functions (codec, helpers, error mapping).  
2. **Coverage tests** – Exercise the real HTTP stack. They run in two modes:
   • **Fixture mode (default)** – Reads canned JSON so CI is fast, deterministic, and free.  
   • **Live mode** – `LIVE=true mix test` will hit the real API and overwrite/add fixtures.

### 3.2 Directory layout

```
test/
└── coverage/
    └── openai/            # provider-specific suite
        ├── core_test.exs  # basic happy-path tests
        ├── streaming_test.exs
        └── ...
fixtures/
└── openai/
    ├── basic_completion.json
    ├── streaming_delta.json
    └── ...
```

The fixtures folder is automatically created by `ReqLLM.Test.LiveFixture`.

### 3.3 Writing a coverage test

```elixir
defmodule ReqLLM.Coverage.OpenAI.CoreTest do
  use ExUnit.Case, async: false
  @moduletag :coverage
  @moduletag :openai

  alias ReqLLM.Test.LiveFixture
  @model "openai:gpt-4o-mini"

  test "simple completion" do
    result = LiveFixture.use_fixture(:openai, "simple_completion", fn ->
      ctx = ReqLLM.Context.new([ReqLLM.Context.user("Ping!")])
      ReqLLM.generate_text(@model, ctx, max_tokens: 3, temperature: 0)
    end)

    {:ok, resp} = result
    assert resp.status == 200
    assert resp.body =~ "Pong"
  end
end
```

Guidelines:

* Keep prompts **deterministic** (temperature `0`, short `max_tokens`) to minimise drift.  
* Wrap every network call with `LiveFixture.use_fixture/3` – the helper decides whether to hit the live API.  
* Make at least one streaming test to verify `parse_stream/2`.

### 3.4 Running tests

* All unit tests  
  ```bash
  mix test --exclude coverage
  ```
* Coverage tests (fixture mode)  
  ```bash
  mix test --only coverage
  ```
* Live round-trip against real API (updates fixtures)  
  ```bash
  LIVE=true mix test --only coverage --only openai   # single provider
  ```
* CI (recommended): run both
  ```bash
  mix test --exclude coverage      # fast unit layer
  mix test --only coverage         # fixture layer
  ```

---

## 4. Best practices

1. **Respect rate-limits** – throttle in `attach/3` if needed.  
2. **Cheapest model first** – pick the smallest public model for fixtures.  
3. **One fixture per feature** – easier updates and targeted re-recording.  
4. **Never commit secrets** – rely on `provider.provider.env` list for env var names.  
5. **Keep code symmetric** – everything added to `encode/1` must be handled in `decode/1`.  
6. **Stream minimal data** – in streaming tests, stop after a handful of chunks to curb cost.  
7. **Update fixtures proactively** – run `LIVE=true mix test --only coverage --only openai` after API changes.  
8. **Document quirks** in the module's `@moduledoc`: max token limits, unsupported params, etc.

---

## 5. Developer checklist

- [ ] Create `lib/req_llm/providers/<provider>.ex` with Provider behaviour + DSL.  
- [ ] Add `lib/req_llm/providers/<provider>/codec.ex` implementing `ReqLLM.Codec`.  
- [ ] Create `priv/models_dev/<provider>.json` with model list & capability flags.  
- [ ] Write unit tests for codec, helpers.  
- [ ] Add coverage test suite under `test/coverage/<provider>/`.  
- [ ] Record initial fixtures:
      `LIVE=true mix test --only coverage --only <provider>`  
- [ ] Document required env vars in the @moduledoc and JSON metadata.  
- [ ] Submit PR. CI must pass both unit and fixture layers.

Happy hacking & welcome to the ReqLLM provider ecosystem!
