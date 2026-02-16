# The Elixir Library Documentation Manifesto v1

Principles from direct response copywriting adapted for technical library documentation—evolved for monorepo ecosystems like JidoWorkspace. These aren't theories—they're proven principles for getting developers to understand, adopt, and successfully use your library.

---

## The ten foundational laws of library documentation

**1. You cannot create need—only channel it.** Developers arrive with existing problems. Your job is to show how your library solves what they're already trying to solve. Research the actual Stack Overflow questions, ElixirForum threads, and GitHub issues that lead people to need your solution. Use their exact terminology.

**2. The README headline consumes 80% of your adoption potential.** Most developers decide within 5 seconds whether to keep reading. A vague description kills interest in even brilliant libraries. Obsess over your opening line before anything else.

**3. The sole purpose of each sentence is to get the next one read.** Every line in your docs—module description, function doc, guide section—exists only to pull developers deeper. If any sentence can be skipped without loss, cut it.

**4. Specificity is the soul of credibility.** "High performance" means nothing. "Handles 50K messages/second on a single node" means something. Benchmarks, concrete examples, and exact use cases force binary judgment (useful/not useful) rather than vague dismissal.

**5. The API design beats documentation.** A well-designed API with mediocre docs outperforms a confusing API with extensive docs. Great API + weak docs = adoption. Weak API + great docs = frustration. Fix the API before polishing prose.

**6. Show the "after" state first.** Developers want to see what their code will look like. Open with the result, then explain how to get there. The emotional response ("that's clean!") precedes the rational analysis of how it works.

**7. Enter the conversation already in their head.** Documentation must begin where the developer IS—not where you want them to be. A developer debugging a GenServer crash needs different content than one evaluating architectural options.

**8. The developer isn't a moron—she's your colleague.** Don't over-explain Elixir basics to Elixir developers. Don't condescend. Tell the truth about limitations. Make the truth about capabilities fascinating.

**9. Test your documentation.** Clone your repo fresh. Follow your own quickstart. Do the examples compile? Does `mix deps.get && mix test` actually work? Let reality decide, not memory.

**10. Write to one developer, never "users."** "Users can configure..." fails. Picture one specific developer at their keyboard. Use "you" naturally: "You can configure..." / "When you call..."

---

## Developer awareness: the strategic foundation

Developers arrive at your documentation in different states. Mismatching your content to their state creates immediate bounce.

| Level | Developer's state | Your lead strategy |
|-------|------------------|-------------------|
| **Ready to Use** | Knows your library, ready to install | Lead with installation and quickstart |
| **Evaluating** | Knows your library, comparing options | Lead with differentiators, benchmarks, production examples |
| **Solution Seeking** | Knows solutions exist, found you via search | Lead with problem statement, then reveal your approach |
| **Problem Aware** | Has the pain, searching for any solution | Lead with problem crystallization, show you understand |
| **Unaware** | Doesn't know they have this problem | Lead with scenario or story that creates recognition |

**Implementation rule:** Your README must work for multiple awareness levels simultaneously. Structure it as a funnel: headline catches the problem-aware, first paragraph hooks solution-seekers, quickstart serves the ready-to-use, detailed sections convince evaluators.

---

## Ecosystem documentation

You're not documenting a single library—you're documenting an ecosystem. There are three distinct layers:

### 1. Package layer (each Hex package)

Each package is independently usable from Hex. This is where external developers land.

**Primary artifacts:** Package README, HexDocs guides, module/function docs
**Audience:** External Elixir developers installing from hex.pm

### 2. Cross-package recipes (agentjido.xyz)

Show how multiple libraries work together (e.g., `jido` + `jido_ai` + `jido_chat`). These live on the main docs site at agentjido.xyz, powered by `jido_workbench`.

**Primary artifacts:** Getting started guides, tutorials, architecture overviews
**Audience:** Developers evaluating or adopting the Jido ecosystem

### 3. Contributor documentation (internal)

For maintainers working in the development workspace. Never published externally.

**Primary artifacts:** `AGENTS.md`, `PACKAGE_TREE.md`, workspace README
**Audience:** Contributors only

**Routing rule:** Put *API details* in HexDocs; put *ecosystem overviews and tutorials* on agentjido.xyz; keep *contributor workflows* internal.

**Implementation rule:** Package docs assume "Elixir dev discovering you via HexDocs" awareness. Site docs on agentjido.xyz assume "developer evaluating Jido" awareness. Never leak internal tooling (`jido_dep/4`, workspace commands) into public docs.

---

## README architecture

### The optimal structure

