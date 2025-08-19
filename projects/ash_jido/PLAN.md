Below is a structured “technical discovery + implementation plan” for **`ash_jido`**.
I’ve organised it so you can copy‑paste individual sections into issues or ADRs as you flesh out the repo.

---

## 1  Why this integration makes sense

| Ash                                                                   | Jido                                                                           |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Declarative resource layer (CRUD, calculations, aggregates, policies) | Composable `Jido.Action` modules that can be orchestrated by agents/workflows  |
| Excellent data‑integrity & persistence tooling                        | Agentic runtime, pluggable AI tooling (`jido_ai`), distributed execution       |
| Spark DSL engine enables compile‑time extensions                      | `use Jido.Action` macro expects metadata & `run/2` implementation([GitHub][1]) |

Bridging them means **every Ash action automatically becomes a tool in an agent’s toolbox**—with type‑safe schemas and Ash policies still enforced.

---

## 2  Core design decisions

| Concern                        | Recommendation                                                                                                                                                                                                                    |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Where to hook**              | Ship an **Ash Resource extension** (`AshJido.Resource`) that adds a new DSL section `jido_actions`. Spark transformers let us inspect each Ash action at compile‑time([Hex Documentation][2]).                                    |
| **Jido module generation**     | Generate a dedicated `Jido.Action` module per Ash action at *compile time* under `MyApp.Jido.<Resource>.<Action>`.  Keeps BEAM code‑loading cheap and docs discoverable (they show up in `mix docs`).                             |
| **Parameter schema**           | Map Ash attributes/arguments → NimbleOptions spec used by Jido: <br>`Ash.Type.String` → `:string`, `:uuid` → `:string`, `:decimal` → `:float`, embedded types default to `:map`.  Allow override inside `jido_actions`.           |
| **Return value**               | After invoking `Ash.Action.do/<resource>.run_action/4`, pipe result through `AshJido.Mapper` which: <br>• converts structs ⇒ maps (`Ash.Resource.Info.attributes`) <br>• preserves `:pagination`/`:count` meta under `:meta` key. |
| **Auth / multitenancy**        | Accept a `%{actor: term(), tenant: term()}` entry in the Jido `context` argument. Forward those into `Ash` calls (`Ash.Query.set_tenant/2`, `Ash.Changeset.set_actor/2`).                                                         |
| **Error handling**             | Trap `{:error, %Ash.Error{}}` and re-wrap in `Jido.Error` so workflows can compensate.                                                                                                                                            |
| **Naming**                     | Default Jido Action name = `"#{resource_short_name}_#{action_name}"`.  Allow override via DSL.                                                                                                                                    |
| **Optional auto‑registration** | Provide `AshJido.AgentBuilder.resources([User, Post])` which returns the list of generated modules so callers can drop it straight into `actions:` of a `use Jido.Agent`.                                                         |

---

## 3  Proposed DSL

```elixir
defmodule MyApp.Accounts.User do
  use Ash.Resource,
    extensions: [AshJido.Resource]

  # …

  actions do
    create :register
    read   :by_id, primary?: true
  end

  jido_actions do
    expose :register                 # auto‑generate
    action :by_id, name: "get_user"  # rename + customise
  end
end
```

Options inside `action/…`:

| key           | default                | meaning                                    |
| ------------- | ---------------------- | ------------------------------------------ |
| `name`        | auto‑derived           | Jido tool name                             |
| `description` | Ash action description | Sent to LLMs                               |
| `output_map?` | `true`                 | convert structs → maps                     |
| `pagination?` | `true`                 | include `page`/`per_page` params for reads |

---

## 4  High‑level module layout

```
lib/
  ash_jido/
    resource.ex        # Spark extension + transformers
    generator.ex       # defines Jido module AST
    mapper.ex          # struct→map helpers
    type_mapper.ex     # Ash → NimbleOptions mapping
    util.ex
test/
  … (use :ash_fixtures + :jido_test_support)
```

