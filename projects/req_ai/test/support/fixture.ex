defmodule ReqAI.Test.Fixture do
  @moduledoc """
  Test fixture helper for loading JSON response fixtures.
  """

  @fixtures Path.join([__DIR__, "..", "fixtures"])

  @doc """
  Loads and decodes a JSON fixture file for a given provider.

  ## Examples

      iex> ReqAI.Test.Fixture.json!(:anthropic, "success.json")
      %{"content" => [%{"text" => "Hello!"}]}

  """
  @spec json!(atom(), String.t()) :: map()
  def json!(provider, file) when is_atom(provider) and is_binary(file) do
    Path.join([@fixtures, to_string(provider), file])
    |> File.read!()
    |> Jason.decode!()
  end
end
