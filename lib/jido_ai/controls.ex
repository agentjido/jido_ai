defmodule Jido.AI.Controls do
  @moduledoc """
  Runs AI input and output controls as Jido Actions.

  Input Actions receive `%{input: value}`. Output Actions receive
  `%{output: value}`. The request `:jido_context` becomes the Jido execution
  context. A successful Action permits work. An Action error stops it.

  Control Actions must not return effects. This request layer has no effect
  dispatcher.
  """

  @type stage :: :input | :output

  @doc false
  @spec run([module()], stage(), term(), map(), keyword()) :: :ok | {:error, term()}
  def run(actions, stage, value, context, opts \\ [])

  def run(actions, stage, value, context, opts)
      when is_list(actions) and stage in [:input, :output] and is_map(context) and
             is_list(opts) do
    params = %{stage => value}
    execute(actions, params, context, opts)
  end

  def run(_actions, _stage, _value, _context, _opts),
    do: {:error, :invalid_control_configuration}

  defp execute(actions, params, context, opts) do
    Enum.reduce_while(actions, :ok, fn action, :ok ->
      case Jido.Exec.run(action, params, context, opts) do
        {:ok, _result} ->
          {:cont, :ok}

        {:ok, _result, []} ->
          {:cont, :ok}

        {:ok, _result, effects} ->
          {:halt, {:error, {:control_effects_not_supported, action, effects}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
end
