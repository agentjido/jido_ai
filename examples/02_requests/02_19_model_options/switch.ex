defmodule JidoAI.Examples.ModelOptions.Switch do
  @moduledoc "Selects Anthropic for the second call, then restores the configured default."
  def transform_request(_request, state, _config, context) do
    if state.iteration == 2 do
      {:ok, %{model: "anthropic:claude-sonnet-4-5", llm_opts: context.anthropic_options}}
    else
      {:ok, %{}}
    end
  end
end
