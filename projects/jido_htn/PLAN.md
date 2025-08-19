Okay, this is an excellent and detailed architectural review. Let's break down the implementation plan for these recommendations.

## Implementation Work Plan for Jido HTN Refinements

This plan follows the chronological worklist suggested in the review.

### 1. Fail-fast Builder & Enhanced Validation (Ref. Review Section 2.1)

**Goal:** Make the domain builder more robust by failing earlier on errors and allowing pluggable validation.

**A. Implement Immediate Task Name Clash Detection**
   *   **Files to Modify:**
        *   `lib/jido_htn/domain/domain_builder.ex` (Module: `Jido.HTN.Domain.BuilderHelpers`)
   *   **Code Changes:**
        *   In `compound/3`:
            *   Before `%{builder | domain: %{domain | tasks: Map.put(domain.tasks, name, task)}}`.
            *   Add: `if Map.has_key?(domain.tasks, name), do: Builder.error("Task '#{name}' already exists and conflicts with an existing task definition."), else: ... (original logic)`.
            *   Ensure the function returns `Builder.t()`. If an error occurs, it should return the result of `Builder.error/1`.
        *   In `primitive/4` (and its other arity):
            *   Similar to `compound/3`, add: `if Map.has_key?(domain.tasks, name), do: Builder.error("Task '#{name}' already exists and conflicts with an existing task definition."), else: ... (original logic)`.
   *   **Testing:**
        *   **Modify:** `test/jido_htn/domain/domain_build_test.exs` and `test/jido_htn/domain/domain_builder_test.exs`.
        *   Add tests that attempt to add a compound task with a name already used by a primitive task (and vice-versa).
        *   Verify that `Domain.build()` on such a builder immediately returns `{:error, "Task '...' already exists..."}` *without* needing to call `Domain.validate()`.
        *   The error message in `domain_validate_test.exs` for duplicate task names might change or become obsolete if the builder catches it first. The test `detects duplicate task names` in `domain_validate_test.exs` should be checked; the error will now come from the builder directly.

**B. Extract Validator Behaviour & Allow Injection**
   *   **Files to Create/Modify:**
        *   **New File:** `lib/jido_htn/domain/builder/validator.ex`
        *   `lib/jido_htn/domain/domain_builder.ex` (Module: `Jido.HTN.Domain.BuilderHelpers`)
        *   `lib/jido_htn/domain.ex` (to potentially update `build/1` signature or add `build/2`)
        *   `lib/jido_htn/domain/domain_validation.ex`
   *   **Code Changes:**
        1.  **Define Behaviour:** In `lib/jido_htn/domain/builder/validator.ex`:
            ```elixir
            defmodule Jido.HTN.Domain.Builder.Validator do
              @moduledoc "Behaviour for custom domain validators."
              @callback validate(Jido.HTN.Domain.t()) :: {:ok, Jido.HTN.Domain.t()} | {:error, String.t() | [String.t()]}
            end
            ```
        2.  **Adapt `ValidationHelpers`:**
            *   Consider making `Jido.HTN.Domain.ValidationHelpers` implement this behaviour, or provide a wrapper. For now, `validate/1` in `ValidationHelpers` already fits the signature if we consider `domain` as the first arg to `validate(domain)`.
        3.  **Modify `Domain.BuilderHelpers.build/1`:**
            *   Change signature to `build(builder, opts \\ [])`.
            *   Extract `default_validators = [&Jido.HTN.Domain.ValidationHelpers.validate/1]`. (Note: `validate/1` needs to be callable with just the domain).
            *   `user_validators = Keyword.get(opts, :validators, [])`.
            *   `all_validators = default_validators ++ user_validators`.
            *   Iterate through `all_validators` using `Enum.reduce_while/3`. If any validator returns `{:error, msg}`, halt and return that error.
                ```elixir
                # In Jido.HTN.Domain.BuilderHelpers
                def build(%Builder{domain: domain, error: nil}, opts \\ []) do
                  default_internal_validator_fun = &Jido.HTN.Domain.ValidationHelpers.validate/1 # Or specific internal validation steps
                  # Custom validators passed in opts should adhere to the Validator behaviour implicitly (fun/1)
                  # or be modules implementing the behaviour.
                  custom_validators = Keyword.get(opts, :custom_validators, [])

                  validators_to_run = [default_internal_validator_fun | custom_validators]

                  Enum.reduce_while(validators_to_run, {:ok, domain}, fn validator_fun, {:ok, current_domain} ->
                    case validator_fun.(current_domain) do
                      :ok -> {:cont, {:ok, current_domain}} # if validator returns just :ok
                      {:ok, validated_domain} -> {:cont, {:ok, validated_domain}} # if validator returns modified domain
                      {:error, _reason} = err -> {:halt, err}
                    end
                  end)
                end
                def build(%Builder{error: error}, _opts), do: {:error, error}
                ```
        4.  **Update `Domain.build!/1`:**
            *   Change to `build!(builder, opts \\ [])` and pass `opts` to `build/2`.
   *   **Testing:**
        *   Write a new test module, e.g., `test/jido_htn/domain/custom_validator_test.exs`.
        *   Define a mock validator module implementing `Jido.HTN.Domain.Builder.Validator`.
        *   Test `Domain.build(builder, custom_validators: [MyMockValidator])`. Verify that the mock validator is called and its errors are propagated.
        *   Test that default validation still runs.

