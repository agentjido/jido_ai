# [P1] `mix jido_ai` crashes with `CaseClauseError` on unsupported `--format` values

## Summary
CLI output functions pattern-match only `"json"` and `"text"` format values and do not validate early. Unsupported format values crash at runtime.

Severity: `P1`  
Type: `logic`, `api`

## Impact
Invalid user input yields stacktrace crash instead of clean CLI error contract.

## Evidence
- Format option is parsed as free string: `/Users/mhostetler/Source/Jido/jido_ai/lib/mix/tasks/jido_ai.ex:71`.
- Output paths case only on `"json"`/`"text"`: `/Users/mhostetler/Source/Jido/jido_ai/lib/mix/tasks/jido_ai.ex:238`, `/Users/mhostetler/Source/Jido/jido_ai/lib/mix/tasks/jido_ai.ex:277`, `/Users/mhostetler/Source/Jido/jido_ai/lib/mix/tasks/jido_ai.ex:290`.

Observed validation command (2026-02-21):
```bash
mix jido_ai --format yaml "hello"
```

Observed output excerpt:
```text
** (CaseClauseError) no case clause matching: "yaml"
    (jido_ai 2.0.0-beta) lib/mix/tasks/jido_ai.ex:238: Mix.Tasks.JidoAi.output_result/2
```

## Reproduction / Validation
1. Run task with unsupported format (`yaml`).
2. Observe crash stacktrace.

## Expected vs Actual
Expected: immediate validation error (`unsupported format`) with non-zero exit and no stacktrace.  
Actual: unhandled `CaseClauseError`.

## Why This Is Non-Idiomatic (if applicable)
CLI interfaces should fail predictably on invalid options and avoid exposing stacktraces for user input errors.

## Suggested Fix
Validate `--format` during config parsing/build and route unsupported values through `output_fatal_error/2`.

## Acceptance Criteria
- [ ] Unsupported format returns user-friendly error.
- [ ] No `CaseClauseError` is raised for format validation failures.
- [ ] Add CLI test for invalid format option.

## Labels
- `priority:P1`
- `type:logic`
- `type:api`
- `area:cli-mix`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/mix/tasks/jido_ai.ex`
