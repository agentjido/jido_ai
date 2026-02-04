defmodule Jido.AI.Text do
  @moduledoc """
  Centralized text extraction utilities for LLM responses.

  This module provides consistent text extraction from various response shapes
  returned by LLM providers (via ReqLLM).

  ## Supported Response Shapes

  - Binary strings (passed through)
  - Lists of content blocks (text blocks extracted and joined)
  - Maps with `message.content` (standard ReqLLM response)
  - Maps with `choices[0].message.content` (OpenAI-style response)
  - iodata/charlists (converted to string)

  ## Examples

      # From ReqLLM response
      iex> extract_text(%{message: %{content: "Hello"}})
      "Hello"

      # From content with text blocks (multiple blocks joined with newlines)
      iex> extract_text(%{message: %{content: [%{type: :text, text: "Hi"}, %{type: :text, text: "there"}]}})
      "Hi\\nthere"

      # From raw content
      iex> extract_text("direct string")
      "direct string"

      # From OpenAI-style response
      iex> extract_text(%{choices: [%{message: %{content: "Hello"}}]})
      "Hello"
  """

  @doc """
  Extracts text content from an LLM response or content value.

  Handles multiple response shapes consistently:
  - Binary strings pass through unchanged
  - Lists of content blocks have text blocks extracted and joined
  - Response maps with `message.content` are unwrapped
  - OpenAI-style responses with `choices[0].message.content` are unwrapped
  - iodata is converted to string
  - All other values return empty string

  ## Parameters

  - `response` - An LLM response map, content value, or any term

  ## Returns

  The extracted text as a string, or empty string if no text found.

  ## Examples

      iex> Jido.AI.Text.extract_text(%{message: %{content: "Hello world"}})
      "Hello world"

      iex> Jido.AI.Text.extract_text(%{message: %{content: [%{type: :text, text: "Part 1"}, %{type: :text, text: "Part 2"}]}})
      "Part 1\\nPart 2"

      iex> Jido.AI.Text.extract_text("already a string")
      "already a string"

      iex> Jido.AI.Text.extract_text(nil)
      ""
  """
  @spec extract_text(term()) :: String.t()

  # Binary strings pass through
  def extract_text(content) when is_binary(content), do: content

  # Nil returns empty string
  def extract_text(nil), do: ""

  # Standard ReqLLM response shape: %{message: %{content: ...}}
  def extract_text(%{message: %{content: content}}) do
    extract_from_content(content)
  end

  # OpenAI-style response shape: %{choices: [%{message: %{content: ...}}]}
  def extract_text(%{choices: [%{message: %{content: content}} | _]}) do
    extract_from_content(content)
  end

  # Fallback for any other map - try common paths
  def extract_text(%{} = map) do
    cond do
      # Try message.content path
      content = get_in(map, [:message, :content]) ->
        extract_from_content(content)

      # Try choices[0].message.content path
      content = get_in(map, [:choices, Access.at(0), :message, :content]) ->
        extract_from_content(content)

      # Try content key directly
      content = Map.get(map, :content) ->
        extract_from_content(content)

      true ->
        ""
    end
  end

  # iodata/charlist
  def extract_text(content) when is_list(content) do
    if iodata?(content) do
      IO.iodata_to_binary(content)
    else
      extract_from_content(content)
    end
  end

  # Catch-all
  def extract_text(_), do: ""

  @doc """
  Extracts text from a content value (not wrapped in response structure).

  This is a lower-level function that handles the content itself,
  not the full response wrapper.

  ## Parameters

  - `content` - Content value (binary, list of blocks, or nil)

  ## Returns

  The extracted text as a string.

  ## Examples

      iex> Jido.AI.Text.extract_from_content("hello")
      "hello"

      iex> Jido.AI.Text.extract_from_content([%{type: :text, text: "hello"}])
      "hello"
  """
  @spec extract_from_content(term()) :: String.t()
  def extract_from_content(nil), do: ""
  def extract_from_content(content) when is_binary(content), do: content

  def extract_from_content(content) when is_list(content) do
    if iodata?(content) do
      IO.iodata_to_binary(content)
    else
      content
      |> Enum.filter(&text_block?/1)
      |> Enum.map_join("\n", fn
        %{text: text} when is_binary(text) -> text
        _ -> ""
      end)
    end
  end

  def extract_from_content(_), do: ""

  # Checks if a content block is a text block
  defp text_block?(%{type: :text}), do: true
  defp text_block?(%{type: "text"}), do: true
  defp text_block?(_), do: false

  # Check for iodata - must contain at least one binary or be a printable charlist
  # This avoids false positives where a list of integers (e.g., token IDs) gets
  # converted to garbage binary
  defp iodata?(list), do: has_binary?(list) or printable_charlist?(list)

  defp has_binary?([]), do: false
  defp has_binary?([head | _tail]) when is_binary(head), do: true
  defp has_binary?([head | tail]) when is_list(head), do: has_binary?(head) or has_binary?(tail)
  defp has_binary?([_ | tail]), do: has_binary?(tail)

  # Only treat as charlist if it's printable (ASCII 32-126, tab, newline, etc.)
  defp printable_charlist?(list) when is_list(list), do: :io_lib.printable_list(list)
  defp printable_charlist?(_), do: false
end
