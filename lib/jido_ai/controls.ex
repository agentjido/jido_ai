defmodule Jido.AI.Controls do
  @moduledoc """
  Runs one AI input or output control as a Jido Action.

  Input Actions receive `%{input: value}`. Output Actions receive
  `%{output: value}`. The request `:jido_context` becomes the Jido execution
  context. A successful Action permits work. An Action error stops it.

  Control Actions must not return effects. This request layer has no effect
  dispatcher.
  """

  @type stage :: :input | :output

  @doc false
  @spec run(module() | nil, stage(), term(), map(), keyword()) :: :ok | {:error, term()}
  def run(action, stage, value, context, opts \\ [])

  def run(nil, stage, _value, context, opts)
      when stage in [:input, :output] and is_map(context) and is_list(opts),
      do: :ok

  def run(action, stage, value, context, opts)
      when is_atom(action) and action not in [nil, true, false] and
             stage in [:input, :output] and is_map(context) and is_list(opts) do
    params = %{stage => value}
    execute(action, params, context, opts)
  end

  def run(_action, _stage, _value, _context, _opts),
    do: {:error, :invalid_control_configuration}

  defp execute(action, params, context, opts) do
    case Jido.Exec.run(action, params, context, opts) do
      {:ok, _result} ->
        :ok

      {:ok, _result, []} ->
        :ok

      {:ok, _result, effects} ->
        {:error, {:control_effects_not_supported, action, effects}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
