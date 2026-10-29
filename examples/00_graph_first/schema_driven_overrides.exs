defmodule JidoAI.Examples.SchemaOverrides.Reasoning do
  @moduledoc "A small reasoning Flow with application-defined input fields."

  use Jido.Flow,
    id: "jido.ai/examples/reasoning/schema-overrides",
    vsn: 1,
    name: "schema_driven_overrides",
    schema:
      Zoi.object(
        %{
          input: Zoi.string(),
          greeting: Zoi.string() |> Zoi.default("Hello"),
          punctuation: Zoi.string() |> Zoi.default(".")
        },
        unrecognized_keys: :error
      ),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  flow do
    step "answer",
         [
           input <- input(:input),
           greeting <- input(:greeting),
           punctuation <- input(:punctuation)
         ],
         inline: [context: context] do
      {:ok,
       %{
         state: context.agent_state,
         response: %{output: "#{greeting}, #{input}#{punctuation}"}
       }}
    end

    output result("answer")
  end
end

defmodule JidoAI.Examples.SchemaOverrides.Agent do
  @moduledoc "An Agent with schema-validated reasoning defaults."

  use Jido.AI.Agent,
    name: "schema_overrides_agent",
    id: "jido.ai/examples/agents/schema-overrides",
    vsn: 1

  ai do
    reasoning JidoAI.Examples.SchemaOverrides.Reasoning do
      greeting "Welcome"
      punctuation "!"
    end
  end
end

alias JidoAI.Examples.SchemaOverrides.Agent
alias JidoAI.Examples.SchemaOverrides.Reasoning

[%{handler: %{target: Reasoning}, defaults: defaults}] = Agent.definition().routes

run = fn id, params ->
  agent = Agent.instantiate!(id: id)
  signal = Agent.request_signal!(params)

  {:ok, _agent, [%Jido.Agent.Directive.Reply{signal: reply}]} = Agent.cmd(agent, signal)
  reply.data
end

configured = run.("configured-defaults", %{input: "Ada"})
overridden = run.("request-overrides", %{input: "Ada", greeting: "Good morning"})

%{output: "Welcome, Ada!"} = configured
%{output: "Good morning, Ada!"} = overridden

IO.inspect(defaults, label: "Agent reasoning defaults")
IO.inspect(configured, label: "Configured result")
IO.inspect(overridden, label: "Request override result")
