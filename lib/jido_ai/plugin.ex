defmodule Jido.AI.Plugin do
  @moduledoc """
  Adds the first AI response configuration to a Jido Agent.

  The Plugin only describes the response. It does not call a model or start a
  process.

      defmodule MyApp.Assistant do
        use Jido.Agent, name: "assistant", extensions: [Jido.AI.Plugin]

        ai do
          model "openai:gpt-4o-mini"
          instructions "Reply in one short sentence."
        end
      end
  """

  alias Jido.Agent.Data
  alias Spark.Dsl.Extension, as: Extension

  @section %Spark.Dsl.Section{
    name: :ai,
    schema: [
      model: [type: :string, required: true],
      instructions: [type: :string, default: ""]
    ]
  }

  use Jido.Plugin, id: "jido.ai", sections: [@section]

  @impl Jido.Plugin
  def state_spec(_opts), do: :none

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    model = Extension.get_opt(dsl, [:ai], :model)
    instructions = Extension.get_opt(dsl, [:ai], :instructions, "")

    cond do
      model != nil and config != %{} ->
        {:error, :use_ai_block_or_config}

      config != %{} ->
        {:ok, config}

      model != nil ->
        {:ok, %{response: %{model: model, instructions: instructions}}}

      true ->
        {:error, :missing_ai_response}
    end
  end

  @impl Jido.Agent.Extension
  def normalize(data) do
    with {:ok, data} <- Data.fields(data, [:response]),
         {:ok, response} <-
           Data.fields(data[:response], [:model, :instructions], %{instructions: ""}),
         :ok <- Data.nonempty(response.model),
         :ok <- validate_instructions(response.instructions) do
      {:ok, %{response: response}}
    end
  end

  @doc "Returns the Agent's static AI response configuration."
  @spec response(module() | Jido.Agent.t()) :: map() | nil
  def response(agent) when is_atom(agent), do: response(agent.definition())

  def response(%Jido.Agent{extensions: extensions}) do
    case Enum.find(extensions, &(&1.provider == __MODULE__)) do
      %{data: %{response: response}} -> response
      nil -> nil
    end
  end

  defp validate_instructions(""), do: :ok
  defp validate_instructions(value), do: Data.nonempty(value)
end
