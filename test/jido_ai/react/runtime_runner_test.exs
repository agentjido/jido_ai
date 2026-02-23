defmodule Jido.AI.Reasoning.ReAct.RuntimeRunnerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.Config
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReActStrategy

  defmodule RetryTool do
    use Jido.Action,
      name: "retry_tool",
      description: "Fails once then succeeds",
      schema:
        Zoi.object(%{
          value: Zoi.integer()
        })

    def run(%{value: value}, _context) do
      key = {__MODULE__, :attempts}
      attempt = :persistent_term.get(key, 0) + 1
      :persistent_term.put(key, attempt)

      if attempt == 1 do
        {:error, :transient_error}
      else
        {:ok, %{value: value, attempt: attempt}}
      end
    end
  end

  defmodule CalculatorTool do
    use Jido.Action,
      name: "calculator",
      description: "simple calculator",
      schema:
        Zoi.object(%{
          a: Zoi.integer(),
          b: Zoi.integer()
        })

    def run(%{a: a, b: b}, _context), do: {:ok, %{result: a + b}}
  end

  setup :set_mimic_from_context

  setup do
    on_exit(fn ->
      :persistent_term.erase({RetryTool, :attempts})
      :persistent_term.erase({__MODULE__, :llm_call_count})
    end)

    :ok
  end

  test "emits ordered event envelopes for a final-answer run" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      {:ok,
       %{
         stream: [ReqLLM.StreamChunk.text("Hello world")],
         usage: %{input_tokens: 3, output_tokens: 2}
       }}
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    config = Config.new(%{model: :capable, tools: %{}})

    events =
      ReAct.stream("Say hello", config, request_id: "req_evt", run_id: "run_evt")
      |> Enum.to_list()

    assert length(events) >= 6
    assert Enum.all?(events, &is_map/1)

    seqs = Enum.map(events, & &1.seq)
    assert seqs == Enum.sort(seqs)
    assert seqs == Enum.uniq(seqs)

    first = hd(events)
    assert first.kind == :request_started
    assert Map.has_key?(first, :id)
    assert Map.has_key?(first, :at_ms)
    assert first.request_id == "req_evt"
    assert first.run_id == "run_evt"

    assert Enum.any?(events, &(&1.kind == :llm_started))
    assert Enum.any?(events, &(&1.kind == :llm_delta))
    assert Enum.any?(events, &(&1.kind == :llm_completed))
    assert Enum.any?(events, &(&1.kind == :request_completed))
    assert Enum.any?(events, &(&1.kind == :checkpoint and &1.data.reason == :terminal))
  end

  test "uses non-streaming generation when streaming is disabled" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      flunk("stream_text should not be called when ReAct streaming is disabled")
    end)

    Mimic.stub(ReqLLM.Generation, :generate_text, fn _model, _messages, _opts ->
      {:ok,
       %{
         message: %{content: "Hello from generate", tool_calls: nil},
         finish_reason: :stop,
         usage: %{input_tokens: 3, output_tokens: 2}
       }}
    end)

    config = Config.new(%{model: :capable, tools: %{}, streaming: false})

    events =
      ReAct.stream("Say hello", config, request_id: "req_non_stream", run_id: "run_non_stream")
      |> Enum.to_list()

    assert Enum.any?(events, &(&1.kind == :request_started))
    assert Enum.any?(events, &(&1.kind == :llm_started))
    refute Enum.any?(events, &(&1.kind == :llm_delta))
    assert Enum.any?(events, &(&1.kind == :llm_completed))
    assert Enum.any?(events, &(&1.kind == :request_completed))
    assert Enum.any?(events, &(&1.kind == :checkpoint and &1.data.reason == :terminal))

    llm_completed = Enum.find(events, &(&1.kind == :llm_completed))
    assert llm_completed.data.text == "Hello from generate"
    assert llm_completed.data.turn_type == :final_answer

    request_completed = Enum.find(events, &(&1.kind == :request_completed))
    assert request_completed.data.result == "Hello from generate"
  end

  test "passes req_http_options to streaming requests" do
    req_http_options = [plug: {Req.Test, []}]
    llm_opts = [thinking: %{type: :enabled, budget_tokens: 1_024}, reasoning_effort: :high]

    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, opts ->
      assert opts[:req_http_options] == req_http_options
      assert opts[:thinking] == %{type: :enabled, budget_tokens: 1_024}
      assert opts[:reasoning_effort] == :high

      {:ok,
       %{
         stream: [ReqLLM.StreamChunk.text("Hello with req_http_options")],
         usage: %{input_tokens: 2, output_tokens: 2}
       }}
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    config = Config.new(%{model: :capable, tools: %{}, req_http_options: req_http_options, llm_opts: llm_opts})
    events = ReAct.stream("Say hello", config) |> Enum.to_list()

    assert Enum.any?(events, &(&1.kind == :request_completed))
  end

  test "passes req_http_options to non-streaming requests" do
    req_http_options = [plug: {Req.Test, []}]
    llm_opts = [thinking: %{type: :enabled, budget_tokens: 2_048}, reasoning_effort: :low]

    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      flunk("stream_text should not be called when ReAct streaming is disabled")
    end)

    Mimic.stub(ReqLLM.Generation, :generate_text, fn _model, _messages, opts ->
      assert opts[:req_http_options] == req_http_options
      assert opts[:thinking] == %{type: :enabled, budget_tokens: 2_048}
      assert opts[:reasoning_effort] == :low

      {:ok,
       %{
         message: %{content: "Hello from generate", tool_calls: nil},
         finish_reason: :stop,
         usage: %{input_tokens: 1, output_tokens: 1}
       }}
    end)

    config =
      Config.new(%{
        model: :capable,
        tools: %{},
        streaming: false,
        req_http_options: req_http_options,
        llm_opts: llm_opts
      })

    events = ReAct.stream("Say hello", config) |> Enum.to_list()

    assert Enum.any?(events, &(&1.kind == :request_completed))
  end

  test "normalizes string-key llm_opts maps and forwards known options" do
    llm_opts = %{
      "thinking" => %{type: :enabled, budget_tokens: 768},
      "reasoning_effort" => :medium,
      "unknown_provider_flag" => true
    }

    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, opts ->
      assert opts[:thinking] == %{type: :enabled, budget_tokens: 768}
      assert opts[:reasoning_effort] == :medium
      refute Keyword.has_key?(opts, :unknown_provider_flag)

      {:ok,
       %{
         stream: [ReqLLM.StreamChunk.text("String-key llm opts normalized")],
         usage: %{input_tokens: 2, output_tokens: 2}
       }}
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    config = Config.new(%{model: :capable, tools: %{}, llm_opts: llm_opts})
    events = ReAct.stream("Say hello", config) |> Enum.to_list()

    assert Enum.any?(events, &(&1.kind == :request_completed))
  end

  test "retries tool execution and reports attempts in tool_completed" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      if count == 1 do
        {:ok,
         %{
           stream: [ReqLLM.StreamChunk.tool_call("retry_tool", %{"value" => 7}, %{id: "tc_retry"})],
           usage: %{input_tokens: 5, output_tokens: 3}
         }}
      else
        {:ok,
         %{
           stream: [ReqLLM.StreamChunk.text("Tool complete")],
           usage: %{input_tokens: 2, output_tokens: 1}
         }}
      end
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    config =
      Config.new(%{
        model: :capable,
        tools: %{RetryTool.name() => RetryTool},
        tool_max_retries: 2,
        tool_retry_backoff_ms: 0
      })

    events = ReAct.stream("Run retry tool", config) |> Enum.to_list()

    tool_completed = Enum.find(events, &(&1.kind == :tool_completed))
    refute is_nil(tool_completed)
    assert tool_completed.data.attempts == 2
    assert match?({:ok, _}, tool_completed.data.result)
  end

  test "resumes from after_llm checkpoint token" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      if count == 1 do
        {:ok,
         %{
           stream: [ReqLLM.StreamChunk.tool_call("calculator", %{"a" => 2, "b" => 3}, %{id: "tc_calc"})],
           usage: %{input_tokens: 4, output_tokens: 3}
         }}
      else
        {:ok,
         %{
           stream: [ReqLLM.StreamChunk.text("Result is 5")],
           usage: %{input_tokens: 2, output_tokens: 2}
         }}
      end
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    config =
      Config.new(%{
        model: :capable,
        tools: %{CalculatorTool.name() => CalculatorTool},
        token_secret: "resume-secret"
      })

    after_llm_token =
      ReAct.stream("Calculate", config)
      |> Enum.reduce_while(nil, fn event, _acc ->
        if event.kind == :checkpoint and event.data.reason == :after_llm do
          {:halt, event.data.token}
        else
          {:cont, nil}
        end
      end)

    assert is_binary(after_llm_token)

    assert {:ok, resumed} = ReAct.continue(after_llm_token, config)
    collected = ReAct.collect_stream(resumed.events)

    assert collected.termination_reason == :final_answer
    assert collected.result == "Result is 5"
    assert is_binary(collected.final_token)
  end

  test "halting event consumption cancels active runner task" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      infinite_stream =
        Stream.repeatedly(fn ->
          Process.sleep(5)
          ReqLLM.StreamChunk.text("x")
        end)

      {:ok, %{stream: infinite_stream, usage: %{input_tokens: 1, output_tokens: 1}}}
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    {:ok, task_supervisor} = Task.Supervisor.start_link()
    on_exit(fn -> if Process.alive?(task_supervisor), do: Process.exit(task_supervisor, :shutdown) end)

    config = Config.new(%{model: :capable, tools: %{}})

    [first_event] =
      ReAct.stream("cancel me", config, task_supervisor: task_supervisor)
      |> Enum.take(1)

    assert first_event.kind == :request_started

    assert wait_until(fn ->
             Task.Supervisor.children(task_supervisor) == []
           end)
  end

  test "strategy consumes runtime runner event stream to terminal state" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      {:ok,
       %{
         stream: [ReqLLM.StreamChunk.text("Hello from runtime runner")],
         usage: %{input_tokens: 3, output_tokens: 2}
       }}
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    request_id = "req_strategy_runtime"

    runtime_events =
      ReAct.stream("Say hello", Config.new(%{model: :capable, tools: %{}}), request_id: request_id, run_id: request_id)
      |> Enum.map(&Map.from_struct/1)

    agent = create_strategy_agent(tools: [CalculatorTool])

    {agent, [_spawn]} =
      ReActStrategy.cmd(
        agent,
        [strategy_instruction(ReActStrategy.start_action(), %{query: "Say hello", request_id: request_id})],
        %{}
      )

    {agent, []} =
      Enum.reduce(runtime_events, {agent, []}, fn event, {acc_agent, _} ->
        ReActStrategy.cmd(
          acc_agent,
          [strategy_instruction(:ai_react_worker_event, %{request_id: request_id, event: event})],
          %{}
        )
      end)

    state = StratState.get(agent, %{})
    assert state.status == :completed
    assert state.result == "Hello from runtime runner"
    assert state.termination_reason == :final_answer
    assert state.active_request_id == nil
    assert state.react_worker_status == :ready
  end

  defp create_strategy_agent(opts) do
    %Jido.Agent{
      id: "react_strategy_test_agent",
      name: "react_strategy_test_agent",
      state: %{}
    }
    |> then(fn agent ->
      {agent, []} = ReActStrategy.init(agent, %{strategy_opts: opts})
      agent
    end)
  end

  defp strategy_instruction(action, params) do
    %Jido.Instruction{action: action, params: params}
  end

  defp wait_until(fun, timeout_ms \\ 500) when is_function(fun, 0) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_until_loop(fun, deadline)
  end

  defp wait_until_loop(fun, deadline) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(5)
        wait_until_loop(fun, deadline)
      end
    end
  end
end
