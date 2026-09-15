# AI Agent authoring verification

This suite applies the core `jido/test/authoring` approach to AI Agents.
It has seven saved cases, eight construction paths, and 14 checked-in JSON
documents. Additional fixtures cover inline Actions, metadata, and invalid source.

Run the suite:

```sh
mix test.authoring
```

Run a group:

```sh
mix test test/authoring/agents/authoring_test.exs --only authoring
mix test test/authoring/agents/execution_test.exs --only authoring
mix test test/authoring/agents/interfaces_test.exs --only authoring
mix test test/authoring/agents/callable_profiles_test.exs --include authoring --seed 0
mix test test/authoring/agents/boundaries_test.exs --only authoring
mix test test/authoring/agents/known_bugs_test.exs --only authoring
```

Run it with the regular tests and examples:

```sh
mix test --include authoring --include example
```

Plain `mix test` excludes the `:authoring` tag, as core Jido does.
The suite has 238 expected-behavior tests. All nine findings have regression
tests for their resolved behavior. The file name `open_findings_test.exs` is
retained for review, but its four tests now assert the corrected contracts.
See [BUGS.md](BUGS.md). The default suite also checks these fixes in
`test/jido_ai/authoring/regressions_test.exs` and `resolved_findings_test.exs`.

## Cases and paths

| Case | Authoring and runtime contract |
| --- | --- |
| Simple | Shorthand model DSL, native turn route, generated Signal and call helpers |
| Tool | Declared Action, JSON tool arguments, real tool execution, next model request |
| Structured | Zoi output schema, structured provider request, typed result field |
| Session | Streaming, request records, history, successive requests, busy rejection |
| Multiple profiles | Independent models, routes and result fields; explicit selection |
| Policy and routing | Native custom-route rejection, model routing, unchanged state after rejection |
| Chain of thought | Alternate reasoning method with the same Agent construction paths |

Each saved case runs through:

1. Compiled `use Jido.AI.Agent` source.
2. Independent Agent attribute and profile maps passed to `Authoring.lower/2`.
3. Keyword Agent attributes with profile maps.
4. Validated `Profile` structs.
5. Incremental core Builder calls on lowered attributes.
6. A core Builder seeded from the authored module.
7. Saved source-profile JSON.
8. Saved lowered-Agent JSON.

There is no AI-specific Builder setter. The incremental path verifies that
lowered AI declarations survive the existing core Builder. Separate regression
tests check raw keyword profiles and map model shorthand at source boundaries.

Definition tests compare complete definitions and complete initial and override
state. They also check neutral identity, profile accessors, invalid state, and
three Codec cycles. Expected source and state live in `Cases`; they are not
extracted from the module being tested.

The two JSON formats serve different purposes. Source-profile documents are
small, independently authored tagged-data inputs. Lowered-Agent documents pin
core routes, Plugin ordering, and Registry references. Their Registry is supplied
by the host from the independently constructed definition. Neither format embeds
the implementation of a model, schema, or Action. Tests never rewrite the files.

Execution tests run every case/path pair against the shared
`Jido.AI.Test.MockLLM` local HTTP/SSE server. ReqLLM, Actions, tools, Flows,
AgentServer and session workers all run normally. The tests check provider
requests, selected models, state, rejected input, and recovery. Session
observations use request completion and explicit provider barriers, not sleeps.

The interface tests also compile inline instructions and a tool, then execute
the authored, Builder, and Codec forms. Invalid-source tests cover duplicate
profiles and models, missing results, unknown routes, wrong state fields,
history/result overlap, and invalid limits.

## Layout

```text
test/authoring/
  README.md
  BUGS.md
  agents/
    authoring_test.exs
    execution_test.exs
    interfaces_test.exs
    callable_profiles_test.exs
    boundaries_test.exs
    known_bugs_test.exs
    recovery_test.exs
    combinations_test.exs
    plugins_controls_test.exs
    output_limits_test.exs
    source_variations_test.exs
    transport_test.exs
    open_findings_test.exs
  support/
    compiler.exs
    agents/
      cases.exs
      corpus.exs
      fixtures/
        *.exs
        invalid/*.exs
        json/*.json
```

Test discovery loads only the support modules. Source fixtures compile when
selected tests run. They are outside `elixirc_paths` and are explicitly ignored
by test-file discovery. The compiler runs in a monitored process so Spark
`after_verify` errors reach the test with their original exception.

## Add a case

Add independent source data, state and request expectations to `Cases`.
Add a source fixture, source JSON, and lowered-Agent JSON. Use trusted Registry
entries for model and schema values. Add the variant to the list, then run
`mix test.authoring`. Review JSON changes as contract changes.

For a confirmed product bug, add a small active characterization and an entry
in [BUGS.md](BUGS.md). Keep the failure distinct from the positive corpus.
After a product fix, replace its characterization with the desired assertion
and update the catalog.

## Extended coverage

- Callable reasoning Plugins preserve their bound Profile through core Builder
  and Codec. The receiving host must supply its Profile Registry value. Tests
  reject wrong methods and invalid configuration, then execute prompt-only
  Signals into the selected result field without changing unrelated state.
- Provider errors and invalid tool arguments across all eight corpus forms,
  with domain-state checks and a successful later request.
- Mixed turn/session profiles through module, Builder, and Codec forms,
  separate provider endpoints, runtime prompt changes, empty prompts, and
  isolation between two instances.
- Generated cancellation, steering, waiting, disabled streaming, invalid
  queries, unrouted profiles, and first-declared route selection. Streaming
  helpers preserve profile-selection and busy-admission errors without changing
  the active request's state.
- Invalid DSL fixtures reject mixed model declaration forms, duplicate routers,
  conflicting skill paths, non-list extensions, and non-module extension entries.
- Custom stateful Plugin ordering and conditional operation controls through
  lowered, Builder, and Codec forms. Tool errors are checked separately from
  invalid tool input: tool errors can return to the model; invalid input fails
  before the Action runs.
- Structured output repair success and exhaustion, model-call limits, and
  session deadline cleanup. Provider barriers replace timing sleeps.
- Bounded map/keyword permutations, duplicate rejection, normalized metadata,
  and resolved application defaults across transport.
- Public map/JSON/YAML Agent imports execute against the local provider.
  A separate BEAM builds its own Registry, decodes checked-in source and Agent
  JSON, and executes a tool. This process test has the `coverage_external_vm`
  tag, consistent with the existing coverage exclusions.
- Separate-BEAM inline Action tests export a document in the parent process.
  The child compiles trusted source and builds its own Registry, then decodes
  the parent's document and runs inline instructions and a tool. Removing the
  required Profile value from the child Registry prevents execution. No Registry
  values or compiled BEAM binaries are sent by the parent.

Run the latest four regression tests separately with:

```sh
mix test test/authoring/agents/open_findings_test.exs --only authoring --seed 0
```

## Limits

This uses a fixed corpus and bounded source permutations, not general property
testing. It does not prove remote providers, long-running sessions, or
performance limits. Separate-BEAM transport covers both named tools and generated
inline Actions when the receiving host has the same trusted fixture source.
It does not test migration between different versions of that source.
It covers ReAct and chain of thought; the other reasoning methods, full skill
catalogs, browser adapters, and topology composition remain in their existing
focused suites. Native dynamic tool-source execution is explicitly rejected
(AI-AUTH-009); no real MCP or browser service is contacted. Native direct `Agent.cmd` execution returns a clear runtime
validation error (AI-AUTH-005); live AgentServer execution is the supported
runtime path here.
