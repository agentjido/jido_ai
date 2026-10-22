defmodule Jido.AI.Execution.StateSize do
  @moduledoc false

  @metadata_key :jido_ai_max_state_size

  def metadata_key, do: @metadata_key

  def limit(%{metadata: metadata}) when is_map(metadata), do: Map.get(metadata, @metadata_key)
  def limit(_source), do: nil

  # Zoi reserves MFA functions named :validate for protocol dispatch.
  def check(state, limit, _context) when is_integer(limit) and limit > 0 do
    if :erlang.external_size(state) <= limit,
      do: :ok,
      else: {:error, "Agent state exceeds max_state_size"}
  end

  # Retain the old MFA for stored schemas, using Zoi's protocol argument order.
  def validate(%Zoi.Types.Map{}, state, limit) when is_map(state) and is_integer(limit),
    do: check(state, limit, [])

  def validate(state, limit, context) when is_integer(limit), do: check(state, limit, context)

  def error?(%{message: "Agent state exceeds max_state_size"}), do: true
  def error?(%{details: %{errors: errors}}), do: error?(errors)
  def error?(errors) when is_list(errors), do: Enum.any?(errors, &error?/1)
  def error?(_error), do: false
end
