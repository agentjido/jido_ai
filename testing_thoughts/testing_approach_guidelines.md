# ReqLLM – Comprehensive Testing Guidelines

This document translates the four architectural reports into an actionable, end-to-end testing approach your team can apply immediately.

## 1. Testing Strategy Tiers (The "ReqLLM Pyramid")

```
                             ┌───────────────────────────┐
                             │ 4. Integration / E2E      │  (real providers)
                             ├───────────────────────────┤
                             │ 3. Capability Tests       │  (mix req_llm.verify)
                             ├───────────────────────────┤
                             │ 2. Provider Contract      │  (build_request/parse_response)
                             ├───────────────────────────┤
                             │ 1. Unit Tests             │  (pure, mocked)
                             └───────────────────────────┘
```

**Tier 1 – Unit**  
- Goal: deterministic validation of **pure functions & structs**.  
- Scope: Data structures, schemas, utils, registry helpers, small core functions.

**Tier 2 – Provider Contract**  
- Goal: each provider obeys the `Provider.Adapter` behaviour & DSL expectations.  
- Scope: `build_request/3`, `parse_response/3`, error mapping, plugin hooks.  
- Isolation: HTTP fully mocked (Bypass) but **real provider module**.

**Tier 3 – Capability Verification**  
- Goal: advertised features in `models_dev/*.json` are **true in practice**.  
- Scope: `Core.CapabilityVerifier`, built-in and custom capabilities.  
- Driver: `mix req_llm.verify` (can point to sandboxed or real endpoints).

