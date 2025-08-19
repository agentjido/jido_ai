# Jido.HTN v1 – Technical Inventory

This document reverse-engineers the entire v1 codebase so that you can confidently redesign it. Everything below is taken directly from the source you just explored.

## 1. Top-level Architecture & Behaviour

### Public façade
- `Jido.HTN` (lib/jido_htn/planner.ex) – the planner module that callers interact with (`plan/3`, `decompose/8`, etc.).

### Supporting sub-systems
- Domain modelling (`Jido.HTN.Domain` + helpers)
- Planner core (Condition evaluation, Effect handling, Task decomposition)
- Serialisation/visualisation/cloning utilities

### Control-flow (happy path)
1. Build a `Domain` (builder DSL or deserialize from JSON).
2. Pass the domain and a `world_state` map to `Jido.HTN.plan/3`.
3. The planner performs a depth-first, priority-ordered decomposition of the root tasks into primitive actions.
4. While searching it maintains:
   - a running **plan** (list of `{module, opts}` tuples)
   - a simulated **world_state** (effects applied)
   - an **MTR** (Method Traversal Record) to later compare/repair plans
   - an optional **debug tree** for visual inspection.
5. Result: `{:ok, plan, mtr}` or `{:ok, plan, mtr, debug_tree}` when `debug: true`.

## 2. Core Data Structures

Structs (all typed with @type for dialyzer):

### Domain
- name :: String
- tasks :: %{String ⇒ CompoundTask | PrimitiveTask}
- allowed_workflows :: %{String ⇒ module} (integration point with jido_action)
- callbacks :: %{String ⇒ (map → boolean | map)} (predicates & transformers)
- root_tasks :: MapSet(String)

### CompoundTask
- name :: String
- methods :: [Method]

### PrimitiveTask
- name :: String
- task :: {Jido.Action, keyword()} | module
- preconditions :: [predicate]
- effects :: [transformer]
- expected_effects :: [transformer]
- cost, duration, scheduling_constraints, background?

### Method
- name :: String | nil
- priority :: integer | nil (lower number = higher priority)
- conditions :: [predicate]
- subtasks :: [String] (task names)
- ordering :: [{before, after}] (topological constraints)

### MethodTraversalRecord
- choices :: [{task_name, method_name, priority}] (root→leaf order)

Supporting modules: `ConditionEvaluator`, `EffectHandler`, `TaskDecomposer`, `Domain.* helpers`, `Serializer`.

## 3. Public & Semi-Public API Surface

(all exported functions – most reside in facade modules)

### A. Jido.HTN (planner.ex)
- `plan(domain, world_state, opts \\ [])`
  opts:
  - `:debug` (bool) – include debug tree
  - `:timeout` (ms) – async planning timeout
  - `:root_tasks` ([String]) – override domain-defined roots
  - `:current_plan_mtr` (MethodTraversalRecord) – enables priority-based pruning
- `decompose/8` (lower-level recursive entry)

### B. Jido.HTN.Domain
- `new/1`
- `compound/3`
- `primitive/4`
- `callback/3`
- `allow/3`
- `root/2`
- `replace/3` (returns {:ok, domain})
- `build/1`, `build!/1`

- `get_primitive/2`, `get_compound/2`
- `tasks_to_map/1`, `list_tasks/1`
- `list_allowed_workflows/1`, `list_callbacks/1`

- `validate/1` (delegates to ValidationHelpers)

### C. Utility/Public helpers
- `Domain.CloneHelpers.clone/1`, `merge/2`
- `Domain.Serializer.serialize/1` (→ JSON), `deserialize/1` (← JSON)
- `Method.order_subtasks/1`, `validate_ordering!/1`
- `MethodTraversalRecord.*` (new/0, record_choice/4, compare_priority/2)

## 4. Domain Builder Pattern

The Builder DSL lives in `Domain.BuilderHelpers`.

Example (from tests):

```elixir
"Demo Domain"
|> Domain.new()
|> Domain.compound("root",
    methods: [%{name: "m1", subtasks: ["greet"], conditions: []}]
   )
|> Domain.primitive("greet", {SayHelloWorkflow, [user_id: 42]})
|> Domain.callback("is_morning?", &MyPredicates.is_morning?/1)
|> Domain.allow("SayHelloWorkflow", SayHelloWorkflow)
|> Domain.root("root")
|> Domain.build!()
```

### Implementation mechanics:
- `Domain.new/1` returns `%Builder{domain: %Domain{}}`
- Each DSL call (`compound`, `primitive`, etc.) mutates the internal struct if no error; otherwise records `error`.
- `build/1` returns `{:ok, domain}` or `{:error, reason}`; `build!/1` raises on error.

Normalization helpers ensure:
- Methods maps are converted to %Method{}
- Optional parameters are given defaults
- Ordering constraints validated immediately (`Method.validate_ordering!/1`).

## 5. Planning Algorithm Details

### A. Entry (`plan/3`)
- Verifies/infers `root_tasks` (must be compound).
- Adds :background_tasks MapSet to world_state.
- Runs `do_plan` in an async Task with timeout.

