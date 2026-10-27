defmodule Jido.AI.ChainOfThoughtLiveTest do
  use ExUnit.Case, async: false

  alias Jido.AITest.ChainOfThoughtAgent
  alias Jido.Agent.Directive.Reply
  alias Jido.AgentServer

  @moduletag :live

  setup_all do
    load_dotenv()

    unless present?(System.get_env("OPENAI_API_KEY")) do
      flunk("OPENAI_API_KEY is required for the Chain of Thought live test")
    end

    :ok
  end

  test "a live model returns at least three numbered steps and one conclusion" do
    owner = self()
    handler_id = "jido-ai-cot-live-#{System.unique_integer([:positive])}"

    events =
      Jido.AI.Telemetry.owned_events() ++
        [
          [:req_llm, :request, :start],
          [:req_llm, :request, :stop],
          [:req_llm, :request, :exception]
        ]

    assert :ok =
             :telemetry.attach_many(
               handler_id,
               events,
               fn event, measurements, metadata, _config ->
                 send(owner, {:telemetry, event, measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    instance = String.to_atom("jido_ai_cot_live_#{System.unique_integer([:positive])}")
    start_supervised!({Jido, name: instance, namespace: Atom.to_string(instance)}, id: instance)

    assert {:ok, server} = Jido.start_agent(instance, ChainOfThoughtAgent, id: "cot-live-agent")
    assert :ok = AgentServer.await_ready(server)

    assert {:ok, _agent, [%Reply{signal: reply}]} =
             AgentServer.call(
               server,
               ChainOfThoughtAgent.request_signal!(%{
                 input:
                   "Use at least three numbered steps. A shop has 12 boxes with 8 markers in each box. It gives away 17 markers. How many markers remain?"
               }),
               60_000
             )

    trace = receive_events([])
    trace_path = write_trace(trace, reply.data)

    assert reply.data.status == :completed
    assert reply.data.model_calls == 1
    assert reply.data.output =~ "79"
    assert reply.data.reasoning.method == :chain_of_thought
    assert reply.data.reasoning.steps_count >= 3
    assert reply.data.reasoning.conclusion =~ "79"

    assert [attempt] = reply.data.model_attempts
    before_context = Jido.AI.Context.Snapshot.decode!(attempt.context.before)
    after_context = Jido.AI.Context.Snapshot.decode!(attempt.context.after)
    assert before_context["stage"] == "prepared"
    assert before_context["shape"]["message_count"] == 2
    assert after_context["stage"] == "completed"
    assert after_context["response"]["call_metadata"]["usage"]["input_tokens"] > 0
    assert after_context["response"]["call_metadata"]["usage"]["output_tokens"] > 0

    reasoning_stops = events_named(trace, [:jido, :ai, :reasoning, :stop])
    request_stops = events_named(trace, [:req_llm, :request, :stop])
    agent_stops = events_named(trace, [:jido, :ai, :agent, :stop])

    assert [{_, reasoning_measurements, reasoning_stop}] = reasoning_stops
    assert [{_, _, request_stop}] = request_stops
    assert [{_, agent_measurements, agent_stop}] = agent_stops

    assert reasoning_stop.reasoning_method == :chain_of_thought
    assert reasoning_stop.status == :ok
    assert after_context["response"]["call_metadata"]["request_id"] == request_stop.request_id
    assert reasoning_measurements.duration > 0
    assert agent_stop.status == :completed
    assert agent_measurements.model_calls == 1
    assert agent_measurements.reasoning_steps == reply.data.reasoning.steps_count
    assert File.exists?(trace_path)

    trace_text = File.read!(trace_path)
    refute trace_text =~ "12 boxes"
    refute trace_text =~ "markers remain"

    IO.puts("\nChain of Thought live result: #{reply.data.output}")
    IO.puts("Model-produced reasoning steps: #{reply.data.reasoning.steps_count}")
    IO.puts("Sanitized trace: #{trace_path}")
  end

  defp load_dotenv do
    if File.exists?(".env") do
      with {:ok, values} <- Dotenvy.source(".env") do
        Enum.each(values, fn {key, value} -> System.put_env(key, value) end)
      end
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp receive_events(events) do
    receive do
      {:telemetry, event, measurements, metadata} ->
        receive_events([{event, measurements, metadata} | events])
    after
      100 -> Enum.reverse(events)
    end
  end

  defp events_named(events, name), do: Enum.filter(events, &(elem(&1, 0) == name))

  defp write_trace(events, result) do
    path = Path.expand("tmp/jido_ai_traces/chain_of_thought_live.json")
    File.mkdir_p!(Path.dirname(path))

    document = %{
      algorithm: "chain_of_thought",
      result: %{
        status: result.status,
        model_calls: result.model_calls,
        reasoning_steps: result.reasoning.steps_count,
        retries: result.retries,
        input_tokens: result.usage.input_tokens,
        output_tokens: result.usage.output_tokens,
        cache_read_tokens: result.usage.cache_read_tokens,
        cache_write_tokens: result.usage.cache_write_tokens
      },
      events: Enum.map(events, &sanitize_event/1)
    }

    File.write!(path, Jason.encode!(document, pretty: true))
    path
  end

  defp sanitize_event({event, measurements, metadata}) do
    %{
      event: Enum.join(event, "."),
      measurements: safe_measurements(measurements),
      metadata: safe_metadata(metadata)
    }
  end

  defp safe_measurements(measurements) do
    measurements
    |> Map.take([
      :duration,
      :model_calls,
      :tool_calls,
      :retries,
      :reasoning_steps,
      :input_tokens,
      :output_tokens,
      :cache_read_tokens,
      :cache_write_tokens,
      :reasoning_tokens,
      :total_cost
    ])
    |> Map.new(fn
      {:duration, duration} ->
        {:duration_ms, System.convert_time_unit(duration, :native, :microsecond) / 1_000}

      field ->
        field
    end)
  end

  defp safe_metadata(metadata) do
    metadata
    |> Map.put_new(:conversation_id, conversation_id(metadata))
    |> Map.take([
      :agent_id,
      :agent_name,
      :conversation_id,
      :finish_reason,
      :http_status,
      :model,
      :operation,
      :provider,
      :reasoning_method,
      :reasoning_name,
      :req_llm_request_id,
      :request_id,
      :run_id,
      :status,
      :thread_id,
      :turn_id
    ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {key, portable(value)} end)
  end

  defp conversation_id(metadata) do
    metadata[:conversation_id] || get_in(metadata, [:request_options, :conversation_id])
  end

  defp portable(%LLMDB.Model{id: id}) when is_binary(id), do: id
  defp portable(value) when is_atom(value), do: Atom.to_string(value)
  defp portable(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp portable(value), do: inspect(value, limit: 3, printable_limit: 100)
end
