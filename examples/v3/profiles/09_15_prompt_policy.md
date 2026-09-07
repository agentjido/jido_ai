# 09_15: Adaptive prompt selection

The [public Agent declarations](../lib/examples/09_reasoning/09_15_prompt_policy/agent.ex)
and [eight integration cases](../test/examples/09_reasoning/09_15_prompt_policy_test.exs)
inspect the actual system messages sent through ReqLLM to the shared mock.
The existing [native Adaptive Agent](../lib/examples/09_reasoning/09_10_adaptive/agent.ex)
supplies the native DSL and data examples.

```sh
mix test test/examples/09_reasoning/09_15_prompt_policy_test.exs --include integration --seed 0
```

Adaptive resolves the prompt after it selects a method. A selected ReAct
profile with nil instructions uses the shared ReAct default. The selection
changes only the request profile. The declared Agent definition stays intact.
CoT, CoD and the other methods keep their existing prompt rules.

| Input form | Selected ReAct system prompt |
| --- | --- |
| Public Adaptive macro or option adapter; omitted, nil, false or empty `system_prompt` | Shared ReAct default |
| Public macro with a prompt module attribute | Exact supplied text |
| Native Adaptive `instructions: nil` | Shared ReAct default |
| Native Adaptive `instructions: ""` | No base prompt |
| Native Adaptive with text instructions | Exact supplied text |
| Direct native ReAct with nil instructions | No base prompt; unchanged |

The public option adapter normalizes empty values once. The shared default
text has one source. No new DSL term, prompt-mode setting or profile value is
introduced. Native instructions remain nil or text. Explicit empty native
instructions retain their existing meaning.

DSL, direct data, Builder and trusted source JSON produce equal definitions
and send the same prompt. Direct Flow and ordinary Agent Turn execution also
use that prompt. Further cases select CoT then ReAct on one Agent, and combine
the ReAct default with structured-output instructions and a validated object.

PRs 217 and 218 establish related prompt-attribute and normalization rules.
These examples extend that evidence to Adaptive. They do not prove all direct
legacy reasoning forms or conversion of old runtime prompt overrides. Those
APIs, dynamic prompt changes, state conversion and full package validation
remain in the migration plan.