---

## 5  Detailed build roadmap

| Sprint                               | Deliverables                                                                                                                                                                |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Week 1 – PoC**                     | • Basic mix skeleton (`mix new ash_jido --sup`) <br>• Add deps: `{:ash, "~> 3.5"}, {:jido, "~> 1.1"}` <br>• Compile‑time generator for a single hard‑coded resource/action. |
| **Week 2 – DSL & generators**        | • Implement `jido_actions` section + `AshJido.Resource.Info` helpers <br>• Support `expose_all? true` flag <br>• Auto‑doc generation (`@moduledoc` render schemas).         |
| **Week 3 – Type & auth plumbing**    | • Finish `Ash → NimbleOptions` mapper <br>• Context (actor, tenant) passthrough <br>• Error wrapping strategy.                                                              |
| **Week 4 – Pagination & query args** | • Optional `limit`/`offset` or cursor params <br>• Stream results for large datasets with `Enum.chunk_every/2`.                                                             |
| **Week 5 – Testing & CI**            | • ExUnit coverage for 3 resource scenarios <br>• Dialyzer & Credo <br>• GitHub CI matrix (OTP 26 / Elixir 1.17)                                                             |
| **Week 6 – Docs & Hex release**      | • `mix docs` with module diagrams <br>• Publish `0.1.0` to Hex <br>• Write migration guide in README.                                                                       |

---

## 6  Potential pitfalls & mitigations

| Risk                                           | Mitigation                                                                                                                       |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **Breaking Ash v3 transformer ordering**       | Declare `before?/1` = `Ash.Resource.Transformers.FinalizeDsl`.  Unit test compilation of a resource that also uses `AshGraphql`. |
| **Large compile times (many resources)**       | Support `runtime: true` flag — generate stubs that call a generic runtime dispatcher rather than full modules.                   |
| **Schema drift when action signature changes** | Store generator checksum in module attrs; raise compile‑time error if checksum differs.                                          |
| **Complex embedded / calced attributes**       | Default to `:map`; allow user‑supplied overrides.                                                                                |

---

## 7  Example output Jido Action (auto‑generated)

```elixir
defmodule MyApp.Jido.User.Register do
  use Jido.Action,
    name: "register_user",
    description: "Creates a new user",
    schema: [
      email:  [type: :string, required: true],
      password: [type: :string, required: true]
    ],
    output_schema: [
      id:       [type: :uuid],
      email:    [type: :string]
    ]

  def run(params, ctx) do
    params
    |> Ash.Changeset.for_create(MyApp.Accounts.User, :register,
         actor: ctx[:actor], tenant: ctx[:tenant])
    |> Ash.create()
    |> AshJido.Mapper.wrap()
  end
end
```

(Everything above is generated; maintaining a 1‑1 mapping to the underlying Ash action.)

---

## 8  Long‑term ideas

* **Agent scaffolder** – `mix ash_jido.gen.agent Accounts.User` creates a ready‑to‑run `Jido.Agent` that exposes all actions for a resource family.
* **Ash ↔ Jido telemetry bridge** to forward workflow events into `Ash.Notifications` and vice‑versa.
* **Optional code‑gen for `jido_ai` tools** so any exposed Ash action is instantly invokable via an LLM function call.

---

### Next steps for you

1. **Nail down the DSL shape** — once agreed, we can lock generator behaviour.
2. Kick off Week 1 PoC, focusing on a single resource and action.
3. Ping me with any edge‑cases you’re worried about (calculated attributes, multitenant sharding, etc.) so we can prototype them early.

Happy hacking! 🧑‍💻

[1]: https://raw.githubusercontent.com/agentjido/jido/main/lib/jido/action.ex "raw.githubusercontent.com"
[2]: https://hexdocs.pm/ash/writing-extensions.html "Writing Extensions — ash v3.5.25"