### B. Decomposition (`decompose/8` in planner – wrapper)
- Recursively handled by `Planner.TaskDecomposer`.

### C. TaskDecomposer.decompose_task/8
- Looks up task struct by name; dispatches to:
  - `decompose_primitive/5`
  - `decompose_compound/8`

### D. Primitive step
- `ConditionEvaluator.preconditions_met?/3`
- If OK → convert to action tuple (`task_to_action/1`)
  - Simulate expected_effects first, then regular effects (`EffectHandler.apply_all_effects_for_simulation/4`)
  - If `background: true` add task name to `:background_tasks` set.
- Returns success tuple with plan, new world_state, MTR (unchanged), debug node.

### E. Compound step
1. Sort methods by priority (default 100).
2. For each method:
   - Evaluate conditions.
   - Record choice in temporary MTR (`try_method/…`).
   - Apply ordering constraints (topological sort).
   - Optionally prune search if a `current_plan_mtr` with higher priority already exists.
   - Recurse back into `Jido.HTN.decompose`.
3. Fails if no method succeeds.

### F. Max recursion depth (`@max_recursion = 100`) guard.

### G. Debug tree format
Tag tuple hierarchy:
- `{:compound, task_name, success?, [method_nodes]}`
- method_node = `{success?, method_name, cond_results, subtree}`
- `{:primitive, task_name, success?, cond_results}`
- `{:empty, reason, false, []}`

## 6. Integration with jido_action / workflows

- A **PrimitiveTask** wraps a *workflow invocation*:
  ```elixir
  task: {WorkflowModule, keyword_opts}
  ```

- You must explicitly allow any workflow inside the domain:
  ```elixir
  Domain.allow("SayHelloWorkflow", SayHelloWorkflow)
  ```

- During plan-time the workflow is **not executed**; its effects are simulated by the supplied effect functions.

- Execution-time helper (`PrimitiveTask.execute/2`) is stubbed to call `Jido.Workflow.run/3` – indicating planned runtime coupling with the jido_action system.

- `Domain.Helpers.op/3` provides a generic adapter that, given a workflow name, returns a lambda ready for runtime execution through the workflow's `run/3` API.

## 7. Validation, Cloning & Serialisation

### Validation (`Domain.ValidationHelpers`) – 14+ validators:
- non-empty, unique names, defined subtasks, valid callbacks, root task rules, cost/duration types, etc.

### Cloning / merging (`Domain.CloneHelpers`)
- Deep copy and deep merge with automatic conflict renaming (`*_from_primitivetask` / `*_from_compoundtask`).

### Serialisation (`Domain.Serializer`)
- JSON encoding/decoding via custom `Jason.Encoder` implementation.
- Functions are encoded as strings (best-effort) and deserialised as stub lambdas (`fn _ -> true end`) – purely for offline storage/testing.

### Visualisation (`domain_visualize.ex`) – builds Mermaid string (not core to planning).

## 8. Configuration & Usage Patterns

### 1. Domain definition
- Builder DSL in Elixir code.
- Or load pre-authored JSON via `Domain.Serializer.deserialize/1`.

### 2. Register predicates & effects
- Plain anonymous functions or named callbacks stored under `domain.callbacks`.
- Reference by string from tasks/methods.

### 3. Register workflows
- `Domain.allow(name, Module)` with `run/3` implementation.

### 4. Planning call (typical)
```elixir
{:ok, plan, mtr, tree} =
  Jido.HTN.plan(domain, %{agent: "bot-1"}, debug: true, timeout: 2000)
```

### 5. Executing the plan
- Caller iterates the list of `{module, opts}` and feeds them into jido_action.

## 9. Feature Summary / Capability Matrix

✓ Compound & primitive tasks, unlimited nesting  
✓ Method priorities + partial ordering constraints  
✓ Mixed predicate sources (bool, fn, callback name)  
✓ Expected-vs-actual effects for predictive simulation  
✓ Background task modelling  
✓ Method Traversal Record for plan comparison / repair  
✓ Domain validation & error accumulation  
✓ Plan search culling using MTR comparison  
✓ JSON import/export & domain cloning/merging  
✓ Optional debug tree generation  
✓ Stub execution hooks for runtime workflow integration

## 10. Limitations & Observations to Address in Rewrite

- Actual workflow execution (`Jido.Workflow.run/3`) is unimplemented.
- Function serialisation is lossy; consider BEAM-UUID + registry or avoid JSON.
- Builder accumulates only the **first** error; might prefer a list of errors.
- Condition evaluator stops at first failure (good) but returns only booleans – richer explanations could help debugging.
- Background-task state is a plain MapSet in world_state – scheduling/overlap rules are external.
- `ordering` constraints limited to pairwise precedence; no groups/parallel designations.
- No heuristic or cost-based search; purely DFS + priority sort.
- Max recursion depth hard-coded.
- Many helper modules marked `@moduledoc false`; promoting stable APIs would aid reuse.

This inventory should give you 100% coverage of the existing functionality and its inter-relationships, providing a solid foundation for the complete v2 rewrite.
