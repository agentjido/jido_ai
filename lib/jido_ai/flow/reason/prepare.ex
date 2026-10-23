defmodule Jido.AI.Flow.Reason.Prepare do
  @moduledoc false

  alias Jido.AI.{Plugin, Request}

  use Jido.Action,
    name: "jido_ai_reason_prepare",
    description: "Prepare one AI reasoning request"

  @impl Jido.Action
  def run(%{prepared: %Request{} = request}, _context), do: {:ok, Request.start(request)}

  def run(params, context) when is_map(params) and is_map(context) do
    with {:ok, input} <- fetch_input(params),
         {:ok, config} <- prepared_config(context),
         {:ok, runtime} <- runtime(params, context),
         {:ok, request} <- Request.prepare(config, input, runtime, Map.get(params, :reply)) do
      {:ok, Request.start(request)}
    end
  end

  def run(params, _context), do: {:error, {:invalid_reasoning_input, params}}

  defp fetch_input(%{input: input}) when is_binary(input) and byte_size(input) > 0,
    do: {:ok, input}

  defp fetch_input(%{input: ""}), do: {:error, :empty_input}
  defp fetch_input(%{input: input}), do: {:error, {:invalid_input, input}}
  defp fetch_input(params), do: {:error, {:invalid_reasoning_input, params}}

  defp prepared_config(context) do
    case get_in(context, [:plugin_inputs, Plugin]) do
      %Jido.Plugin.Input{prepared: config} when is_map(config) -> {:ok, config}
      _other -> {:error, :missing_ai_config}
    end
  end

  defp runtime(params, context) do
    request_options = Map.get(params, :request_options, [])

    if is_list(request_options) and Keyword.keyword?(request_options) do
      opts =
        request_options
        |> Keyword.put(:conversation, Map.get(params, :conversation))
        |> Keyword.put(:jido_context, context)

      Request.options(opts)
    else
      {:error, {:invalid_options, request_options}}
    end
  end
end