**C. Refactor Sequential Validation Passes**
   *   **Files to Modify:**
        *   `lib/jido_htn/domain/domain_validation.ex` (Module: `Jido.HTN.Domain.ValidationHelpers`)
   *   **Code Changes:**
        *   In `validate/1` (which might become `validate(domain, opts \\ [])`):
            *   Create a list of private validation functions:
              ```elixir
              @validation_pipeline [
                &validate_non_empty_domain/1,
                &validate_unique_names/1,
                &validate_subtasks/1,
                # ... all other validation functions
              ]
              ```
            *   `verbose_mode = Keyword.get(opts, :verbose, false)`.
            *   If `verbose_mode` is `false` (default):
                *   Use `Enum.reduce_while(@validation_pipeline, :ok, fn validation_fun, :ok -> ... end)`. Return on first error.
            *   If `verbose_mode` is `true`:
                *   Use `Enum.reduce(@validation_pipeline, [], fn validation_fun, errors_acc -> ... end)` to collect all errors. Return `{:error, all_errors_list}` if any.
   *   **Testing:**
        *   **Modify:** `test/jido_htn/domain/domain_validate_test.exs`.
        *   Create domains with multiple validation errors.
        *   Test `Domain.validate(domain)` (or `Domain.build(builder)` if validation is integrated there) and ensure it returns only the first error (or the error from the first failing category).
        *   Test `Domain.validate(domain, verbose: true)` and ensure it returns a list of all applicable errors.

### 2. Iterative Decomposer & Plan Accumulation (Ref. Review Section 2.2)

**Goal:** Improve planner performance and avoid stack overflows for large/deep HTNs.

**A. Optimize Plan Accumulation (List Concatenation)**
   *   **Files to Modify:**
        *   `lib/jido_htn/planner/task_decomposer.ex`
        *   `lib/jido_htn/planner.ex` (Module: `Jido.HTN`, function: `do_decompose/8`)
   *   **Code Changes:**
        1.  **`TaskDecomposer.decompose_primitive/4`:**
            *   Change `{:ok, current_plan ++ [action], ...}` to `{:ok, [action | current_plan], ...}`.
        2.  **`TaskDecomposer.decompose_compound/7`:**
            *   When a method succeeds (`try_method` returns `{:ok, new_plan_segment, ...}`), this `new_plan_segment` will now be reversed (actions prepended). It should be prepended to the `current_plan` being built up by `do_decompose`.
            *   The `new_plan` from `try_method` will be `method_sub_plan_reversed ++ current_plan_reversed`.
        3.  **`TaskDecomposer.try_method/8`:**
            *   The `current_plan` passed in is already reversed. When `Jido.HTN.decompose` is called, it will prepend to this.
        4.  **`Jido.HTN.decompose/7` and `Jido.HTN.do_decompose/8`:**
            *   `current_plan` will accumulate in reverse order.
            *   In `do_decompose/8`, the base case `([], world_state, current_plan, ...)` should return `{:ok, Enum.reverse(current_plan), world_state, ...}`.
   *   **Testing:**
        *   **Verify:** All existing planner tests in `test/jido_htn/planner_test.exs`, `task_decomposer_test.exs`, etc., must pass. The order of actions in the final plan must be correct.
        *   **Enhance:** `test/jido_htn/planner/performance_test.exs`. Measure before/after for `create_complex_domain` with a large number of primitive tasks in sequence. Expect improved planning time.

