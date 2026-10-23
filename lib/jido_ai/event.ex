defmodule Jido.AI.Event do
  @moduledoc """
  One ordered, portable event from an AI request.

  All event consumers use this value. A trace, stream, Signal projection, or
  telemetry handler can select the event data that it needs without defining a
  second event order.
  """

  @terminal_types [:request_completed, :request_failed, :request_cancelled]

  @type type ::
          :request_started
          | :model_completed
          | :tool_round_completed
          | :request_completed
          | :request_failed
          | :request_cancelled
          | atom()

  @type t :: %{
          required(:request_id) => String.t(),
          required(:run_id) => String.t(),
          required(:sequence) => pos_integer(),
          required(:type) => type(),
          required(:elapsed_ms) => non_neg_integer(),
          required(:iteration) => non_neg_integer() | nil,
          required(:data) => map()
        }

  @doc false
  @spec new(map(), type(), map(), keyword()) :: t()
  def new(request, type, data, opts \\ [])
      when is_map(request) and is_atom(type) and is_map(data) and is_list(opts) do
    %{
      request_id: Map.fetch!(request, :request_id),
      run_id: Map.fetch!(request, :run_id),
      sequence: Keyword.fetch!(opts, :sequence),
      type: type,
      elapsed_ms: Keyword.get(opts, :elapsed_ms, 0),
      iteration: Keyword.get(opts, :iteration),
      data: data
    }
  end

  @doc "Returns true for a terminal request event."
  @spec terminal?(t()) :: boolean()
  def terminal?(%{type: type}), do: type in @terminal_types

  @doc "Validates the canonical event shape."
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(%{
        request_id: request_id,
        run_id: run_id,
        sequence: sequence,
        type: type,
        elapsed_ms: elapsed_ms,
        iteration: iteration,
        data: data
      })
      when is_binary(request_id) and byte_size(request_id) > 0 and is_binary(run_id) and
             byte_size(run_id) > 0 and is_integer(sequence) and sequence > 0 and is_atom(type) and
             type not in [nil, true, false] and is_integer(elapsed_ms) and elapsed_ms >= 0 and
             (is_nil(iteration) or (is_integer(iteration) and iteration >= 0)) and is_map(data) and
             not is_struct(data),
      do: :ok

  def validate(_event), do: {:error, :invalid_ai_event}
end
