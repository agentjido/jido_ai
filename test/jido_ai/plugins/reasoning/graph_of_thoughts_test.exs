defmodule Jido.AI.Plugins.Reasoning.GraphOfThoughtsTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Plugins.Reasoning.GraphOfThoughts, as: Capability

  defmodule Overwrite do
    use Jido.Action, name: "overwrite_got_defaults"

    def run(_, context) do
      next = put_in(context.agent_state.reasoning_got.timeout, 1)
      {:ok, next}
    end
  end

  test "core creates owned defaults for the fixed method" do
    definition = definition([])
    agent = Jido.Agent.instantiate!(definition)

    assert agent.state.reasoning_got == %{
             strategy: :got,
             default_model: :reasoning,
             timeout: 30_000,
             options: %{}
           }

    assert agent.state.result == nil
  end

  test "configured defaults survive an empty restored state and reject another method" do
    config = [default_model: :fast, timeout: 800, options: %{system_prompt: "Use facts"}]
    {:reasoning_got, schema} = Capability.state_spec(config)
    assert {:ok, state} = Zoi.parse(schema, %{})
    assert state.default_model == :fast and state.timeout == 800
    assert state.options == %{system_prompt: "Use facts"}
    assert {:error, _} = Zoi.parse(schema, %{state | strategy: :invalid})
    assert {:error, _} = Zoi.parse(schema, %{state | timeout: 0})
  end

  test "an ordinary Action cannot replace the owned defaults" do
    agent = definition([]) |> Jido.Agent.instantiate!()
    signal = Jido.Signal.new!("defaults.replace", %{}, source: "/test")
    assert {:error, error} = Jido.Agent.cmd(agent, signal)
    assert inspect(error) =~ "Plugin"
    assert agent.state.reasoning_got.timeout == 30_000
  end

  defp definition(config) do
    Jido.Agent.new!(%{
      name: "got_capability_contract",
      schema: Zoi.object(%{result: Zoi.any() |> Zoi.default(nil)}),
      plugins: [{Capability, config}],
      routes: [{"defaults.replace", Overwrite}]
    })
  end
end
