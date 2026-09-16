# Jido AI example instructions

Adapted from `../jido/examples/AGENTS.md`. Keep the same learning and integration
standards, with AI-specific APIs and ownership rules below.

The examples are a first-class learning resource and a living integration test
suite. Apply these instructions to all files under `examples/`.

## Purpose

Each example must teach one main Jido AI capability. A stable example must:

- Use the current public V3 API.
- Show production-shaped code.
- Have a deterministic run path that needs no credentials.
- State what it proves and what it does not prove.
- Work as an independent integration fixture when practical.

Keep only examples that teach a distinct Jido AI capability. Do not add a stable
example for an application policy that only combines capabilities that the
learning path already covers. Put that policy in a guide or a larger demo
unless the composition itself teaches a new Jido AI contract.

The AI catalog uses its own numbered groups. Do not copy the core `01` through
`08` grouping or renumber existing examples without an explicit catalog change.
For the basic learning path, teach one answer, one tool, structured output,
controls, and streaming/session requests before alternate authoring forms or
runtime internals. Group `99_research`, when introduced, records proposed,
incomplete, or not yet promoted behavior. A research example must state its
status and must not present unsupported behavior as the normal Jido AI pattern.

A research README must name the current public contract, the remaining gap or
reason that promotion is deferred, the executable evidence, and the proof
limits. When the owning package closes the original gap, either promote the
lesson into the stable AI learning path or state the remaining promotion work.
Do not keep an
implemented research copy with no distinct purpose.

## Agent and Action authoring

Use `Jido.AI.Agent` and the AI DSL as the normal form for a static AI Agent.
Use `Jido.Agent, extensions: [Jido.AI.DSL]` when the lesson teaches core extension
composition. Do not build a manual model/tool/repair loop for a basic lesson
already served by the public AI runtime.

```elixir
use Jido.AI.Agent, name: "example_assistant"

agent do
  schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

  ai :assistant do
    model "openai:gpt-4o-mini"
    instructions "Answer the user's question."

    controls do
      timeout 5_000
      max_model_calls 2
    end

    result into: :reply
  end
end

routes do
  signal_source "/examples/ai/basic"

  route "examples.ai.basic.answer", ai: :assistant do
    define :answer, args: [:query]
  end
end
```

The model ID illustrates application configuration. The deterministic test path
must bind the local HTTP/SSE model server through supported runtime options;
it must not call that remote provider. Run native AI requests through AgentServer.
Direct native AI `Agent.cmd` execution is not the supported runtime path.

Callable reasoning accepts only a prompt. Bind a resolved Profile
in host context under `:jido_ai_callable_profile`, or in a reasoning Plugin's
`profile` configuration. Do not teach flat method/model/timeout inputs or
Plugin state defaults. A raw reasoning tool must explicitly forward the Profile
binding. Bind deterministic provider options under `context.ai[profile.id]` for
each Profile, including nested calls; an outer Profile's transport does not
configure a differently named inner Profile. Check that the complete local
script was consumed. Keep detailed method and deadline matrices in unit tests.

Follow these rules:

1. Put the main Agent module first in the primary source file.
2. Use an inline Action when only one route uses the behavior.
3. Omit an explicit `name` from an inline Action. The inline Action compiler
   gives it a stable generated name. Add a name only when the lesson must refer
   to that identity.
4. Use an inline Flow step when only one Flow uses the step.
5. Give every Flow an explicit `output` statement. Select the complete result
   that the caller or Agent will receive, even when the final step seems clear.
6. Add `output_schema` when a concrete output contract protects a reusable Flow
   or teaches output validation. Do not add a broad schema only to fill the
   option.
7. Move calculations to private functions before you create a named Action.
8. Use a named Action only when it is reused, needs a stable module identity,
   is a first-class extension point, or is the subject of the example. A named
   model-callable Action is valid when its stable tool identity or reuse is part
   of the lesson; do not replace it mechanically with an inline Action.
9. Use Builder, JSON, or direct definition forms only when the example teaches
   those forms.
10. Use the generated `ask`, `ask_sync`, and `ask_stream` API for AI work.
    Use core `define` for domain commands or an explicit admission lesson.
    A core route helper returns the admission Agent, not the AI answer.
11. Use static Zoi schemas at Agent, Action, and Flow boundaries.
12. Use Action or Signal input for requested work. Use execution context for
    runtime services and execution metadata. Use Agent state for durable domain
    data.
13. Keep runtime clients, callbacks, PIDs, references, and other temporary values
    in execution context. Do not put them in Agent state, Signals, or Directives.
