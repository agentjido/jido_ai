defmodule Jido.AI.Actions.Planning.Request do
  @moduledoc false
  @defaults %{
    model: [:default_model, :model],
    max_tokens: [:default_max_tokens],
    temperature: [:default_temperature],
    max_steps: [:default_max_steps]
  }

  def before_validate(schema, params), do: Jido.AI.ActionInput.before_validate(schema, params)

  def prepare(schema, params, context) when is_map(params) do
    context = Jido.AI.ActionInput.context(context)
    params = Jido.AI.ActionInput.apply_defaults(schema, params, context, @defaults, [:planning])

    with {:ok, params} <- Zoi.parse(schema, params),
         model = Jido.AI.Models.resolve(params[:model] || :planning),
         {:ok, options} <- options(params, context) do
      {:ok, params, model, options}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  def prepare(_, _, _), do: {:error, :invalid_planning_parameters}

  defp options(params, context), do: Jido.AI.ActionInput.options(params, context)
end