**Tier 4 – Integration / End-to-End**  
- Goal: prove the full critical path (#183–#192 in dependency report) still works against live APIs.  
- Scope: `ReqLLM.generate_text/stream_text/generate_object/embed`.  
- Tag: `@tag :integration` – run only in CI nightly or with `ALLOW_LIVE=1`.

## 2. Mock & Stub Strategy (per dependency layer)

| Dependency | Mock Tool | Pattern |
|------------|-----------|---------|
| HTTP (`Req`) | Bypass | Start Bypass \|> put_expect/3 \|> point base_url |
| Provider Registry | Mox | `expect(ProviderRegistryMock,…​)` then pass into functions |
| Configuration (`Core.Config`) | Patch or Application env | `Application.put_env/4` in setup |
| `:persistent_term` state | Helper | `ReqLLM.Test.reset_registry/0` that clears/re-seeds |
| SSE Streams | Bypass | send chunked `"data: {...}\n\n"` frames |
| File system (models_dev) | Temp path | `with_tmp_dir(fn -> … end)` or `Path.join(System.tmp_dir!,…)` |
| Async Tasks / Retry logic | `ExUnit.CaptureLog` + `Process.sleep/1` | assert back-off behaviour |

## 3. Layer-specific Testing Patterns & Examples

### A. Data Structures & Schemas (Tier-1)  
```elixir
use ExUnit.Case, async: true
alias ReqLLM.{Model, Message}

describe "Model.from/1" do
  property "never raises and returns {:ok, %Model{}}" do
    check all provider <- member_of([:openai, :anthropic]),
              name <- string(:printable) do
      assert {:ok, _} = Model.from("#{provider}:#{name}")
    end
  end
end
```
Tools: `StreamData` for property tests; no mocks required.

### B. Core Business Logic (Tier-1/2)  
```elixir
defmodule ReqLLM.Core.GenerationTest do
  use ExUnit.Case, async: true
  import Mox         # define ProviderMock implements Provider.Adapter
  setup :verify_on_exit!

  test "fallbacks to retries on 429" do
    ProviderMock
    |> expect(:build_request, fn _msgs, _, _ -> {:ok, Req.new(url: "/")} end)
    |> expect(:parse_response, fn _resp, _, _ -> {:error, {:http, 429}} end)

    {:error, {:max_retries, 3}} =
      Generation.generate_text(Model.from!("mock:turbo"), ["hi"], provider: ProviderMock)
  end
end
```

### C. Provider Contract (Tier-2)  
```elixir
defmodule ReqLLM.Provider.BuiltIns.OpenAITest do
  use ExUnit.Case
  import ReqLLM.Test.BypassHelpers   # thin wrapper around Bypass

  test "build_request encodes messages according OpenAI schema" do
    model = ReqLLM.model!("openai:gpt-4")
    {:ok, req} = OpenAI.build_request([ReqLLM.message!("hi")], [], model: model)

    assert req.headers["content-type"] == "application/json"
    assert Jason.decode!(req.body)["model"] == "gpt-4"
  end

  test "parse_response extracts text on 200" do
    bypass(fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"choices":[%{"message":{"content":"pong"}}]}))
    end)

    {:ok, resp} = Req.get(url: bypass_url())
    {:ok, "pong"} = OpenAI.parse_response(resp, nil, [])
  end
end
```

### D. Capability Verification (Tier-3)  
Add custom capability test modules and rely on task harness:

```elixir
defmodule MyApp.Capabilities.LowLatency do
  @behaviour ReqLLM.Capability
  def id, do: :low_latency
  def advertised?(model), do: model.annotations[:latency_ms] < 500
  def verify(model, _), do: {:ok, ReqLLM.generate_text!(model, "ping")}
end
```
Run in CI: `mix req_llm.verify --only low_latency`.

### E. Integration / Streaming (Tier-4)  
```elixir
@tag :integration
test "stream_text returns enumerable of binaries" do
  {:ok, resp} =
    ReqLLM.stream_text!("openai:gpt-3.5-turbo", [%{role: :user, content: "Hello"}])

  chunks = Enum.take(resp.body, 2)
  assert Enum.all?(chunks, &is_binary/1)
end
```
Guard with `System.get_env("OPENAI_API_KEY")` or `skip/1`.

## 4. Tooling & Frameworks

- **ExUnit** – default test runner.  
- **Mox** – mocks for behaviours (`Provider.Adapter`, `Kagi.Keyring`, etc.).  
- **Bypass** – local HTTP server for end-to-end request assertions.  
- **StreamData** – property & fuzz tests for codecs and schemas.  
- **ExCoveralls** – coverage reporting (`mix coveralls.json`).  
- **Credo** & **Dialyzer** – static analysis in CI.  
- **ExVCR** (optional) – record/live switch for provider integration tests.

Helper libs already in repo (suggested path: `test/support/`):  
`ReqLLM.Test.BypassHelpers`, `ReqLLM.Test.RegistryStub`, `ReqLLM.Test.Env`.

## 5. Coverage Goals & Quality Metrics

| Metric | Target |
|--------|--------|
| Line coverage (unit + contract) | ≥ 85 % |
| Mutation score (MutaEx) | ≥ 70 % |
| Credo - critical issues | 0 |
| Dialyzer warnings | 0 |
| PR must not drop coverage | enforced by CI |
| Performance budget (verify) | < 5 min (parallel tasks) |

## 6. Test Organisation & Structure

```
test/
  unit/              # Tier-1 (async)
  provider_contract/ # Tier-2
  capability/        # Tier-3  (can call mix task programmatically)
  integration/       # Tier-4  (tagged :integration, :slow)
  support/           # Common mocks, helpers
```

ExUnit filters in `test_helper.exs`:

```elixir
ExUnit.start(exclude: [:integration, :slow])
```
Run full suite locally: `MIX_ENV=test mix test --include integration`.

## 7. CI / CD Integration (GitHub Actions example)

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    env:
      MIX_ENV: test
      OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}   # only needed for :integration
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'
      - name: Cache deps
        uses: actions/cache@v3
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix test
      - run: MIX_ENV=test mix coveralls.json
      - run: mix credo --strict
      - run: mix dialyzer
  nightly-integration:
    if: github.event_name == 'schedule'
    runs-on: ubuntu-latest
    env:
      MIX_ENV: test
      ALLOW_LIVE: 1
      OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
    steps:
      # same install steps …
      - run: mix test --only integration
```

## 8. Quick-Start Checklist for Developers

1. `mix test` – fast feedback (tier-1 & 2).  
2. `mix req_llm.verify openai` – run advertised capability suite.  
3. `mix test --only integration` – before tagging a release.  
4. Add a **provider**?  
   - Implement callbacks → create `*_test.exs` in `provider_contract/`.  
5. Update **models.dev** metadata?  
   - Run `mix req_llm.model_sync` → add/adjust capability tests if needed.

---

**By following this layered, tooling-backed strategy you will:**

- Detect regressions early (unit & contract).  
- Guarantee metadata fidelity (capability & sync tests).  
- Keep user trust by routinely exercising real provider paths (integration).  
- Maintain high code quality and coverage enforced by CI.

**Happy testing!**
