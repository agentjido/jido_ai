defmodule Jido.AI.Error.ObjectGeneration do
  @moduledoc """
  Error for general object generation failures during structured data generation.

  This error is raised when the AI provider fails to generate valid structured objects,
  such as when the response cannot be parsed or decoded into the expected format.
  """

  use Splode.Error,
    fields: [:text, :response, :usage, :cause],
    class: :invalid

  @type t :: %__MODULE__{
          text: String.t() | nil,
          response: map() | nil,
          usage: map() | nil,
          cause: term() | nil
        }

  @spec message(map()) :: String.t()
  def message(%{text: text, cause: cause}) when not is_nil(cause) do
    "Object generation failed: #{inspect(cause)}#{format_text_preview(text)}"
  end

  def message(%{text: text}) do
    "Object generation failed: unable to parse generated content#{format_text_preview(text)}"
  end

  defp format_text_preview(nil), do: ""
  defp format_text_preview(""), do: ""

  defp format_text_preview(text) when is_binary(text) do
    preview = text |> String.trim() |> String.slice(0, 100)
    " (preview: \"#{preview}#{if String.length(text) > 100, do: "...", else: ""}\")"
  end

  defp format_text_preview(_), do: ""
end
