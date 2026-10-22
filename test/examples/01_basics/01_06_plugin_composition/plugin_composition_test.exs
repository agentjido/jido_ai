defmodule JidoAI.Examples.PluginCompositionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugin
  alias JidoAI.Examples.PluginComposition.{ConvenienceAgent, ExplicitAgent}

  @moduletag :example

  test "explicit and convenience forms install the same AI Plugin data" do
    assert Enum.map(ExplicitAgent.definition().extensions, & &1.provider) == [Plugin]
    assert Enum.map(ConvenienceAgent.definition().extensions, & &1.provider) == [Plugin]
    assert Plugin.config(ExplicitAgent) == Plugin.config(ConvenienceAgent)
  end
end