```markdown
# LibraryName

[One sentence: What problem this solves for whom]

[One paragraph: The "after" state—what your code looks like with this library]

## Where This Package Fits

[One short paragraph explaining how this package fits into the Jido ecosystem:
core / AI / app / extension / utility. Link to the ecosystem overview on agentjido.xyz.]

**Works best with:**
- [jido](https://hex.pm/packages/jido) – [1 line: why]
- [jido_ai](https://hex.pm/packages/jido_ai) – [1 line: why]

## Installation

[Minimal steps to get started—deps, config, nothing else]

## Quick Start

[One complete, working example that demonstrates core value]

## Why This Library?

[Differentiators, design philosophy, when to use vs. alternatives]

## Documentation

[Link to HexDocs]

## Features

[Bullet list of capabilities]

## Examples

[2-3 real-world use cases with code]

## License
```

### Package README guidelines

Each package README must answer:
- "Is this a core package, extension, app, or utility?"
- "What are its key dependencies in this ecosystem?" (link to hex.pm packages)

For high-level packages (e.g., `jido_chat`, `jido_code`), mention any **implicit transitive expectations** ("Assumes you already have a Jido app running" vs "Can be used stand-alone").

### The headline formula

Your first line must pass the "5-second test." Developers should know immediately:
- What category of tool this is
- What problem it solves
- Whether it's relevant to them

**Weak:** "A powerful Elixir library for working with data"

**Strong:** "Runtime introspection for BEAM applications—surface process bottlenecks, memory leaks, and supervision tree issues in production"

**Strongest pattern:** `[Action verb] [specific outcome] for [specific context]`

---

## The code example hierarchy

Code examples are your most powerful documentation tool. They bypass explanation and show reality.

### First example: immediate value

```elixir
# BAD: Shows API surface
MyLib.configure(option: :value)
MyLib.do_thing()

# GOOD: Shows complete, working transformation
# Before: Manual, error-prone approach
defmodule MyApp.Worker do
  def process(data) do
    case validate(data) do
      {:ok, valid} ->
        case transform(valid) do
          {:ok, result} -> {:ok, save(result)}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end
end

# After: With MyLib
defmodule MyApp.Worker do
  use MyLib.Pipeline

  def process(data) do
    data
    |> validate()
    |> transform()
    |> save()
  end
end
```

### The example progression

1. **Quickstart:** Minimal working example (copy-paste-run)
2. **Common case:** The 80% use case with realistic data
3. **Edge cases:** Error handling, configuration, customization
4. **Advanced:** Full production setup, integration patterns

### Specificity in examples

| Vague | Specific |
|-------|----------|
| `data` | `%User{name: "Jane", email: "jane@example.com"}` |
| `some_value` | `{:ok, 42}` |
| `# configure as needed` | `config :my_lib, pool_size: 10, timeout: :timer.seconds(30)` |
| `MyModule.function()` | `MyLib.validate(%{email: "test@example.com"})` |

---

## Cross-package recipes (agentjido.xyz)

In an ecosystem, the most valuable examples show how multiple packages work together. These recipes live on agentjido.xyz (powered by `jido_workbench`), not in individual package docs.

For Jido-style packages, aim for at least:

1. **Core recipe** – e.g., "Start a Jido agent that calls an LLM"
   - Uses `jido` + `jido_ai`
2. **App recipe** – e.g., "Add a chat room with agents"
   - Uses `jido` + `jido_ai` + `jido_chat`
3. **Tooling recipe** – e.g., "Use Jido Code to drive agentic coding workflows"
   - Uses `jido_code` + core packages

**Rule:** Recipes on agentjido.xyz must:
- List all participating packages explicitly with hex.pm links
- Include a dependency diagram or bullet list
- Be copy-paste-runnable with Hex deps (no workspace assumptions)

**Package HexDocs can link to agentjido.xyz** for cross-package tutorials, but should not duplicate that content.

---

## Module and function documentation

### The @moduledoc formula

```elixir
@moduledoc """
[One sentence: What this module does]

[One paragraph: When and why you'd use it]

## Examples

    [Complete, working example]

## Options

[If applicable, document options here]
"""
```

### The @doc formula

```elixir
@doc """
[One sentence: What this function does, starting with a verb]

[When to use it, what it returns, edge cases worth knowing]

## Examples

    iex> MyLib.function(input)
    expected_output

    iex> MyLib.function(edge_case)
    edge_case_output
"""
```

### Documentation anti-patterns

**Tautological docs:**
```elixir
# BAD
@doc "Starts the server"
def start_server(opts), do: ...

# GOOD
@doc """
Starts a supervised connection pool to the configured database.

Returns `{:ok, pid}` on success. Crashes if the database is unreachable
after `connect_timeout` (default: 5 seconds).
"""
def start_server(opts), do: ...
```

**Obvious parameter descriptions:**
```elixir
# BAD
@doc """
## Parameters
- `user` - The user
- `opts` - The options
"""

# GOOD: Only document non-obvious parameters
@doc """
## Options
- `:timeout` - How long to wait for confirmation (default: 5000ms)
- `:retry` - Whether to retry on network failure (default: false)
"""
```

