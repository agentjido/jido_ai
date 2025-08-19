defmodule Sparq.Evaluator.Bind do
  alias Sparq.{Context, Error}
  alias Sparq.Evaluator.{PatternMatch, VariableBinding}

  @type bind_result :: {term(), Context.t()} | {:error, Error.t(), Context.t()}

  @doc """
  Handles variable binding with pattern matching.
  Returns {value, context} or {:error, error, context}.
  """
  @spec handle_bind(term(), term(), atom(), Context.t()) :: bind_result()
  def handle_bind(pattern, value, declaration_type, context) do
    try do
      case Sparq.Evaluator.evaluate(value, context) do
        {resolved_value, new_ctx} ->
          new_ctx =
            Context.add_trace(new_ctx, {:debug, "Pattern matching", {pattern, resolved_value}})

          cond do
            is_atom(pattern) ->
              VariableBinding.handle_variable_binding(
                new_ctx,
                pattern,
                resolved_value,
                declaration_type
              )

            true ->
              try do
                case PatternMatch.match(pattern, resolved_value) do
                  {:ok, bindings} ->
                    new_ctx = Context.add_trace(new_ctx, {:debug, "Bindings", bindings})

                    case PatternMatch.apply_bindings(new_ctx, bindings, declaration_type) do
                      {:ok, value, ctx} -> {value, ctx}
                      {:error, err, ctx} -> {:error, err, ctx}
                    end
                end
              rescue
                e in Error ->
                  new_ctx = Context.add_trace(new_ctx, {:debug, "Pattern match error", e})
                  {:error, e, new_ctx}
              end
          end

        error ->
          error
      end
    rescue
      e -> {:error, e, context}
    catch
      e -> {:error, e, context}
    end
  end
end
