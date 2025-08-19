defmodule JidoWorkbench.Documentation.LivebookParser do
  @moduledoc """
  Custom parser for NimblePublisher that handles frontmatter in a Livebook-compatible way.

  This parser supports two formats:

  1. Standard NimblePublisher format for .md files:
     ```
     %{
       title: "Document Title",
       ...
     }
     ---
     # Content
     ```

  2. Simple HTML comment format for .livemd files:
     ```
     <!-- %{
       title: "Document Title",
       description: "Document description",
       category: :category,
       order: 1,
       tags: [:tag1, :tag2]
     } -->

     # Content
     ```

  The parser will handle both formats and extract the metadata appropriately.
  """

  @doc """
  Parses the content of a file and extracts metadata and body.

  ## Parameters

  - path: The file path
  - contents: The file contents

  ## Returns

  A tuple `{attrs, body}` where:
  - attrs: Map of metadata attributes
  - body: The document body
  """
  def parse(path, contents) do
    if String.ends_with?(path, ".livemd") do
      parse_livebook(contents)
    else
      parse_markdown(contents)
    end
  end

  @doc """
  Parse standard Markdown files with frontmatter.
  """
  def parse_markdown(contents) do
    case :binary.split(contents, ["\n---\n"], [:global]) do
      [attrs, body] ->
        {parse_attrs(attrs), body}

      [body] ->
        # No frontmatter found, return empty attrs
        {%{}, body}
    end
  end

  @doc """
  Parse Livebook files with frontmatter in HTML comments.
  """
  def parse_livebook(contents) do
    # Try to find map in HTML comments at the start of the file
    case Regex.run(~r/\A\s*<!--\s*(%{.*?})\s*-->/s, contents) do
      [full_match, attrs_str] ->
        # Found frontmatter in comments
        attrs = parse_attrs(attrs_str)
        # Remove the frontmatter from the body
        body = String.replace(contents, full_match, "", global: false)
        {attrs, body}

      nil ->
        # No frontmatter found, try standard format as fallback
        case :binary.split(contents, ["\n---\n"], [:global]) do
          [attrs, body] -> {parse_attrs(attrs), body}
          [body] -> {%{}, body}
        end
    end
  end

  @doc """
  Parse Elixir map from string representation.
  """
  def parse_attrs(attrs_str) do
    {attrs, _} = Code.eval_string(attrs_str)
    attrs
  end
end
