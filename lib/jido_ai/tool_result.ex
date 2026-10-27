defmodule Jido.AI.ToolResult do
  @moduledoc "Separates a local Action result from bounded model-visible content."

  @default_max_bytes 16_384

  @doc "Normalizes one local Action outcome without putting its value in model context."
  @spec normalize(map(), pos_integer()) :: map()
  def normalize(outcome, max_bytes \\ @default_max_bytes)

  def normalize(%{status: :ok, value: value}, max_bytes)
      when is_integer(max_bytes) and max_bytes > 0 do
    {model_content, metadata} = project(value, max_bytes)

    %{
      status: :ok,
      value: value,
      model_content: model_content,
      error: nil,
      metadata: metadata
    }
  end

  def normalize(%{status: :error, error: error}, max_bytes)
      when is_integer(max_bytes) and max_bytes > 0 do
    safe_error = %{
      "status" => "error",
      "error" => %{
        "type" => safe_type(field(error, :type)),
        "message" => safe_message(field(error, :message)),
        "retryable" => field(error, :retryable?) == true
      }
    }

    {model_content, metadata} = project(safe_error, max_bytes)

    %{
      status: :error,
      value: nil,
      model_content: model_content,
      error: safe_error["error"],
      metadata: metadata
    }
  end

  def normalize(_outcome, max_bytes) when is_integer(max_bytes) and max_bytes > 0 do
    normalize(
      %{
        status: :error,
        error: %{type: :invalid_tool_result, message: "tool action returned an invalid result"}
      },
      max_bytes
    )
  end

  @doc "Returns JSON-safe model content and size metadata."
  @spec project(term(), pos_integer()) :: {term(), map()}
  def project(value, max_bytes \\ @default_max_bytes)

  def project(value, max_bytes) when is_integer(max_bytes) and max_bytes > 0 do
    case Jason.encode(value) do
      {:ok, encoded} when byte_size(encoded) <= max_bytes ->
        {Jason.decode!(encoded), %{bytes: byte_size(encoded), max_bytes: max_bytes, truncated: false}}

      {:ok, encoded} ->
        content = %{
          "status" => "truncated",
          "message" => "tool result exceeded the model-content limit",
          "original_bytes" => byte_size(encoded),
          "max_bytes" => max_bytes
        }

        {content, %{bytes: byte_size(encoded), max_bytes: max_bytes, truncated: true}}

      {:error, _reason} ->
        content = %{
          "status" => "error",
          "error" => %{
            "type" => "invalid_tool_result",
            "message" => "tool result is not JSON-compatible",
            "retryable" => false
          }
        }

        {content, %{bytes: nil, max_bytes: max_bytes, truncated: false}}
    end
  end

  defp safe_type(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_type(value) when is_binary(value) and value != "", do: truncate(value, 128)
  defp safe_type(_value), do: "tool_error"

  defp safe_message(value) when is_binary(value) and value != "", do: truncate(value, 1_024)
  defp safe_message(_value), do: "tool action failed"

  defp truncate(value, max_bytes) when byte_size(value) <= max_bytes, do: value

  defp truncate(value, max_bytes) do
    value
    |> String.codepoints()
    |> Enum.reduce_while("", fn codepoint, output ->
      if byte_size(output) + byte_size(codepoint) > max_bytes,
        do: {:halt, output},
        else: {:cont, output <> codepoint}
    end)
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_value, _key), do: nil
end
