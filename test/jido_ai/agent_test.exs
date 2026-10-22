defmodule Jido.AI.AgentTest do
  use ExUnit.Case, async: true

  defmodule AuditExtension do
    use Jido.Agent.Extension, id: "test.audit"
  end

  defmodule Assistant do
    use Jido.AI.Agent,
      name: "assistant",
      extensions: [Jido.AI.AgentTest.AuditExtension]

    ai do
      model "openai:gpt-4o-mini"
    end
  end

  test "use adds the AI Plugin and preserves other extensions" do
    providers = Enum.map(Assistant.definition().extensions, & &1.provider)

    assert providers == [Jido.AI.Plugin, AuditExtension]

    assert Jido.AI.Plugin.config(Assistant) == %{
             model: "openai:gpt-4o-mini",
             instructions: "",
             tools: [],
             controls: Jido.AI.Plugin.default_controls()
           }
  end
end
