defmodule Jido.AI.PluginTest do
  use ExUnit.Case, async: true

  defmodule Assistant do
    use Jido.Agent, name: "assistant", extensions: [Jido.AI.Plugin]

    ai do
      model "openai:gpt-4o-mini"
      instructions "Reply in one short sentence."
    end
  end

  test "an Agent declares its basic AI response" do
    assert Jido.AI.Plugin.response(Assistant) == %{
             model: "openai:gpt-4o-mini",
             instructions: "Reply in one short sentence."
           }
  end
end