**B. Optimize MTR Accumulation**
   *   **Files to Modify:**
        *   `lib/jido_htn/planner/task_decomposer.ex` (Module: `Jido.HTN.Planner.TaskDecomposer`, function: `try_method/8`)
   *   **Code Changes:**
        *   In `try_method/8`:
            *   Change `new_mtr = Kernel.++(mtr, [{task.name, ...}])` to `new_mtr = [{task.name, Map.get(method_struct, :name), Map.get(method_struct, :priority)} | mtr]`.
            *   The `MethodTraversalRecord.compare_priority/2` function already reverses choices, so it should handle this change correctly.
   *   **Testing:**
        *   **Verify:** `test/jido_htn/planner/method_traversal_record_test.exs` should still pass. The logic of `compare_priority` relies on reversed choices, so ensure this internal reversal is compatible.

**C. Address Recursion Depth and Timeout**
   *   **Files to Modify:**
        *   `lib/jido_htn/planner.ex` (Module: `Jido.HTN`)
        *   `lib/jido_htn/planner/task_decomposer.ex`
   *   **Code Changes:**
        1.  **Pass Deadline:**
            *   In `Jido.HTN.plan/3`: Calculate `deadline = System.monotonic_time(:millisecond) + timeout`.
            *   Pass `deadline` to `do_plan/4`, then to `decompose/8`, then to `do_decompose/9` (new arity).
            *   `TaskDecomposer.decompose_task/8` (new arity) and `decompose_compound/8` (new arity) must also accept and pass `deadline`.
        2.  **Check Deadline:**
            *   At the beginning of `Jido.HTN.do_decompose/9`:
              ```elixir
              defp do_decompose(_domain, _tasks, _world_state, _current_plan, _mtr, _recursion_count, _debug, _acc_tree, deadline)
                   when System.monotonic_time(:millisecond) >= deadline do
                dbug("Planning timed out due to deadline")
                {:error, "Planning timed out (internal check)", {:compound, "root", false, [{:empty, "Timeout", false, []}]}}
              end
              ```
            *   Also, check in `when recursion_count >= @max_recursion`.
        3.  **Tail Call Optimization (TCO) for Task List Processing:**
            *   The current `do_decompose/8` should already be TCO regarding the list of tasks `[task | rest_tasks]`. The main concern is the depth of task decomposition itself.
            *   A full conversion to an explicit stack loop for task decomposition is a large refactoring. For now, focus on the deadline. If stack overflows persist, this larger refactor will be necessary.
   *   **Testing:**
        *   Create a new test in `test/jido_htn/planner_test.exs` for timeouts.
        *   Design a domain that would take longer than a short timeout (e.g., many sequential high-cost computation tasks, or very deep recursion if `@max_recursion` is temporarily increased for the test).
        *   Verify `HTN.plan(domain, %{}, timeout: 10)` returns `{:error, "Planning timed out..."}`.
        *   For `@max_recursion`, tests should verify it's still hit if deadline isn't.

### 3. Background-Task Monitoring & Effect Staging (Ref. Review Section 2.3)

**Goal:** Make background tasks more robust by monitoring them and applying effects conditionally.

