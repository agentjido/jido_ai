defmodule Jido.AI.Flow.Reason.Compose do
  @moduledoc false

  alias Jido.AI.Flow.Reason.Pipeline

  use Jido.Action,
    name: "jido_ai_reason_compose",
    description: "Compose the configured AI reasoning pipeline"

  @impl Jido.Action
  def run(%{__jido_ai_reasoning__: true} = state, _context) do
    case Pipeline.new(state) do
      {:ok, flow} -> {:continue, %{request: state}, flow}
      {:error, error} -> {:error, error}
    end
  end
end