---

## Elixir documentation mechanics

### ExDoc & HexDocs

Your package's docs live on HexDocs—treat them as the primary entry point for external developers.

**Checklist for each package:**

- `mix.exs`:
  - `docs: [main: "readme", extras: ["README.md", "guides/getting_started.md"]]`
  - `source_url: "https://github.com/agentjido/<package>"`
  - `source_ref: "v1.2.0"` (tag that matches the Hex release)
- `mix docs` runs cleanly locally
- README examples compile as doctests or minimal `.exs` scripts

**Rule:** Every "Quickstart" in the README should also be runnable from HexDocs (no workspace-only assumptions like local paths).

### Typespecs and @typedoc

Typespecs are part of your API. They power Dialyzer, editor tooling, and human understanding.

- Use `@typedoc` for your public types:

  ```elixir
  @typedoc """
  Represents a running Jido agent process.

  Returned from `Jido.start_link/1` and used in all agent APIs.
  """
  @type agent_ref :: pid()
  ```

- Prefer named types in docs and specs over raw maps/tuples in examples
- For complex data structures, link from `@moduledoc` to the core type

### Behaviours and extension points

In an ecosystem like Jido, behaviours define how developers plug custom logic into your system.

For each `@behaviour`:

- Document it in its own module with:
  - A clear overview: "Implement this to customize X"
  - `@callback` docs that explain when each callback is invoked
  - One complete implementation example

```elixir
defmodule Jido.Worker do
  @moduledoc """
  Behaviour for long-running Jido workers.

  Implement this to plug your business logic into the Jido supervision tree.
  """

  @callback handle_task(term(), state()) ::
              {:ok, state()} | {:error, term(), state()}

  @optional_callbacks handle_task: 2
end
```

- When consuming behaviours, use `@impl true` to make intent clear in docs and code:

  ```elixir
  defmodule MyApp.Worker do
    @behaviour Jido.Worker

    @impl true
    def handle_task(task, state) do
      ...
    end
  end
  ```

---

## The "So What?" test for features

After every feature claim, ask "So what?" until you hit developer value.

**Example chain:**
- "Uses ETS for storage" → So what?
- "Fast concurrent reads" → So what?
- "No GenServer bottleneck" → So what?
- "Handles 100K lookups/second per node" → So what?
- "Your API response times stay under 10ms at scale" ← **DEVELOPER VALUE**

Lead with the final answer. Support with the technical details.

---

## Error messages as documentation

Error messages are documentation that appears exactly when developers need it.

```elixir
# BAD
raise "invalid configuration"

# GOOD
raise ArgumentError, """
Invalid configuration for MyLib.Worker

Expected :pool_size to be a positive integer, got: #{inspect(value)}

Example configuration:

    config :my_app, MyLib.Worker,
      pool_size: 10,
      timeout: 5_000
"""
```

### Error message checklist

- [ ] What went wrong (specific, not vague)
- [ ] What was expected vs. what was received
- [ ] How to fix it (example of correct usage)
- [ ] Where to find more information (link to docs if complex)

---

## Writing for different documentation types

### HexDocs guides (long-form)

Use the "slippery slide" principle—every section pulls to the next.

```markdown
# Getting Started with MyLib

You've got a GenServer that's becoming a bottleneck. Requests queue up,
response times spike, and you're not sure where the problem is.

This guide shows you how to surface that bottleneck in under 5 minutes.

## Prerequisites

[Minimal list—don't pad this]

## Step 1: Add the dependency

[Code, then one sentence of context if needed]

## Step 2: ...
```

**Rhythm:** Short setup sections, longer explanation sections, short action sections. Vary the pace.

### Public docs only

All published documentation (HexDocs and agentjido.xyz) must be written for external developers using Hex packages.

**Rules:**

- **All examples use Hex dependencies:**

  ```elixir
  def deps do
    [
      {:jido, "~> 1.2"},
      {:jido_ai, "~> 2.0"}
    ]
  end
  ```

- **Never mention internal tooling** (`jido_dep/4`, `mix ws.*`, workspace commands) in public docs
- **Use standard Mix commands** (`mix test`, `mix docs`) in all examples
- **Link to hex.pm and agentjido.xyz**, never to internal workspace files

### Inline code comments

Per the AGENTS.md rule: avoid non-critical comments. When you must comment:

```elixir
# BAD: Explains what (the code already shows this)
# Increment the counter
counter = counter + 1

# GOOD: Explains why (the code can't show this)
# ETS reads don't need serialization, so we bypass the GenServer
:ets.lookup(table, key)
```

### Changelog entries

