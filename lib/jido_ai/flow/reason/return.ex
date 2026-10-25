defmodule Jido.AI.Flow.Reason.Return do
  @moduledoc false

  alias Jido.AI.{Event, Result}
  alias Jido.AI.Reasoning.State

  use Jido.Action,
    name: "jido_ai_reason_return",
    description: "Return one validated AI reasoning result"

  @impl Jido.Action
  def run(%{result: %Result{status: :completed} = result}, _context),
    do: validated(result)

  def run(
        %{
          request: %{__jido_ai_reasoning__: true} = request,
          result: %{output: output, usage: usage, trace: trace}
        },
        _context
      )
      when is_map(usage) and is_list(trace) do
    events = custom_events(request, output, usage, trace)

    request
    |> Result.completed(output, usage, events)
    |> validated()
  end

  def run(%{result: result}, _context), do: {:error, {:invalid_reasoning_result, result}}

  defp custom_events(request, output, usage, trace) do
    started = Enum.reverse(request.trace)

    custom =
      trace
      |> Enum.reject(&match?(%{type: type} when type in [:request_started, :request_completed], &1))
      |> Enum.with_index(length(started) + 1)
      |> Enum.map(fn {event, sequence} -> custom_event(request, event, sequence) end)

    sequence = length(started) + length(custom) + 1

    completed =
      Event.new(request, :request_completed, %{output: State.summarize(output), usage: usage},
        sequence: sequence,
        elapsed_ms: elapsed_ms(request),
        iteration: request.iterations
      )

    started ++ custom ++ [completed]
  end

  defp custom_event(request, %{type: type} = event, sequence) when is_atom(type) do
    data = Map.get(event, :data, Map.drop(event, [:type, :sequence, :elapsed_ms, :iteration]))

    Event.new(request, type, data,
      sequence: sequence,
      elapsed_ms: Map.get(event, :elapsed_ms, elapsed_ms(request)),
      iteration: Map.get(event, :iteration, request.iterations)
    )
  end

  defp custom_event(request, event, sequence) do
    Event.new(request, :reasoning_event, %{event: State.summarize(event)},
      sequence: sequence,
      elapsed_ms: elapsed_ms(request),
      iteration: request.iterations
    )
  end

  defp elapsed_ms(request) do
    case List.first(request.trace) do
      %{elapsed_ms: elapsed_ms} -> elapsed_ms + State.since_last_event_ms(request)
      _event -> 0
    end
  end

  defp validated(result) do
    case Result.validate(result) do
      :ok -> {:ok, Map.from_struct(result)}
      {:error, reason} -> {:error, {:invalid_reasoning_result, reason}}
    end
  end
end
