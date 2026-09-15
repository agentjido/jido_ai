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
    opts = Keyword.merge([name: "root_reasoning", streaming: false], opts)
    model = Keyword.get(opts, :model, :fast)
    output = Jido.AI.Output.new!(opts[:output])

    generation =
      opts
      |> Keyword.get(:llm_opts, [])
      |> Jido.AI.Reasoning.ReAct.Config.normalize_option_names()
      |> Enum.into([])
      |> then(fn values ->
        values = if opts[:temperature], do: Keyword.put(values, :temperature, opts[:temperature]), else: values
        values = if opts[:max_tokens], do: Keyword.put(values, :max_tokens, opts[:max_tokens]), else: values

        values =
          if opts[:llm_timeout_ms],
            do: Keyword.put(values, :receive_timeout, opts[:llm_timeout_ms]),
            else: values

        if opts[:req_http_options],
          do: Keyword.put(values, :req_http_options, opts[:req_http_options]),
          else: values
      end)

    instructions =
      case opts[:system_prompt] do
        value when value in [nil, false, ""] -> default_instructions(method)
        value -> value
      end

    tools =
      Enum.map(Keyword.get(opts, :tools, []), fn target ->
        %{
          target: target,
          forward_context: :all,
          timeout: Keyword.get(opts, :tool_timeout_ms, 15_000),
          max_retries: Keyword.get(opts, :tool_max_retries, 1),
          retry_backoff: Keyword.get(opts, :tool_retry_backoff_ms, 200)
        }
      end)

    result =
      if output do
        %{
          schema: output.schema,
          into: :last_result,
          max_repairs: if(output.on_validation_error == :repair, do: output.retries, else: 0),
          repair_fun: output.repair_fun,
          on_validation_error: output.on_validation_error
        }
      else
        %{schema: nil, into: :last_result}
      end

    requests = %{
      mode: :session,
      streaming: Keyword.get(opts, :streaming, false),
      steering: method == :react,
      on_busy: Keyword.get(opts, :request_policy, :reject)
    }

    requests =
      if timeout = opts[:stream_timeout_ms],
        do: Map.put(requests, :idle_timeout, timeout),
        else: requests

    profile =
      Jido.AI.profile!(%{
        id: :assistant,
        instructions: instructions,
        models: %{answer: %{model: model, generation: generation}},
        reasoning: %{
          method: method,
          model: :answer,
          options: Keyword.get(opts, :reasoning_options, %{}),
          request_transformer: opts[:request_transformer],
          effect_policy: Keyword.get(opts, :strategy_effect_policy, %{})
        },
        controls: %{
          max_iterations: Keyword.get(opts, :max_iterations, 10),
          max_model_calls: Keyword.get(opts, :max_model_calls, Keyword.get(opts, :max_iterations, 10)),
          max_tool_calls: Keyword.get(opts, :max_tool_calls, 16),
          timeout: Keyword.get(opts, :request_timeout_ms, 60_000)
        },
        requests: requests,
        effect_policy: Keyword.get(opts, :effect_policy, %{}),
        tool_context: Keyword.get(opts, :tool_context, %{}),
        tools: tools,
        result: result,
        memory: %{history: if(method == :react, do: :messages, else: nil)}
      })

    schema =
      Zoi.object(%{
        model: Zoi.any() |> Zoi.default(model),
        last_request_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
        last_query: Jido.AI.Query.schema() |> Zoi.default(""),
        last_prompt: Jido.AI.Query.schema() |> Zoi.default(""),
        last_result: Zoi.any() |> Zoi.default(nil),
        completed: Zoi.boolean() |> Zoi.default(false),
        messages: Jido.AI.Conversation.schema(),
        selected_strategy: Zoi.atom() |> Zoi.nullable() |> Zoi.default(nil)
      })

    {:ok, definition} =
      Jido.AI.Authoring.lower(
        %{
          name: opts[:name],
          schema: schema,
          plugins: [],
          routes: [{"ai.#{Jido.AI.Reasoning.label(method)}.query", Jido.AI.Authoring.ai(:assistant)}]
        },
        [profile]
      )

    definition
  end

  defp default_instructions(method) do
    cond do
      Jido.AI.Reasoning.Linear.linear?(method) -> Jido.AI.Reasoning.Linear.default_prompt(method)
      method == :react -> Jido.AI.Reasoning.react_prompt()
      true -> nil
    end
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