```markdown
# BAD
- Fixed bug in Worker module
- Updated dependencies
- Improved performance

# GOOD
- Fixed race condition in `Worker.process/2` that could drop messages
  under high concurrency (issue #127)
- `Pool.checkout/1` now returns in <1ms (previously 5-10ms) by caching
  connection metadata
```

---

## The specificity doctrine for Elixir libraries

| Vague claim | Specific alternative |
|-------------|---------------------|
| "High performance" | "Processes 47K events/sec on a c5.xlarge" |
| "Easy to use" | "3 lines to add to your supervision tree" |
| "Well tested" | "94% code coverage, property-based tests for serialization" |
| "Production ready" | "Running in production at [Company] handling 2M requests/day" |
| "Flexible configuration" | "12 configuration options, sensible defaults for all" |
| "Good documentation" | "Full HexDocs coverage, 15 guides, 47 examples" |

---

## Psychological principles for documentation

### Reciprocity
Give value before asking for anything. Your README should teach something useful even if they don't adopt the library.

### Social proof
"Used by" sections, GitHub stars, hex.pm downloads—but only if the numbers are meaningful. 47 stars means nothing. "Powering the real-time features at [Known Company]" means something.

### Authority
Credentials that matter: "By the author of [well-known library]," production usage stats, contributions to Elixir core, conference talks. Don't manufacture authority.

### Commitment
Get small commitments first. "Add this one line to see if it works" is easier than "restructure your supervision tree." Quickstarts should be reversible.

---

## The editing protocol

### The 24-hour rule
Write docs → Wait overnight → Edit. Fresh eyes catch assumptions that made sense while writing but confuse readers.

### Read aloud test
If you stumble reading your docs aloud, developers will stumble reading them silently. Technical writing should still flow.

### The "new developer" test
Find someone unfamiliar with your library. Watch them try to use it from your docs alone. Where do they get stuck? That's where your docs fail.

### Cut by 30%
1. Complete first draft
2. Cut 30% of words aggressively
3. Ask: Is anything essential missing?
4. Add back only what's necessary

**What to cut:** Obvious statements, redundant explanations, hedge words ("basically," "simply," "just"), throat-clearing ("It should be noted that..."), duplicate information.

**What to keep:** Code examples, specific details, non-obvious gotchas, configuration options, error scenarios.

---

## Pre-publish checklist

### Core documentation

- [ ] **Headline:** Does it clearly state what problem this solves?
- [ ] **Quickstart:** Can a developer copy-paste and have something working in <2 minutes?
- [ ] **Examples:** Do all examples compile and run?
- [ ] **Installation:** Are the mix.exs instructions complete and correct?
- [ ] **One reader:** Is it written to "you," not "users"?
- [ ] **Specificity:** Are vague claims replaced with concrete details?
- [ ] **Differentiation:** Is it clear when to use this vs. alternatives?
- [ ] **Error handling:** Are failure modes documented?
- [ ] **Configuration:** Are all options documented with defaults noted?
- [ ] **Cut fat:** Can you remove 20% more words without losing meaning?

### Elixir & HexDocs

- [ ] **HexDocs build:** Does `mix docs` succeed, and is `main` set to "readme"?
- [ ] **Source links:** Do HexDocs link back to the correct tag/commit on GitHub?
- [ ] **Typespecs:** Are public types documented with `@typedoc`?
- [ ] **Behaviours:** Are callbacks documented with when they're invoked?

### Ecosystem

- [ ] **Ecosystem fit:** Does the README explain where this package fits in the Jido ecosystem and link to agentjido.xyz?
- [ ] **Version alignment:** Are dependency version requirements in the README consistent with `mix.exs`?
- [ ] **Cross-package recipes:** Are relevant tutorials on agentjido.xyz linked from the README or HexDocs?

### Testing

- [ ] **Fresh project test:** In a new Mix project that depends on this package via Hex, does `mix deps.get && mix test` pass with your Quickstart code?
- [ ] **No internal leakage:** Does the README avoid mentioning workspace tooling, internal paths, or contributor-only commands?

---

## The master summary

Across all documentation that drives adoption, the same principles repeat:

**Know your developer's awareness level and meet them there.** The README headline is 80% of first impressions—obsess accordingly. Specificity creates believability. The API design matters more than clever prose. Every sentence exists to get the next sentence read. You cannot create need, only channel existing need. Test your docs by using them yourself. Write to one developer, not "users." Enter the conversation already in their head. Show code first, explain second.

**For ecosystems:** Document two public layers—package HexDocs and cross-package tutorials on agentjido.xyz. Keep workspace concerns strictly internal. Make ecosystem fit explicit in every README. Link to agentjido.xyz for how packages work together.

The documentation author's job remains: **Help one developer solve one problem.** Do it with clarity, specificity, and working examples. Adoption follows.
