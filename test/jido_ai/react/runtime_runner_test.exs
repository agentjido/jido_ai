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

  defmodule SlowOrderTool do
    use Jido.Action,
      name: "slow_order_tool",
      description: "completes after fast tool",
      schema: Zoi.object(%{})

    def run(_params, _context) do
      Process.sleep(40)

      {:ok, %{marker: :slow},
       [
         %Jido.Agent.StateOp.SetState{
           attrs: %{react_order_marker: :slow}
         }
       ]}
    end
  end

  defmodule FastOrderTool do
    use Jido.Action,
      name: "fast_order_tool",
      description: "completes before slow tool",
      schema: Zoi.object(%{})

    def run(_params, _context) do
      {:ok, %{marker: :fast},
       [
         %Jido.Agent.StateOp.SetState{
           attrs: %{react_order_marker: :fast}
         }
       ]}
    end
  end

  defmodule SnapshotStateTool do
    use Jido.Action,
      name: "snapshot_state_tool",
      description: "reads agent state snapshot and appends to sums",
      schema:
        Zoi.object(%{
          step: Zoi.integer()
        })

    def run(%{step: step}, context) do
      snapshot = context[:state] || %{}
      seen = Map.get(snapshot, :sums, [])

      {:ok,
       %{
         seen: seen,
         step: step,
         has_state: is_map(context[:state])
       },
       [
         %Jido.Agent.StateOp.SetState{
           attrs: %{sums: seen ++ [step]}
         }
       ]}
    end
  end

  defmodule SeenCodesTool do
    use Jido.Action,
      name: "seen_codes_tool",
      description: "returns codes and stores them in the runtime state snapshot",
      schema: Zoi.object(%{})

    def run(_params, _context) do
      seen_codes = ["8409.91.01", "8409.99.99"]

      {:ok, %{seen_codes: seen_codes},
       [
         %Jido.Agent.StateOp.SetState{
           attrs: %{seen_codes: seen_codes}
         }
       ]}
    end
  end

  defmodule DynamicToolSchemaTransformer do
    alias Jido.AI.Reasoning.ReAct.ToolSelection

    def transform_request(request, _state, _config, runtime_context) do
      seen_codes = get_in(runtime_context, [:state, :seen_codes]) || []

      case seen_codes do
        [] ->
          {:ok, %{tools: only(request.tools, [SeenCodesTool.name()])}}

        codes ->
          {:ok,
           %{
             tools: %{},
             llm_opts: [
               provider_options: [
                 response_schema: %{
                   type: "object",
                   properties: %{code: %{enum: codes}}
                 }
               ]
             ]
           }}
      end
    end

    defp only(tools, names) do
      {:ok, filtered} = ToolSelection.filter_allowed(tools, names)
      filtered
    end
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
    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      {:ok,
       responses_stream_response(
         [ReqLLM.StreamChunk.text("Hello world")],
         %{finish_reason: :stop, usage: %{input_tokens: 3, output_tokens: 2}},
         model
       )}
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

  test "passes inline model specs through to ReqLLM requests" do
    inline_model = %{provider: :openai, id: "gpt-4o-mini", base_url: "http://localhost:4000/v1"}

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      assert model == inline_model

      {:ok,
       responses_stream_response(
         [ReqLLM.StreamChunk.text("Hello from inline model")],
         %{finish_reason: :stop, usage: %{input_tokens: 3, output_tokens: 2}},
         model
       )}
    end)

    config = Config.new(%{model: inline_model, tools: %{}})

    events =
      ReAct.stream("Say hello", config, request_id: "req_inline_model", run_id: "run_inline_model")
      |> Enum.to_list()

    assert Enum.any?(events, &(&1.kind == :request_completed))
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

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, opts ->
      assert opts[:req_http_options] == req_http_options
      assert opts[:thinking] == %{type: :enabled, budget_tokens: 1_024}
      assert opts[:reasoning_effort] == :high

      {:ok,
       responses_stream_response(
         [ReqLLM.StreamChunk.text("Hello with req_http_options")],
         %{finish_reason: :stop, usage: %{input_tokens: 2, output_tokens: 2}},
         model
       )}
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

  test "normalizes string-key llm_opts maps and forwards ReqLLM options" do
    llm_opts = %{
      "thinking" => %{type: :enabled, budget_tokens: 768},
      "reasoning_effort" => :medium,
      "top_p" => 0.75,
      "unknown_provider_flag" => true
    }

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, opts ->
      assert opts[:thinking] == %{type: :enabled, budget_tokens: 768}
      assert opts[:reasoning_effort] == :medium
      assert opts[:top_p] == 0.75
      refute Keyword.has_key?(opts, nil)

      {:ok,
       responses_stream_response(
         [ReqLLM.StreamChunk.text("String-key llm opts normalized")],
         %{finish_reason: :stop, usage: %{input_tokens: 2, output_tokens: 2}},
         model
       )}
    end)

    config = Config.new(%{model: :capable, tools: %{}, llm_opts: llm_opts})
    events = ReAct.stream("Say hello", config) |> Enum.to_list()

    assert Enum.any?(events, &(&1.kind == :request_completed))
  end

  test "normalizes provider_options maps in llm_opts before forwarding to ReqLLM" do
    llm_opts = %{
      "provider_options" => %{
        "verbosity" => "high",
        "__jido_ai_nonexistent_provider_option__" => true
      }
    }

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, opts ->
      assert opts[:provider_options] == [verbosity: "high"]

      {:ok,
       responses_stream_response(
         [ReqLLM.StreamChunk.text("Provider options normalized")],
         %{finish_reason: :stop, usage: %{input_tokens: 2, output_tokens: 2}},
         model
       )}
    end)

    config = Config.new(%{model: "openai:gpt-4o", tools: %{}, llm_opts: llm_opts})
    events = ReAct.stream("Say hello", config) |> Enum.to_list()

    assert Enum.any?(events, &(&1.kind == :request_completed))
  end

  test "passes previous_response_id between streaming tool rounds for OpenAI Responses models" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      previous_response_id =
        opts
        |> Keyword.get(:provider_options, [])
        |> Keyword.get(:previous_response_id)

      case count do
        1 ->
          assert is_nil(previous_response_id)

          {:ok,
           responses_stream_response(
             [
               ReqLLM.StreamChunk.tool_call("calculator", %{"a" => 2, "b" => 3}, %{id: "call_calc_1"}),
               ReqLLM.StreamChunk.meta(%{
                 finish_reason: :tool_calls,
                 response_id: "resp_tool_round_1",
                 usage: %{input_tokens: 4, output_tokens: 2}
               })
             ],
             %{
               finish_reason: :tool_calls,
               response_id: "resp_tool_round_1",
               usage: %{input_tokens: 4, output_tokens: 2}
             },
             "openai:gpt-4o-mini"
           )}

        2 ->
          assert previous_response_id == "resp_tool_round_1"

          {:ok,
           responses_stream_response(
             [
               ReqLLM.StreamChunk.text("Result is 5"),
               ReqLLM.StreamChunk.meta(%{
                 finish_reason: :stop,
                 response_id: "resp_tool_round_2",
                 usage: %{input_tokens: 3, output_tokens: 2}
               })
             ],
             %{
               finish_reason: :stop,
               response_id: "resp_tool_round_2",
               usage: %{input_tokens: 3, output_tokens: 2}
             },
             "openai:gpt-4o-mini"
           )}
      end
    end)

    config =
      Config.new(%{
        model: "openai:gpt-4o-mini",
        tools: %{CalculatorTool.name() => CalculatorTool},
        tool_max_retries: 0,
        tool_retry_backoff_ms: 0
      })

    events = ReAct.stream("Calculate 2 + 3", config) |> Enum.to_list()

    request_completed = Enum.find(events, &(&1.kind == :request_completed))
    assert request_completed.data.result == "Result is 5"
  end

  test "keeps tool-call argument fragment streams alive across idle timeout" do
    Mimic.stub(ReqLLM.StreamResponse, :process_stream, &process_stream_response/2)

    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      case count do
        1 ->
          arg_fragments = chunk_string(~s({"a":2,"b":3}), 2)

          chunks =
            [
              ReqLLM.StreamChunk.tool_call("calculator", %{}, %{id: "tc_calc_fragments", index: 0})
              | Enum.map(arg_fragments, fn fragment ->
                  ReqLLM.StreamChunk.meta(%{tool_call_args: %{index: 0, fragment: fragment}})
                end)
            ]

          {:ok,
           %{
             stream: delayed_stream(chunks, 30),
             finish_reason: :tool_calls,
             usage: %{input_tokens: 4, output_tokens: 2}
           }}

        2 ->
          {:ok,
           %{
             stream: delayed_stream([ReqLLM.StreamChunk.text("Result is 5")], 30),
             finish_reason: :stop,
             usage: %{input_tokens: 3, output_tokens: 2}
           }}
      end
    end)

    config =
      Config.new(%{
        model: "anthropic:claude-sonnet-4-5",
        tools: %{CalculatorTool.name() => CalculatorTool},
        stream_timeout_ms: 120,
        tool_max_retries: 0,
        tool_retry_backoff_ms: 0
      })

    events = ReAct.stream("Calculate 2 + 3", config) |> Enum.to_list()

    request_completed = Enum.find(events, &(&1.kind == :request_completed))
    tool_completed = Enum.find(events, &(&1.kind == :tool_completed and &1.data.tool_call_id == "tc_calc_fragments"))

    assert request_completed.data.result == "Result is 5"
    assert {:ok, %{result: 5}, _effects} = tool_completed.data.result
  end

  test "keeps active streams alive when llm deltas are not captured" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      {:ok,
       responses_stream_response(
         delayed_stream(
           [
             ReqLLM.StreamChunk.text("Hello "),
             ReqLLM.StreamChunk.text("from "),
             ReqLLM.StreamChunk.text("stream")
           ],
           35
         ),
         %{finish_reason: :stop, usage: %{input_tokens: 2, output_tokens: 3}},
         model
       )}
    end)

    config =
      Config.new(%{
        model: :capable,
        tools: %{},
        capture_deltas?: false,
        stream_timeout_ms: 150
      })

    events = ReAct.stream("Say hello", config) |> Enum.to_list()
    request_completed = Enum.find(events, &(&1.kind == :request_completed))

    refute Enum.any?(events, &(&1.kind == :llm_delta))
    assert request_completed.data.result == "Hello from stream"
  end

  test "throttles synthetic progress for dense hidden chunk streams" do
    parent = self()
    hidden_text_chunks = for _ <- 1..200, do: ReqLLM.StreamChunk.text("x")

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      {:ok,
       responses_stream_response(
         delayed_stream(hidden_text_chunks, 2),
         %{finish_reason: :stop, usage: %{input_tokens: 2, output_tokens: 200}},
         model
       )}
    end)

    config =
      Config.new(%{
        model: :capable,
        tools: %{},
        capture_deltas?: false,
        stream_timeout_ms: 120
      })

    consumer =
      spawn(fn ->
        send(parent, {:consumer_started, self()})
        send(parent, {:consumer_done, ReAct.stream("Dense hidden stream", config) |> Enum.to_list()})
      end)

    assert_receive {:consumer_started, ^consumer}, 200
    Process.sleep(180)

    assert {:message_queue_len, queue_len} = Process.info(consumer, :message_queue_len)
    assert queue_len < 20

    assert_receive {:consumer_done, events}, 2_000
    request_completed = Enum.find(events, &(&1.kind == :request_completed))
    assert request_completed.data.result == String.duplicate("x", 200)
  end

  test "halts inactive streams after stream_timeout_ms" do
    parent = self()

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      {:ok,
       responses_stream_response(
         delayed_stream([ReqLLM.StreamChunk.text("too late")], 250),
         %{finish_reason: :stop, usage: %{input_tokens: 1, output_tokens: 1}},
         model,
         cancel: fn ->
           send(parent, :idle_stream_cancelled)
           :ok
         end
       )}
    end)

    config =
      Config.new(%{
        model: :capable,
        tools: %{},
        stream_timeout_ms: 80
      })

    started_at = System.monotonic_time(:millisecond)
    events = ReAct.stream("stall", config) |> Enum.to_list()
    elapsed_ms = System.monotonic_time(:millisecond) - started_at

    assert elapsed_ms >= 60
    assert elapsed_ms < 200
    refute Enum.any?(events, &(&1.kind == :request_completed))
    assert_receive :idle_stream_cancelled, 200
  end

  test "preserves reasoning_details across tool turns" do
    parent = self()

    reasoning_details = [
      %ReqLLM.Message.ReasoningDetails{
        text: "Need calculator result before answering",
        signature: "rsig_123",
        encrypted?: true,
        provider: :openai,
        format: "responses/v1",
        index: 0,
        provider_data: %{token: "opaque-token"}
      }
    ]

    Mimic.stub(ReqLLM.StreamResponse, :process_stream, &process_stream_response/2)

    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, messages, _opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      case count do
        1 ->
          {:ok,
           %{
             stream: [ReqLLM.StreamChunk.tool_call("calculator", %{"a" => 2, "b" => 3}, %{id: "tc_reasoning"})],
             finish_reason: :tool_calls,
             reasoning_details: reasoning_details,
             usage: %{input_tokens: 4, output_tokens: 2}
           }}

        2 ->
          assistant_message =
            Enum.find(messages, fn
              %{role: role, tool_calls: tool_calls} when role in [:assistant, "assistant"] ->
                is_list(tool_calls) and tool_calls != []

              _ ->
                false
            end)

          send(parent, {:assistant_reasoning_details, Map.get(assistant_message, :reasoning_details)})

          {:ok,
           %{
             stream: [ReqLLM.StreamChunk.text("Result is 5")],
             finish_reason: :stop,
             usage: %{input_tokens: 3, output_tokens: 2}
           }}
      end
    end)

    config =
      Config.new(%{
        model: :capable,
        tools: %{CalculatorTool.name() => CalculatorTool},
        tool_max_retries: 0,
        tool_retry_backoff_ms: 0
      })

    events = ReAct.stream("Calculate 2 + 3", config) |> Enum.to_list()
    request_completed = Enum.find(events, &(&1.kind == :request_completed))

    assert_receive {:assistant_reasoning_details, ^reasoning_details}, 200
    assert request_completed.data.result == "Result is 5"
  end

  test "retries tool execution and reports attempts in tool_completed" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      if count == 1 do
        {:ok,
         responses_stream_response(
           [ReqLLM.StreamChunk.tool_call("retry_tool", %{"value" => 7}, %{id: "tc_retry"})],
           %{finish_reason: :tool_calls, usage: %{input_tokens: 5, output_tokens: 3}},
           model
         )}
      else
        {:ok,
         responses_stream_response(
           [ReqLLM.StreamChunk.text("Tool complete")],
           %{finish_reason: :stop, usage: %{input_tokens: 2, output_tokens: 1}},
           model
         )}
      end
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
    assert match?({:ok, _, _}, tool_completed.data.result)
  end

  test "emits tool_completed events in original tool call order for parallel tools" do
    stub_parallel_order_run()

    config =
      Config.new(%{
        model: :capable,
        tools: %{SlowOrderTool.name() => SlowOrderTool, FastOrderTool.name() => FastOrderTool},
        tool_max_retries: 0,
        tool_retry_backoff_ms: 0
      })

    events = ReAct.stream("Run tools in order", config) |> Enum.to_list()

    tool_completed_ids =
      events
      |> Enum.filter(&(&1.kind == :tool_completed))
      |> Enum.map(& &1.data.tool_call_id)

    assert tool_completed_ids == ["tc_slow", "tc_fast"]
  end

  test "strategy applies tool effects in deterministic call order" do
    stub_parallel_order_run()
    request_id = "req_strategy_ordering"

    runtime_events =
      ReAct.stream(
        "Run tools in order",
        Config.new(%{
          model: :capable,
          tools: %{SlowOrderTool.name() => SlowOrderTool, FastOrderTool.name() => FastOrderTool},
          tool_max_retries: 0,
          tool_retry_backoff_ms: 0
        }),
        request_id: request_id,
        run_id: request_id
      )
      |> Enum.map(&Map.from_struct/1)

    tool_completed_ids =
      runtime_events
      |> Enum.filter(&(&1.kind == :tool_completed))
      |> Enum.map(&get_in(&1, [:data, :tool_call_id]))

    assert tool_completed_ids == ["tc_slow", "tc_fast"]

    agent = create_strategy_agent(tools: [SlowOrderTool, FastOrderTool])

    {agent, [_spawn]} =
      ReActStrategy.cmd(
        agent,
        [strategy_instruction(ReActStrategy.start_action(), %{query: "Run tools in order", request_id: request_id})],
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
    assert state.termination_reason == :final_answer
    assert agent.state.react_order_marker == :fast
  end

  test "refreshes tool context state snapshot between rounds when state effects are allowed" do
    stub_state_snapshot_round_trip()

    config =
      Config.new(%{
        model: :capable,
        tools: %{SnapshotStateTool.name() => SnapshotStateTool},
        tool_max_retries: 0,
        tool_retry_backoff_ms: 0
      })

    events =
      ReAct.stream(
        "Update sums twice",
        config,
        context: %{state: %{sums: []}}
      )
      |> Enum.to_list()

    first_tool_completed = Enum.find(events, &(&1.kind == :tool_completed and &1.data.tool_call_id == "tc_step_1"))
    second_tool_completed = Enum.find(events, &(&1.kind == :tool_completed and &1.data.tool_call_id == "tc_step_2"))

    assert {:ok, %{seen: [], step: 1}, _effects} = first_tool_completed.data.result
    assert {:ok, %{seen: [1], step: 2}, _effects} = second_tool_completed.data.result
  end

  test "does not refresh tool context state snapshot when policy removes state effects" do
    stub_state_snapshot_round_trip()

    config =
      Config.new(%{
        model: :capable,
        tools: %{SnapshotStateTool.name() => SnapshotStateTool},
        tool_max_retries: 0,
        tool_retry_backoff_ms: 0,
        effect_policy: %{mode: :deny_all}
      })

    events =
      ReAct.stream(
        "Update sums twice",
        config,
        context: %{state: %{sums: []}, effect_policy: %{mode: :deny_all}}
      )
      |> Enum.to_list()

    first_tool_completed = Enum.find(events, &(&1.kind == :tool_completed and &1.data.tool_call_id == "tc_step_1"))
    second_tool_completed = Enum.find(events, &(&1.kind == :tool_completed and &1.data.tool_call_id == "tc_step_2"))

    assert {:ok, %{seen: [], step: 1}, _effects} = first_tool_completed.data.result
    assert {:ok, %{seen: [], step: 2}, _effects} = second_tool_completed.data.result
  end

  test "uses runtime config effect_policy with standalone state snapshot context" do
    stub_state_snapshot_round_trip()

    config =
      Config.new(%{
        model: :capable,
        tools: %{SnapshotStateTool.name() => SnapshotStateTool},
        tool_max_retries: 0,
        tool_retry_backoff_ms: 0,
        effect_policy: %{mode: :deny_all}
      })

    events =
      ReAct.stream(
        "Update sums twice",
        config,
        context: %{state: %{sums: []}}
      )
      |> Enum.to_list()

    first_tool_completed = Enum.find(events, &(&1.kind == :tool_completed and &1.data.tool_call_id == "tc_step_1"))
    second_tool_completed = Enum.find(events, &(&1.kind == :tool_completed and &1.data.tool_call_id == "tc_step_2"))

    assert {:ok, %{seen: [], step: 1, has_state: true}, _effects} =
             first_tool_completed.data.result

    assert {:ok, %{seen: [], step: 2}, _effects} = second_tool_completed.data.result
  end

  test "resumes from after_llm checkpoint token" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      if count == 1 do
        {:ok,
         responses_stream_response(
           [ReqLLM.StreamChunk.tool_call("calculator", %{"a" => 2, "b" => 3}, %{id: "tc_calc"})],
           %{finish_reason: :tool_calls, usage: %{input_tokens: 4, output_tokens: 3}},
           model
         )}
      else
        {:ok,
         responses_stream_response(
           [ReqLLM.StreamChunk.text("Result is 5")],
           %{finish_reason: :stop, usage: %{input_tokens: 2, output_tokens: 2}},
           model
         )}
      end
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

  test "request_transformer can narrow tools and add llm opts from runtime state" do
    parent = self()

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      case count do
        1 ->
          send(parent, {:turn_one_tool_names, Enum.map(opts[:tools], & &1.name)})

          {:ok,
           responses_stream_response(
             [ReqLLM.StreamChunk.tool_call("seen_codes_tool", %{}, %{id: "tc_seen_codes"})],
             %{finish_reason: :tool_calls, usage: %{input_tokens: 4, output_tokens: 2}},
             model
           )}

        2 ->
          send(parent, {:turn_two_tool_names, Enum.map(opts[:tools], & &1.name)})

          response_schema =
            opts
            |> Keyword.get(:provider_options, [])
            |> Keyword.get(:response_schema)

          send(parent, {:turn_two_response_schema, response_schema})

          {:ok,
           responses_stream_response(
             [ReqLLM.StreamChunk.text("Selected code 8409.91.01")],
             %{finish_reason: :stop, usage: %{input_tokens: 3, output_tokens: 2}},
             model
           )}
      end
    end)

    config =
      Config.new(%{
        model: :capable,
        tools: %{
          CalculatorTool.name() => CalculatorTool,
          SeenCodesTool.name() => SeenCodesTool
        },
        request_transformer: DynamicToolSchemaTransformer,
        tool_max_retries: 0,
        tool_retry_backoff_ms: 0
      })

    events =
      ReAct.stream(
        "Classify using seen codes only",
        config,
        context: %{state: %{seen_codes: []}}
      )
      |> Enum.to_list()

    assert_receive {:turn_one_tool_names, ["seen_codes_tool"]}, 200
    assert_receive {:turn_two_tool_names, []}, 200

    assert_receive {:turn_two_response_schema, response_schema}, 200
    assert get_in(response_schema, [:properties, :code, :enum]) == ["8409.91.01", "8409.99.99"]

    request_completed = Enum.find(events, &(&1.kind == :request_completed))
    assert request_completed.data.result == "Selected code 8409.91.01"
  end

  test "halting event consumption cancels active runner task" do
    parent = self()

    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      infinite_stream =
        Stream.repeatedly(fn ->
          Process.sleep(5)
          ReqLLM.StreamChunk.text("x")
        end)

      {:ok,
       responses_stream_response(
         infinite_stream,
         %{finish_reason: :stop, usage: %{input_tokens: 1, output_tokens: 1}},
         model,
         cancel: fn ->
           send(parent, :stream_cancelled)
           :ok
         end
       )}
    end)

    {:ok, task_supervisor} = Task.Supervisor.start_link()
    on_exit(fn -> if Process.alive?(task_supervisor), do: Process.exit(task_supervisor, :shutdown) end)

    config = Config.new(%{model: :capable, tools: %{}})

    [first_event] =
      ReAct.stream("cancel me", config, task_supervisor: task_supervisor)
      |> Enum.take(1)

    assert first_event.kind == :request_started
    assert_receive :stream_cancelled, 200

    assert wait_until(fn ->
             Task.Supervisor.children(task_supervisor) == []
           end)
  end

  describe "stream_timeout" do
    test "default derives from tool_exec.timeout_ms + 60s" do
      config = Config.new(%{model: :capable, tool_timeout_ms: 120_000})
      assert Config.stream_timeout(config) == 180_000
    end

    test "explicit stream_timeout_ms overrides auto-derive" do
      config = Config.new(%{model: :capable, stream_timeout_ms: 600_000})
      assert Config.stream_timeout(config) == 600_000
    end

    test "default tool timeout gives 75s stream timeout" do
      config = Config.new(%{model: :capable})
      assert Config.stream_timeout(config) == 75_000
    end
  end

  test "strategy consumes runtime runner event stream to terminal state" do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      {:ok,
       responses_stream_response(
         [ReqLLM.StreamChunk.text("Hello from runtime runner")],
         %{finish_reason: :stop, usage: %{input_tokens: 3, output_tokens: 2}},
         model
       )}
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

  defp stub_parallel_order_run do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      if count == 1 do
        {:ok,
         responses_stream_response(
           [
             ReqLLM.StreamChunk.tool_call("slow_order_tool", %{}, %{id: "tc_slow"}),
             ReqLLM.StreamChunk.tool_call("fast_order_tool", %{}, %{id: "tc_fast"})
           ],
           %{finish_reason: :tool_calls, usage: %{input_tokens: 6, output_tokens: 3}},
           model
         )}
      else
        {:ok,
         responses_stream_response(
           [ReqLLM.StreamChunk.text("Tool round complete")],
           %{finish_reason: :stop, usage: %{input_tokens: 2, output_tokens: 1}},
           model
         )}
      end
    end)
  end

  defp stub_state_snapshot_round_trip do
    Mimic.stub(ReqLLM.Generation, :stream_text, fn model, _messages, _opts ->
      count = :persistent_term.get({__MODULE__, :llm_call_count}, 0) + 1
      :persistent_term.put({__MODULE__, :llm_call_count}, count)

      case count do
        1 ->
          {:ok,
           responses_stream_response(
             [ReqLLM.StreamChunk.tool_call("snapshot_state_tool", %{"step" => 1}, %{id: "tc_step_1"})],
             %{finish_reason: :tool_calls, usage: %{input_tokens: 4, output_tokens: 2}},
             model
           )}

        2 ->
          {:ok,
           responses_stream_response(
             [ReqLLM.StreamChunk.tool_call("snapshot_state_tool", %{"step" => 2}, %{id: "tc_step_2"})],
             %{finish_reason: :tool_calls, usage: %{input_tokens: 3, output_tokens: 2}},
             model
           )}

        _ ->
          {:ok,
           responses_stream_response(
             [ReqLLM.StreamChunk.text("Done")],
             %{finish_reason: :stop, usage: %{input_tokens: 2, output_tokens: 1}},
             model
           )}
      end
    end)
  end

  defp delayed_stream(chunks, delay_ms) do
    Stream.map(chunks, fn chunk ->
      Process.sleep(delay_ms)
      chunk
    end)
  end

  defp chunk_string(value, chunk_size) when is_binary(value) and is_integer(chunk_size) and chunk_size > 0 do
    value
    |> String.graphemes()
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(&Enum.join/1)
  end

  defp responses_stream_response(chunks, metadata, model_spec, opts \\ []) do
    {:ok, model} = ReqLLM.model(model_spec)
    {:ok, metadata_handle} = ReqLLM.StreamResponse.MetadataHandle.start_link(fn -> metadata end)

    %ReqLLM.StreamResponse{
      stream: chunks,
      metadata_handle: metadata_handle,
      cancel: Keyword.get(opts, :cancel, fn -> :ok end),
      model: model,
      context: Keyword.get(opts, :context, ReqLLM.Context.new([]))
    }
  end

  defp process_stream_response(%{stream: stream} = stream_response, opts) do
    callbacks = %{
      on_chunk: Keyword.get(opts, :on_chunk),
      on_meta: Keyword.get(opts, :on_meta),
      on_result: Keyword.get(opts, :on_result),
      on_thinking: Keyword.get(opts, :on_thinking),
      on_tool_call: Keyword.get(opts, :on_tool_call)
    }

    chunks =
      Enum.map(stream, fn chunk ->
        invoke_stream_callback(chunk, callbacks)
        chunk
      end)

    summary = ReqLLM.Response.Stream.summarize(chunks)

    {:ok,
     %{
       message: %{
         content: build_stream_content(summary.text, summary.thinking),
         tool_calls: summary.tool_calls,
         reasoning_details: Map.get(stream_response, :reasoning_details)
       },
       finish_reason: stream_finish_reason(summary.tool_calls, Map.get(stream_response, :finish_reason)),
       usage: Map.get(stream_response, :usage, summary.usage),
       model: Map.get(stream_response, :model)
     }}
  end

  defp invoke_stream_callback(chunk, callbacks) do
    maybe_invoke_chunk_callback(chunk, callbacks.on_chunk)
    maybe_invoke_meta_callback(chunk, callbacks.on_meta)
    invoke_stream_specific_callback(chunk, callbacks)
  end

  defp invoke_stream_specific_callback(%ReqLLM.StreamChunk{type: :content, text: text}, %{on_result: callback})
       when is_function(callback, 1) and is_binary(text),
       do: callback.(text)

  defp invoke_stream_specific_callback(%ReqLLM.StreamChunk{type: :thinking, text: text}, %{on_thinking: callback})
       when is_function(callback, 1) and is_binary(text),
       do: callback.(text)

  defp invoke_stream_specific_callback(%ReqLLM.StreamChunk{type: :tool_call} = chunk, %{on_tool_call: callback})
       when is_function(callback, 1),
       do: callback.(chunk)

  defp invoke_stream_specific_callback(_chunk, _callbacks), do: :ok

  defp maybe_invoke_chunk_callback(_chunk, callback) when not is_function(callback, 1), do: :ok
  defp maybe_invoke_chunk_callback(chunk, callback), do: callback.(chunk)

  defp maybe_invoke_meta_callback(%ReqLLM.StreamChunk{type: :meta} = chunk, callback) when is_function(callback, 1),
    do: callback.(chunk)

  defp maybe_invoke_meta_callback(_chunk, _callback), do: :ok

  defp build_stream_content(text, nil), do: text
  defp build_stream_content(text, ""), do: text

  defp build_stream_content(text, thinking) do
    [
      %{type: :thinking, thinking: thinking},
      %{type: :text, text: text || ""}
    ]
  end

  defp stream_finish_reason(tool_calls, _finish_reason) when is_list(tool_calls) and tool_calls != [], do: :tool_calls
  defp stream_finish_reason(_tool_calls, finish_reason) when not is_nil(finish_reason), do: finish_reason
  defp stream_finish_reason(_tool_calls, _finish_reason), do: :stop

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
