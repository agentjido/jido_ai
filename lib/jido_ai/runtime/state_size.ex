defmodule Jido.AI.Runtime.StateSize do
  @moduledoc false

  @metadata_key :jido_ai_max_state_size

  def metadata_key, do: @metadata_key

  def limit(%{metadata: metadata}) when is_map(metadata), do: Map.get(metadata, @metadata_key)
  def limit(_source), do: nil

  def validate(state, limit, _context) do
    if :erlang.external_size(state) <= limit,
      do: :ok,
      else: {:error, "Agent state exceeds max_state_size"}
  end

  def error?(%{message: "Agent state exceeds max_state_size"}), do: true
  def error?(%{details: %{errors: errors}}), do: error?(errors)
  def error?(errors) when is_list(errors), do: Enum.any?(errors, &error?/1)
  def error?(_error), do: false
end
