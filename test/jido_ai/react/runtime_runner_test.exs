defmodule Jido.AI.ReAct.RuntimeRunnerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.ReAct
  alias Jido.AI.ReAct.Config

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

    config = Config.new(%{model: :capable, tools: %{}})

    _first =
      ReAct.stream("cancel me", config)
      |> Enum.take(1)

    Process.sleep(20)
    refute_received {:react_runner, _, :event, _}
  end
end
