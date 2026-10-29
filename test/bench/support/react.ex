defmodule JidoAI.Bench.ReAct do
  @moduledoc false

  @spec rounds!([String.t()], [pos_integer()], keyword()) :: [pos_integer()]
  def rounds!(arguments, defaults, opts \\ []) do
    rounds = if arguments == [], do: defaults, else: Enum.map(arguments, &parse_round!/1)

    if Keyword.get(opts, :one, false) and length(rounds) != 1 do
      raise ArgumentError, "pass exactly one round count"
    end

    rounds
  end

  defp parse_round!(value) do
    case Integer.parse(value) do
      {rounds, ""} when rounds in 1..20 -> rounds
      _other -> raise ArgumentError, "round count must be an integer from 1 through 20"
    end
  end
end