14. Do not call another `Jido.Action` module's `run/2` function directly. Run the
    Action through a Flow, route, or public executor so that input validation,
    context handling, and instrumentation remain active.
15. Validate a complete plan from an external source before any side effect
    starts. This rule applies to model-selected tools, parallel work, and other
    plans that can cause more than one operation.
16. Give every retry, repair loop, and tool loop an explicit application limit.
    Document the result when the limit is reached.
17. Return a complete candidate state. Keep post-commit effects in Directives
    and Plugin dispatch.
18. Do not use raw `send` or `receive` in an example Action or Flow body. Use
    Signals and Directives for domain communication. Do not pass test-only
    observers, blockers, gates, or work functions through execution context.

Raw `send` and `receive` are permitted in unit tests and test support. Use them
there to build deterministic barriers and process monitors. Use a bounded wait,
or prove that cancellation and test cleanup always terminate an intentional
unbounded wait.

Use public ReqLLM calls when the lesson teaches model aliases or direct provider
integration. That is an explicit exception to the AI Agent form. Do not use
internal `Jido.AI.Execution.*` or `Jido.AI.Operations.*` calls as a basic teaching API.
Keep explicit Flow orchestration only when that composition is the lesson.

## Runtime inspection and control

Use public Jido AI request, stream, and session APIs to observe and control AI
work. Prefer generated request helpers, `Jido.AI.Request.await/2`,
`Jido.AI.Request.Stream.events/2`, and public `Jido.AI.Orchestration`
cancellation and inspection. `Jido.Session` is a portable value, not the live API.
Use public core AgentServer APIs for the core Turn itself. Do not confuse an AI
request's lifetime with the admission Turn that starts it. Keep streams and
runtime handles outside portable Agent state.

Follow these rules:

- Keep the operation under test separate from the code that observes it.
- Do not add an observer callback, blocking callback, hidden command, or other
  example-only shim to make runtime state visible.
- Do not inspect private process state or depend on internal messages, private
  functions, or undocumented runtime structure.
- A debug API can inspect an active Turn. It must not be used as the operation
  that keeps the Turn active.
- When a test needs an active Turn for a deterministic period, put the blocking
  Action or barrier in test support. Use it only to create the test condition.
  Inspect and control the Turn through public Jido APIs.
- Keep raw `send` and `receive` inside that test fixture. Use bounded waits, or
  prove that cancellation and cleanup terminate the fixture.
- Do not present a test fixture as application architecture in example source
  or documentation.

If a documented behavior cannot be observed or controlled through a clean
public API, treat this as an API gap in the owning package (Jido AI, core Jido,
or ReqLLM). Do not hide the gap with an
example-only adapter or callback. Record the missing contract and its use case,
add the API and its contract tests in the package that owns the behavior, and
then update or promote the example. Keep the example in `99_research` when the
required public contract does not yet exist.

## Names and routes

- Use the numbered folder name for the example ID and a descriptive concept
  name for modules.
- Scope Signal types to the section, example, and command.
- Scope Signal sources to the example.
- Use exact routes for commands exposed with `define`.
- Keep names stable after an example becomes part of the published learning
  path.

## File layout

Use this layout:

```text
examples/
  support/                  # Small modules used by two or more sections

  NN_section/
    README.md
    support/                # Modules used by two or more section examples

    NN_MM_example/
      README.md
      agent.ex              # Main Agent; flow.ex for a Flow-only lesson
      worker.ex             # A first-class part of the lesson
      demo.exs              # Optional executable demonstration
      support/              # Scaffolding used only by this example
      fixtures/             # JSON and other input data
```

Apply these placement rules:

- Keep code with its numbered example by default. A reader must not have to
  search the repository to understand the main behavior.
- Keep first-class Agents, Flows, Plugins, protocols, and worker roles at the
  numbered example folder root.
- Put adapters, fake services, observers, formatters, and runtime scaffolding in
  the numbered example `support/` folder.
- Put a module in the section `support/` folder only when two or more examples
  in that section use the same behavior.
- Put a module in `examples/support/` only when examples in two or more sections
  use the same behavior. This folder is suitable for small shared Actions,
  common Signal helpers, and other stable example building blocks.
- Use `JidoAI.Examples.Support.*` for new modules in `examples/support/`. Use a
  clear role name such as `KeepState`, not a generic name such as `Helpers`.
- Keep `examples/support/` small. Do not move code there only to make one source
  file shorter. Do not add a shared abstraction when local code is easier for a
  reader to understand.
- Do not make one numbered example depend on private support from another
  numbered example. Move the code to section support or `examples/support/`,
  based on the scope of reuse.
