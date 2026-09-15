defmodule JidoAI.Examples.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoAI.Examples.Case
      alias JidoAI.Examples.MockLLM
      alias Jido.AgentServer, as: Server
      @moduletag :example
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

  def conversation_entries(%Jido.Thread{} = thread) do
    {:ok, selected} = Jido.AI.Conversation.select(thread)

    Enum.map(selected.entries, fn entry ->
      {:ok, message} = Jido.AI.Conversation.message(entry)
      message |> Map.from_struct() |> Map.put(:refs, entry.refs)
    end)
  end

  def conversation(agent) do
    {:ok, profile} = Jido.AI.Configuration.profile(agent)
    {:ok, entries} = Jido.AI.History.read(agent.state, profile)
    entries
  end

  # Keep provider substitution in test support, not in the teaching Agent.
  def native_mock(script) do
    {server, _context} = mock(script)

    {server, %{ai: %{assistant: %{options: JidoAI.Examples.MockLLM.options(server)}}}}
  end

  def observe_tools, do: JidoAI.Examples.ToolEvents.attach()

  def ask(server, context) do
    Jido.AgentServer.call(server, signal(), context: context, timeout: 10_000)
  end

  def signal,
    do: Jido.Signal.new!("ai.ask", %{query: "Help with this case"}, source: "/examples/ai")

  def assert_script_done(mock) do
    assert %{remaining: [], unexpected: [], waiting: []} = JidoAI.Examples.MockLLM.report(mock)
  end

  def profile_atoms(source) do
    {:ok, {profile, routes}} = Jido.AI.Profile.source(source)

    profile
    |> Map.from_struct()
    |> Map.put(:routes, routes)
    |> static_atoms()
    |> Enum.uniq()
  end

  defp static_atoms(value) when is_atom(value), do: [value]
  defp static_atoms(value) when is_list(value), do: Enum.flat_map(value, &static_atoms/1)
  defp static_atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> static_atoms()
  defp static_atoms(%_{}), do: []

  defp static_atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {key, item} -> static_atoms(key) ++ static_atoms(item) end)

  defp static_atoms(_value), do: []
end
