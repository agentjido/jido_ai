defmodule JidoAI.Examples.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoAI.Examples.Case
      alias JidoAI.Examples.MockLLM
      alias Jido.AgentServer, as: Server
      @moduletag :integration
    end
  end

  setup do
    name = :"ai_v3_example_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: name})
    {:ok, jido: name}
  end

  def mock(script) do
    server = start_supervised!({JidoAI.Examples.MockLLM, script: script, observer: self()})

    context = %{
      model: JidoAI.Examples.MockLLM.model(),
      model_options: JidoAI.Examples.MockLLM.options(server),
      ai: %{assistant: %{options: JidoAI.Examples.MockLLM.options(server)}},
      observer: self()
    }

    {server, context}
  end

  def start_agent(jido, agent) do
    {:ok, server} = Jido.start_agent(jido, agent)
    server
  end

  def ask(server, context) do
    Jido.AgentServer.call(server, signal(), context: context, timeout: 10_000)
  end

  def signal,
    do: Jido.Signal.new!("ai.ask", %{query: "Help with this case"}, source: "/examples/ai")

  def assert_script_done(mock) do
    assert %{remaining: [], unexpected: [], waiting: []} = JidoAI.Examples.MockLLM.report(mock)
  end
end
