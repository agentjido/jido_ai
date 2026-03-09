defmodule Jido.AI.PromptBuilder do
  @moduledoc """
  Builds enriched user prompts with XML-tagged context sections.

  Context engineering best practice: place retrieved context (memory, facts,
  errors) in the **user message** rather than the system prompt. This keeps the
  system prompt stable across turns, maximizing KV-cache hit rates with providers
  that support prompt caching (e.g., Anthropic's prompt caching).

  Each context section is wrapped in an XML tag and placed before the user
  message so the LLM treats it as retrieved context, not user input.

  ## Usage

      alias Jido.AI.PromptBuilder

      prompt = PromptBuilder.build("What meetings do I have today?", [
        {:memory_context, memory_block},
        {:known_facts, facts_string},
        {:previous_errors, error_string}
      ])

  Sections with `nil` or empty string values are automatically skipped.

  ## Custom Tags

  You can use any atom as a tag name:

      PromptBuilder.build("Hello", [
        {:retrieved_documents, docs_text},
        {:user_preferences, prefs_text}
      ])

  This produces:

      <retrieved_documents>
      ...docs...
      </retrieved_documents>

      <user_preferences>
      ...prefs...
      </user_preferences>

      Hello
  """

  @doc """
  Builds an enriched prompt by prepending XML-tagged context sections to the message.

  ## Parameters

    * `message` — the user's message (string). Non-string messages are returned as-is.
    * `sections` — a list of `{tag_name, content}` tuples. `nil` or empty content is skipped.

  ## Returns

  The enriched prompt string, or the original message if no sections have content.
  """
  @spec build(term(), [{atom(), String.t() | nil}]) :: term()
  def build(message, []), do: message

  def build(message, sections) when is_binary(message) and is_list(sections) do
    context_blocks =
      sections
      |> Enum.reject(fn {_tag, content} -> blank?(content) end)
      |> Enum.map(fn {tag, content} -> wrap_xml(tag, content) end)

    case context_blocks do
      [] -> message
      blocks -> Enum.join(blocks ++ [message], "\n\n")
    end
  end

  def build(message, _sections), do: message

  @doc """
  Wraps content in an XML tag.

  ## Examples

      iex> Jido.AI.PromptBuilder.wrap_xml(:memory_context, "some memories")
      "<memory_context>\\nsome memories\\n</memory_context>"
  """
  @spec wrap_xml(atom(), String.t()) :: String.t()
  def wrap_xml(tag, content) when is_atom(tag) and is_binary(content) do
    tag_str = Atom.to_string(tag)
    "<#{tag_str}>\n#{content}\n</#{tag_str}>"
  end

  @spec blank?(term()) :: boolean()
  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: true
end
