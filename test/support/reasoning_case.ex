defmodule Jido.AI.Test.ReasoningCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Jido.AI.Test.ReasoningCase
      alias Jido.AgentServer, as: Server
      alias Jido.AI.{Configuration, Request, Session}
      alias Jido.AI.Test.MockLLM
    end
  end

  setup do
    jido = :"root_reasoning_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  def definition(method, opts \\ []) do
    [name: "root_reasoning", reasoning: method, streaming: false]
    |> Keyword.merge(opts)
    |> Jido.AI.Agent.Options.lower!()
    |> Jido.Agent.new!()
  end

  def start_reasoning(jido, method, opts \\ []) do
    agent = definition(method, Keyword.put_new(opts, :model, Jido.AI.Test.MockLLM.model()))
    start_agent(jido, Jido.Agent.instantiate!(agent))
  end

  def start_agent(jido, agent) do
    assert {:ok, server} = Jido.start_agent(jido, agent, default_dispatch: {:pid, target: self()})
    server
  end

  def mock(script) do
    start_supervised!({Jido.AI.Test.MockLLM, script: script, observer: self()})
  end

  def request(server, mock, method, query \\ "What is 2 + 2?", opts \\ []) do
    Jido.AI.Request.create_and_send(
      server,
      query,
      Keyword.merge(
        [
          signal_type: "ai.#{Jido.AI.Reasoning.label(method)}.query",
          source: "/test/reasoning",
          model: Jido.AI.Test.MockLLM.model(),
          llm_opts: Jido.AI.Test.MockLLM.options(mock),
          stream_to: self()
        ],
        opts
      )
    )
  end

  def record(server, request), do: Jido.AgentServer.agent(server).state.requests[request.id]

  def events(request),
    do: request |> Jido.AI.Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  def owner(server), do: Jido.AgentServer.children(server)[{:plugin, Jido.AI.Session.Plugin}].pid

  def assert_script_done(mock) do
    assert %{remaining: [], unexpected: [], waiting: []} = Jido.AI.Test.MockLLM.report(mock)
  end

  def eventually(check, attempts \\ 200)
  def eventually(check, 0), do: assert(check.())

  def eventually(check, attempts) do
    if check.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(check, attempts - 1)
        )
  end

  def response(content, usage \\ %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}) do
    {:raw,
     %{
       id: "root-linear",
       object: "chat.completion",
       model: "gpt-4o-mini",
       choices: [%{index: 0, message: %{role: "assistant", content: content}, finish_reason: "stop"}],
       usage: usage
     }}
  end
end
