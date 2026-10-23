defmodule Jido.AI.Test.LiveCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  alias Jido.AI.Test.LiveTrace

  @default_options [max_tokens: 32, temperature: 0.0, receive_timeout: 30_000]

  using do
    quote do
      @moduletag :live
      @moduletag timeout: 60_000

      import Jido.AI.Test.LiveCase,
        only: [capture_live: 4, capture_live: 5, live_options: 0, live_options: 1]
    end
  end

  @doc false
  def live_options, do: @default_options

  @doc false
  def live_options(overrides), do: Keyword.merge(@default_options, overrides)

  @doc false
  def capture_live(agent, input, scenario, fun),
    do: capture_live(agent, input, scenario, @default_options, fun)

  @doc false
  def capture_live(agent, input, scenario, options, fun) do
    config = Jido.AI.Plugin.config(agent)
    {:ok, model} = Jido.AI.Models.resolve(config.model)

    request = %{
      scenario: scenario,
      model: model,
      instructions: config.instructions,
      input: input,
      options: options
    }

    {result, trace_path} = LiveTrace.capture(request, fun)
    IO.puts("Live trace: #{trace_path}")

    assert File.exists?(trace_path)

    trace = trace_path |> File.read!() |> Jason.decode!()

    assert trace["scenario"] == scenario
    assert trace["status"] == "ok"

    assert_trace_shape(trace)

    {result, trace_path}
  end

  defp assert_trace_shape(%{"schema_version" => 2, "events" => events} = trace) do
    assert is_list(events)
    assert List.first(events)["type"] == "request_started"
    assert List.last(events)["type"] == "request_completed"
    assert is_map(trace["result"]["usage"])
    assert is_list(trace["runtime_events"])
  end

  defp assert_trace_shape(%{"events" => events, "runtime_events" => runtime_events}) do
    assert Enum.map(events, & &1["type"]) == [
             "ai.request.started",
             "ai.response.completed"
           ]

    assert is_list(runtime_events)
  end
end