- Keep fixture data beside its consumer in `fixtures/`.
- Keep a section-level launcher at the section root only when it starts more
  than one numbered example. Put other launchers in their numbered folder.
- Mirror each numbered source folder under `test/examples/`.
- Keep shared example test helpers in `test/examples/support/` under the
  package's test instructions.

Do not split a file only because it is long. Split it by domain role. Keep the
main Agent state, Plugins, and routes easy to find. Do not hide a system role
that the lesson teaches in a generic support file.

## Documentation

Every numbered example must have a short `README.md`. It must contain:

- The problem that the example solves.
- The main concepts that it teaches.
- The recommended file reading order.
- An exact run command.
- The expected result.
- Important failure, recovery, or cleanup behavior.
- Explicit limitations and non-goals.
- Links to its source and tests.
- Direct links to shared support modules that the example uses.
- Links to the previous and next examples when sequence matters.

Start with this template and keep it short:

```markdown
# NN_MM Example title

One sentence that states the problem and the result.

## What you will learn

- Main Jido AI concept.
- Important boundary or failure behavior.

## Read the code

Read [the main source](agent.ex) first. Then read any first-class worker,
Plugin, or shared support files that are part of the lesson.

## Run it

`mix test test/examples/NN_section/NN_MM_example --include example --seed 0`

Expected result: describe the visible state, output, or process behavior.

## Important behavior

Describe the main success case and the important failure, recovery, or cleanup
case.

## Limits

State what this example does not prove or support.

## Files

- [Source](agent.ex)
- [Tests](../../../test/examples/NN_section/NN_MM_example/example_test.exs)
- [Shared support](../support/shared_action.ex), when used

Previous: [NN_MM Previous](../NN_MM_previous/README.md) | Next: [NN_MM Next](../NN_MM_next/README.md)
```

A section README must give the learning order and a short description of each
example. Do not copy detailed implementation text into the section README.

Live provider demonstrations must be optional. The default example and its
tests must not need external network access or an API key. Loopback HTTP/SSE to
the deterministic model server is permitted. Mock provider responses only;
keep real ReqLLM transport, Jido Actions, Flows, validation, and AgentServer
execution. Provider barriers and test observers belong in test support, not in
application-shaped example Actions. Never put credentials in
source, state, Signals, Directives, fixtures, or test output.

Use comments to explain Jido boundaries and important design decisions. Do not
use comments to describe each code statement.

## Example tests

Every stable example must have at least one behavior test with the `:example`
tag. The test must:

- Use public Jido APIs.
- Prove the main claim in the example README.
- Include the main success case.
- Include one important failure, recovery, or cleanup case when applicable.
- Use deterministic adapters and explicit synchronization barriers.
- Avoid `Process.sleep/1` and timing-only completion checks.
- Confirm process and resource cleanup when the example starts children or
  external resources.

Keep detailed implementation edge cases in `test/jido_ai/`. Keep construction
matrices, transport permutations, and complete definition equivalence in the
separate `test/authoring/` suite. Do not copy the same
assertion set into core and example tests. Example tests must read as a clear
proof of the documented behavior.

Run the focused section test after a change:

```sh
mix test test/examples/NN_section --include example --seed 0
```

Run the full example suite when shared support, catalog files, or more than one
section changes:

```sh
mix examples --seed 0
```

## Catalog integrity

The folder tree is the source of truth for example counts. Catalog checks must
verify:

- Folder IDs and order.
- The required README, source, and test files. A direct public-API lesson may
  keep executable calls in its matching test instead of adding an empty Agent
  module; document that exception.
- Documentation links.
- One matching test folder for each stable example.
- No undocumented stable example.
- No skipped stable example test.

Do not put manual pass counts or dated suite status in documentation unless a
tool generates and verifies them. Historical results already recorded elsewhere
are evidence snapshots, not a substitute for rerunning the suite.

Existing skipped upstream regressions do not satisfy the stable-example rule.
Keep their issue link and reproduction visible until fixed or explicitly
reclassified. Do not delete, weaken, or silently unskip them to claim compliance.
Dynamic tool sources remain deferred. Rich-model export is out of scope; core
Registry references do not make model records independently portable.

## Review checklist

For each section review:

1. Confirm the learning order and the main claim of each example.
2. Check Agent DSL use and convert one-use named Actions to inline Actions.
3. Record each valid exception to the inline Action rule.
4. Move support files to the correct scope.
5. Add or update each numbered README.
6. Keep example tests focused on documented public behavior.
7. Run the focused section test.
8. After removal or renumbering, delete empty folders and verify that source
   folders, test folders, and README links still match.
9. Report guideline gaps and lessons that can improve these instructions.