**A. Modify `PrimitiveTask.execute/2` for Background Tasks**
   *   **Files to Modify:**
        *   `lib/jido_htn/primitive_task.ex`
        *   `lib/jido_htn/planner/task_decomposer.ex`
        *   `lib/jido_htn/domain.ex` (The `Domain.t` world_state part)
   *   **Code Changes:**
        1.  **`PrimitiveTask.execute/2`:**
            *   When `background: true`:
                *   `{:ok, task_pid} = Task.Supervisor.start_child(YourApp.BackgroundTasksSupervisor, fn -> Workflow.run(action, params, context) end)` (Requires a dedicated supervisor for background tasks).
                *   Return `{:ok, %{__jido_background_pid__: task_pid}}`. This return value needs to be handled by the planner.
                *   *Alternatively, if not using a supervisor directly here:* `task_pid = Task.start_link(fn -> ... end)` could be used, but monitoring becomes more complex. The review implies the *caller* (planner) should monitor.
                *   The `background` field in `PrimitiveTask.t` might become `background: boolean() | {:link, boolean()}` to control linking. For now, assume `start_link` or supervised task.
        2.  **`TaskDecomposer.decompose_primitive/4` (will have more args due to deadline):**
            *   When a primitive task is executed and it's a background task:
                *   The `action` tuple returned by `task_to_action` will be `{{module, params}, %{__jido_background_pid__: pid}}` or similar. The plan structure might need to adapt if PIDs are part of it. This seems overly complex for the plan itself.
                *   **Revised approach for `decompose_primitive`:**
                    *   If `task.background`:
                        *   `task_pid = Task.start(...)` (or supervised equivalent). For now, let's assume `Task.start` which is not linked. The monitoring part is external to the planner's immediate synchronous flow.
                        *   The `action` added to the plan remains `{module, params}`.
                        *   `new_world_state` modification:
                            *   Apply `task.expected_effects` to `world_state`.
                            *   Add `pid` to a new field in `world_state`, e.g., `active_background_tasks: MapSet.put(world_state.active_background_tasks || MapSet.new(), {task.name, pid_from_task_start})`.
                            *   Store *actual* effects for later application: `pending_background_effects: Map.put(world_state.pending_background_effects || %{}, pid, task.effects)`.
                        *   Do NOT apply `task.effects` via `EffectHandler` here.
   *   **Testing:**
        *   Unit test `PrimitiveTask.execute/2` for background tasks: verify it starts a task and potentially returns a PID (or that a task is registered with a supervisor). This is hard to unit test directly for `Task.start`.
        *   Integration test in `background_task_test.exs`:
            *   Verify that `world_state.active_background_tasks` contains the PID after a background task is planned.
            *   Verify `world_state.pending_background_effects` stores the correct effects.

