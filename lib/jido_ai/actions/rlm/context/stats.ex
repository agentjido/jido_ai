defmodule Jido.AI.Actions.RLM.Context.Stats do
  @moduledoc """
  Get size and structure information about the loaded context.

  Returns the total byte size, estimated line count, and a sample of the
  first bytes of the context for quick inspection.

  ## Parameters

  No parameters required.

  ## Returns

      %{
        size_bytes: 125_000,
        approx_lines: 2500,
        sample: "Line 1: The quick brown fox\\nLine 2: ..."
      }
  """

  use Jido.Action,
    name: "context_stats",
    description: "Get size and structure information about the loaded context",
    category: "rlm",
    tags: ["rlm", "context", "exploration"],
    vsn: "1.0.0",
    schema: Zoi.object(%{})

  alias Jido.AI.RLM.ContextStore

  @sample_bytes 500

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
  def run(_params, context) do
    ref = context.context_ref
    size = ContextStore.size(ref)
    sample_length = min(@sample_bytes, size)

    with {:ok, sample} <- ContextStore.fetch_range(ref, 0, sample_length) do
      approx_lines = estimate_lines(size, sample)
      {:ok, %{size_bytes: size, approx_lines: approx_lines, sample: sample}}
    end
  end

  defp estimate_lines(0, _sample), do: 0

  defp estimate_lines(total_bytes, sample) do
    sample_size = byte_size(sample)

    if sample_size == 0 do
      0
    else
      newlines_in_sample = sample |> String.graphemes() |> Enum.count(&(&1 == "\n"))
      lines_per_byte = (newlines_in_sample + 1) / sample_size
      round(lines_per_byte * total_bytes)
    end
  end
end
