# Jido.AI Examples

The runnable agents, tools, and demo scripts for `jido_ai` live in this top-level `examples/`
folder. They stay out of the root `elixirc_paths`, so the core package does not compile example
modules by default.

Run everything from the repository root. `.env` is loaded from the repo root when present.

## Run Demo Scripts

```bash
mix run examples/scripts/demo/actions_llm_runtime_demo.exs
mix run examples/scripts/demo/actions_tool_calling_runtime_demo.exs
mix run examples/scripts/demo/actions_reasoning_runtime_demo.exs
mix run examples/scripts/demo/weather_multi_turn_context_demo.exs
```

## Run Example Agents

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.ReActAgent \
  "Should I bring an umbrella in Chicago this evening?"
```

## Test

```bash
mix test
```

## Optional Agent Guild observations

Use this example when the caller has selected an unfamiliar **public** HTTP(S) endpoint,
or supplied a shareable Agent Guild passport and independently known issuer/subject DIDs.
It is an ordinary pair of actions, not an execution interceptor. Neither action attaches
an endpoint, delegates work, registers an identity, provisions credits, or makes a payment.

The direct path requires no model. From the repository root, start `iex -S mix` and load
the actual example modules without calling the bootstrap's separate `init!/1`:

```elixir
Code.require_file("examples/scripts/shared/bootstrap.exs")

alias Jido.AI.Examples.Tools.AgentGuildPreflight
alias Jido.AI.Examples.Tools.AgentGuildVerifyPassport
alias Jido.AI.Actions.ToolCalling.ExecuteTool

# This call sends the selected URL to Guild and triggers a public-endpoint probe.
{:ok, observation} = Jido.Exec.run(
  AgentGuildPreflight,
  %{target: "https://example.com/agent"},
  %{},
  max_retries: 0
)

# In your application, supply these three values from the caller's task:
# public_passport_json: complete public credential JSON text, including its proof
# expected_issuer_did: an independently trusted Guild issuer did:key
# expected_subject_did: the independently known intended counterparty did:key
{:ok, verification} = Jido.Exec.run(
  ExecuteTool,
  %{
    tool_name: AgentGuildVerifyPassport.name(),
    params: %{
      "credential_json" => public_passport_json,
      "expected_issuer" => expected_issuer_did,
      "expected_subject" => expected_subject_did
    },
    timeout: 8_000
  },
  %{tools: %{AgentGuildVerifyPassport.name() => AgentGuildVerifyPassport}},
  max_retries: 0
)
```

`AgentGuildObservationAgent` is an optional real `Jido.AI.Agent` composition of those
actions. Creating it makes no model request. Asking it a question uses the host's model
and may incur provider charges. Its prompt advises explicit selection; this is not an
enforced human approval step or a guarantee of model behavior. Guards run inside each
action, including direct calls, independently of strategy-specific hooks.

The helper uses only fixed HTTPS routes at `https://agent-guild-5d5r.onrender.com`:
free `GET /preflight?url=...` and free `POST /credentials/verify`. It sends only the exact
selected URL or complete validated original public JSON text, with fixed public headers.
It does not forward action context, history, credentials, expected DIDs as extra fields,
or unrelated tool arguments. The service actively probes the endpoint and may record
the URL; verification attempts record `passport_verified`, including failures. Host,
model and framework logging remain governed by host settings. Publicness and independent
selection are caller responsibilities; the code cannot detect confidential JSON claims.

Endpoint input is at most 2,048 bytes. HTTP(S) is allowed; credentials, fragments,
whitespace, malformed Unicode and local/reserved literal addresses are rejected.
DNS names must have ordinary ASCII labels; Guild performs DNS screening and its own
probe policy. The helper does not resolve the target locally or establish ownership.
Exact target equality binds only this response to this request, never subsequent execution.

Each action has one HTTP attempt, no redirects or retries, a 6-second whole-request
deadline, and shorter pool/connect/read timeouts. The linked request task is killed on
deadline; this cannot undo a request or remote probe already received by Guild. Native
outer timeouts can return their own framework error if the caller sets them too short.
Response bodies are streamed and capped at 65,536 bytes; compressed bodies are rejected.
JSON input and responses are limited to 16 nested containers, with duplicate keys and
non-object roots rejected. No attacker-controlled detail, headline, claims, or instruction
text is forwarded in the output; negative and unavailable results use fixed local text.

The endpoint result preserves all six statuses and verifies the returned failed/unknown/
scored lists and verdict agree. Failed reachability or protocol checks mean the service
verdict is `do_not_delegate`; another failure means `delegate_with_caution`; otherwise
it is `no_failed_checks`. Unknown checks do not change that verdict. Card signing is a
**presence check**, not cryptographic validation; Guild registry history is not proof of
independent endpoint ownership. `observed_at_local` is the helper's local timestamp.

Passport verification accepts the current VC 2.0 `AgentGuildPassport` format with
`DataIntegrityProof` / `eddsa-jcs-2022`. The complete original JSON text is preserved
after parsing and duplicate checks, including numeric and escape representations.
The action separately enforces issuer/subject binding, proof method/purpose, identical
signed `validFrom` and `proof.created`, no future issue time, a fixed 24-hour maximum
age and an unexpired `validUntil` when present. This conservative example policy may
reject otherwise cryptographically valid older passports. Missing or stale passports
produce unavailable output; they do not trigger enrollment or a paid fallback.

The remote verifier must return boolean `valid` and `guild_issued` and the exact expected
DIDs. A negative signature result remains `verified: false`. Verification establishes
reported origin and integrity only, not safety, legal identity, current reputation,
task quality, payment entitlement, or DID-to-endpoint binding. `{:ok, result}` and
`ExecuteTool`'s success status mean the action completed; inspect the report's `status`
and `verified` fields. They never authorize hiring, payment, or execution.

Run the deterministic native examples with:

```bash
mix test test/jido_ai/examples/agent_guild_observation_test.exs
```

Tests use Jido's actual example loader, schemas, agent composition, `Jido.Exec`,
`ExecuteTool` and `Turn`, substituting only the HTTP adapter. They do not prove live
service behavior or cryptographic verification by the remote service. Source contracts:
[Guild preflight](https://github.com/AgentTanuki/agent-guild/blob/9cf6c561468e60afb77acdbddebfc5134a155e4f/live/guild/app/preflight.py),
[passport format](https://github.com/AgentTanuki/agent-guild/blob/9cf6c561468e60afb77acdbddebfc5134a155e4f/live/guild/app/vc.py),
and [verification response/logging](https://github.com/AgentTanuki/agent-guild/blob/9cf6c561468e60afb77acdbddebfc5134a155e4f/live/guild/app/store.py).
The example is original contribution code under this repository's Apache-2.0 license.
