defmodule JidoAI.Examples.SkillRuntimePublicTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.SkillRuntime.Agent
  alias Jido.AI.Skill.{AgentIntegration, Registry, Spec}

  test "the authored Agent loads a host-bound skill without test callbacks", %{jido: jido} do
    start_supervised!(Registry)

    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "load", name: "load_skill", arguments: %{name: "review"}}]}},
        %{reply: {:text, "Reviewed"}}
      ])

    binding =
      AgentIntegration.prepare!(
        specs: [%Spec{name: "review", description: "Review a case", body_ref: {:inline, "Check each claim."}}]
      )

    context = Map.merge(context, binding.tool_context)
    server = start_agent(jido, Agent.new!())
    assert {:ok, "Reviewed"} = Agent.ask_sync(server, "Review this", context: context)
    [_, final] = MockLLM.report(mock).requests
    assert Jason.encode!(final.body) =~ "Check each claim."
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end
end
