# Models, profiles, and instructions

A profile names one AI behavior. A simple Agent needs only `:assistant`.
Several profiles are useful when the same domain Agent needs distinct work,
such as a short answer and a deeper review. Keep separate routes so callers
can select the behavior explicitly.

```elixir
ai :answer do
  model :fast
  instructions "Answer from the supplied evidence."
  result into: :reply
end

ai :review do
  model :careful
  instructions "List uncertain claims and their evidence."
  result into: :reply
end
```

`model :fast` is an application alias, not a provider name. Configure aliases
in the application and keep provider changes out of Agent source when model
selection is operational policy. A profile can also name a model directly.
The request API supports a request-scoped model input. Such an override
changes the model for that request; it does not create a new profile or route.

Instructions state the task and output expectations. They are not a security
boundary. If a user must not call a tool, enforce that with tool access policy.
If a result must have a shape, enforce it with `result` validation. If a
request has a cost bound, enforce it with controls or quotas. A prompt alone
cannot provide any of these guarantees.

For each profile, state the expected input, tools, result, and limit. A name
such as `:review` should tell a developer why a second profile exists. The
[model helper example](../../examples/01_authoring/01_08_model_helpers/README.md)
shows aliases and provider options. The [routing example](../../examples/16_capabilities/16_03_routing_policy/README.md)
shows policy that chooses among models. Continue with [tool contracts](06_tool_contracts.md).