**B. Effect Staging and Application**
   *   **Files to Modify/Consider:**
        *   `lib/jido_htn/planner/effect_handler.ex` (Its role might diminish for background tasks' initial effects).
        *   The main application loop that *uses* the Jido HTN planner. This is outside the library itself but crucial.
   *   **Code Changes:**
        1.  **`TaskDecomposer.decompose_primitive/4`:** (As described above) Apply `expected_effects` immediately. Store actual `effects` and PID in `world_state`.
        2.  **External Monitoring (Conceptual - User's Responsibility):**
            *   The application using `Jido.HTN.plan/3` receives a plan and a final `world_state`. This `world_state` now contains `active_background_tasks` (PIDs) and `pending_background_effects`.
            *   The application must implement logic to `Process.monitor(pid)` these PIDs.
            *   On `:DOWN` message for a monitored PID:
                *   If `reason == :normal`, retrieve the `pending_effects` for this PID from `world_state` and apply them using `EffectHandler.apply_effects(domain, effects, result_from_task_if_any, current_actual_world_state)`.
                *   Remove PID from `active_background_tasks` and `pending_background_effects`.
                *   If `reason != :normal`, log the error, do not apply effects, and clean up.
   *   **Testing (`background_task_test.exs`):**
        *   Test that `expected_effects` are applied to the `world_state` returned by `HTN.plan/3`.
        *   Mocking task completion:
            *   Create a test action that sends a message to `self()` on completion/crash.
            *   In the test, after `HTN.plan/3`, retrieve PIDs, simulate receiving `:DOWN` messages.
            *   Verify actual effects are applied only on successful completion.
        *   Test that `world_state` returned by the planner includes the `active_background_tasks` and `pending_background_effects` fields.

### 4. Serializer MFA Refactor (Ref. Review Section 2.4)

**Goal:** Implement lossless serialization for named functions.

   *   **Files to Modify:**
        *   `lib/jido_htn/serializer.ex` (Module: `Jido.HTN.Domain.Serializer` and `Jason.Encoder` for `Jido.HTN.Domain`)
        *   `lib/jido_htn/domain/helpers.ex` (if `function_to_string` is used for serialization by `Jason.Encoder`)
   *   **Code Changes:**
        1.  **`Jido.HTN.Domain.Serializer.serialize_function/1` (New Helper or inline in `encode_functions`):**
            ```elixir
            defp serialize_function(fun) when is_function(fun) do
              info = Function.info(fun)
              # Check for anonymous functions (heuristic)
              if info[:module] == :erl_eval or info[:type] == :local and not Keyword.has_key?(info, :name) do
                raise "Anonymous functions cannot be reliably serialized. Task: #{task_name_context}, Field: #{field_context}"
                # Or return a specific map: %{__jido_anon_fun__: true, string: "fn ..."}
              else
                %{__jido_mfa__: %{m: info[:module], f: info[:name], a: info[:arity]}}
              end
            end
            defp serialize_function(other), do: other # For non-functions like booleans or strings
            ```
        2.  **Update `Jason.Encoder` for `Jido.HTN.Domain`:**
            *   `encode_functions(functions)`: Map `functions` using `serialize_function/1`.
            *   `encode_callbacks(callbacks)`: `Map.new(callbacks, fn {name, fun} -> {name, serialize_function(fun)} end)`.
        3.  **`Jido.HTN.Domain.Serializer.deserialize_function/1`:**
            ```elixir
            defp deserialize_function(%{"__jido_mfa__" => %{"m" => mod, "f" => fun, "a" => arity}}) do
              module = String.to_existing_atom(Atom.to_string(mod)) # Ensure module atom exists
              function_name = String.to_existing_atom(Atom.to_string(fun))
              if Code.ensure_loaded(module) && function_exported?(module, function_name, arity) do
                {:ok, Function.capture(module, function_name, arity)}
              else
                {:error, "Cannot deserialize MFA: #{module}.#{function_name}/#{arity} not found or loaded."}
              end
            end
            # Handle anonymous function marker if one was chosen during serialization
            defp deserialize_function(%{"__jido_anon_fun__" => true, "string" => _fun_str}) do
               # To maintain current test behavior for WIP, but ideally this path means error or placeholder
              {:ok, fn _ -> true end} # Placeholder, ideally error or specific handling
            end
            defp deserialize_function(val) when is_boolean(val), do: {:ok, val} # For simple conditions
            defp deserialize_function(val) when is_binary(val), do: {:ok, val} # For callback names
            defp deserialize_function(_), do: {:error, "Invalid function format for deserialization"}
            ```
        4.  Update `deserialize_functions`, `deserialize_callbacks` to use the new `deserialize_function/1`.
        5.  Remove `Jido.HTN.Domain.Helpers.function_to_string/1` if its only purpose was for the old serialization.
   *   **Testing:**
        *   **Modify/Rewrite:** `test/jido_htn/domain/domain_serialize_wip.exs` and `test/jido_htn/serializer_test.exs`.
        *   Test serialization and deserialization of domains containing named functions in preconditions, effects, and callbacks. Verify the deserialized functions are callable and behave correctly.
        *   Test that attempting to serialize a domain with an anonymous function (not a string callback name) raises an error (or is handled as per the decision for `__jido_anon_fun__`).
        *   Test deserialization failure for non-existent MFAs.

### 5. Switch ExDbug → Logger with Metadata (Ref. Review Section 2.5)

**Goal:** Improve observability with standard Elixir logging.

   *   **Files to Modify:** All files currently using `use ExDbug`.
        *   `lib/jido_htn/domain/domain_reader.ex`
        *   `lib/jido_htn/domain/domain_builder.ex`
        *   `lib/jido_htn/domain/domain_validation.ex`
        *   `lib/jido_htn/planner/effect_handler.ex`
        *   `lib/jido_htn/planner/condition_evaluator.ex`
        *   `lib/jido_htn/planner/task_decomposer.ex`
        *   `lib/jido_htn/planner.ex`
   *   **Code Changes:**
        1.  Remove `use ExDbug, enabled: ...` from all modules.
        2.  Add `require Logger` to these modules.
        3.  Replace `dbug("message")` with `Logger.debug("message")`.
        4.  Replace `dbug("message with #{interpolation}")` with `Logger.debug(fn -> "message with #{interpolation}" end)` or `Logger.debug("message with #{interpolation}")` if interpolation is cheap.
        5.  Add structured metadata:
            *   Example in `TaskDecomposer.decompose_task`:
              `Logger.debug("Decomposing task", task_name: task_name, recursion_count: recursion_count)`
            *   Example in `Domain.ReadHelpers.get_primitive`:
              `Logger.debug("Getting primitive task", task_name: name)`
   *   **Testing:**
        *   Manually enable `Logger` level to `:debug` during testing.
        *   Inspect log output to ensure messages are correctly formatted and contain the expected metadata.
        *   Update any tests that might have been capturing `ExDbug` output (if any relied on specific string matching from `dbug`). Generally, tests shouldn't assert on debug logs.

### 6. Polish Items & Documentation Sync

**A. Mermaid Edge Labels**
   *   **Files to Modify:** `lib/jido_htn/domain/domain_visualize.ex`
   *   **Code Changes:**
        *   `generate_edges/1`: Needs access to the `domain` to resolve function references to callback names.
            *   Pass `domain` to `generate_edges` and then to `extract_conditions`.
        *   `extract_conditions/2` (new arity `extract_conditions(conditions, domain)`):
            *   For each condition:
                *   If `is_binary(condition)` (it's a callback name), use it directly.
                *   If `is_function(condition)`:
                    *   Try to find it in `domain.callbacks` by value (this is inefficient).
                    *   A better way: pre-process callbacks into a `Map<function_ref, name>` if possible, or rely on `Function.info` for named functions.
                    *   `Function.info(func, :name)` can give the atom name for named functions.
                    *   For anonymous functions, use a short placeholder like `"[anon_cond]"`.
        *   Modify `generate_legend` to explain any placeholder syntax.
   *   **Testing:**
        *   Manually generate Mermaid diagrams for domains with various condition types (named callbacks, Elixir named functions, anonymous functions).
        *   Verify edge labels are more readable.

**B. Default Method Names**
   *   **Files to Modify:** `lib/jido_htn/planner/task_decomposer.ex`
   *   **Code Changes:**
        *   In `decompose_compound/7` (or its new arity):
            *   When processing methods `fn {method, index}, {_, acc_trees} -> ... end`.
            *   `method_name = Map.get(method, :name) || "#{task.name}_m#{index + 1}"`. Use this `method_name` in debug trees and MTR recording.
   *   **Testing:**
        *   **Modify:** `test/jido_htn/planner/method_traversal_record_test.exs`.
        *   Create a domain with methods that don't have explicit names.
        *   Inspect the `debug_tree` to ensure default names like `"taskName_m1"` are generated.

**C. `Jido.HTN.DomainBehaviour`**
   *   **Decision:** Remove it as it's unused.
   *   **Files to Modify:**
        *   `lib/jido_htn/behaviour.ex`: Delete the `Jido.HTN.DomainBehaviour` module definition.
        *   `test/jido_htn/domain/domain_full_test.exs`: Remove `@behaviour Jido.HTN.DomainBehaviour` from `CopyTradeDomain`.
   *   **Testing:**
        *   Ensure all tests still compile and pass, especially `domain_full_test.exs`.

---
This plan provides a step-by-step guide to address the architectural recommendations. Each major section should be implemented and tested incrementally. Remember to run all existing tests after each significant change to catch regressions.