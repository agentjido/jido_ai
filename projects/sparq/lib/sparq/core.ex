defmodule Sparq.Core do
  @moduledoc """
  Core execution engine for Sparq.
  Manages program execution flow and context lifecycle.
  """
  alias Sparq.{Context, Error, Evaluator}

  # use ExDbug, enabled: false
  # @decorate_all dbug()

  @doc """
  Executes a Sparq program.

  The program can be:
  - A single expression
  - A list of expressions
  - A block AST node
  - A script AST node

  Returns {:ok, result, context} on success
  or {:error, error, context} on failure.
  """
  @spec execute(term(), keyword()) ::
          {:ok, term(), Context.t()} | {:error, Error.t(), Context.t()}
  def execute(program, opts \\ []) do
    context =
      Context.new(opts)
      |> Context.push_frame(:root)
      |> Context.start_execution()

    try do
      {result, ctx} =
        case program do
          # Script node - use as is
          {:script, _meta, _exprs} = script -> Evaluator.evaluate(script, context)
          # Single block node - wrap in script
          {:block, meta, _body} -> Evaluator.evaluate({:script, meta, [program]}, context)
          # List of expressions - wrap in script
          cmds when is_list(cmds) -> Evaluator.evaluate({:script, [], cmds}, context)
          # Single expression - wrap in script
          expr -> Evaluator.evaluate({:script, [], [expr]}, context)
        end

      # Keep the root frame in the final context
      {:ok, result, Context.end_execution(%{ctx | status: :halted})}
    rescue
      err in Error ->
        {:error, err, Context.end_execution(%{context | status: :error})}

      error ->
        err = Error.from_exception(error)
        {:error, err, Context.end_execution(%{context | status: :error})}
    end
  end

  @doc """
  Helper function to execute a list of arguments.
  """
  @spec execute_args([term()], Context.t()) :: {[term()], Context.t()}
  def execute_args(args, context) do
    Evaluator.evaluate_args(args, context)
  end

  # Initializes a new execution context with root frame
  @spec initialize_context(keyword()) :: Context.t()
  defp initialize_context(opts) do
    Context.new(opts)
    |> Context.push_frame(:root)
    |> Context.start_execution()
  end

  defp handle_error(context, kind, error) do
    Context.add_error(context, Error.from_catch(kind, error))
  end

  defp get_last_error(%Context{event_history: event_history}) do
    event_history
    |> :queue.to_list()
    |> Enum.find(fn
      {:error, _} -> true
      _ -> false
    end)
    |> case do
      {:error, error} -> error
      _ -> nil
    end
  end
end
