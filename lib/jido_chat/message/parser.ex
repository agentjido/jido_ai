defmodule Jido.Chat.Message.Parser do
  @moduledoc """
  Parser for chat messages using NimbleParsec.

  This module provides functionality to parse special syntax in chat messages,
  particularly focusing on @mentions. It uses NimbleParsec for efficient and
  reliable parsing of message content.

  ## Features

  * Parsing @mentions in messages (e.g., "@alice hello")
  * Tracking mention positions for highlighting
  * Support for complex message content with mixed text and mentions
  * Efficient parsing with NimbleParsec

  ## Examples

  ```elixir
  content = "Hello @alice and @bob!"
  participants = %{
    "user1" => "alice",
    "user2" => "bob"
  }

  {:ok, mentions} = Parser.parse_mentions(content, participants)
  # Returns list of Mention structs with position information
  ```

  ## Mention Format

  Mentions must follow these rules:
  * Start with @ symbol
  * Followed by alphanumeric characters or underscores
  * Match a participant's display name (case insensitive)

  ## Implementation Details

  The parser uses NimbleParsec combinators to build an efficient parser:

  ### Parsers
  * `mention_name_parser` - Parses @mentions in the format @name
  * `content_parser` - Parses the entire message content, handling @mentions, whitespace, and text

  ### Helper Functions
  * `create_mentions/2` - Creates mention structs from parsed tokens
  * `create_mention/2` - Creates a single mention struct if the name matches a participant
  * `find_participant/2` - Matches mention names to participants (case insensitive)
  * `track_offset/5` - NimbleParsec callback to track mention positions
  """

  import NimbleParsec

  defmodule Mention do
    @moduledoc """
    Represents a mention of a participant in a message.

    Contains information about:
    * The mentioned participant's ID
    * The display name used in the mention
    * The position and length of the mention in the message
    """

    @type t :: %__MODULE__{
            participant_id: String.t(),
            display_name: String.t(),
            offset: non_neg_integer(),
            length: non_neg_integer()
          }
    defstruct [:participant_id, :display_name, :offset, :length]
  end

  # Basic parsec building blocks
  whitespace = ascii_string([?\s, ?\t, ?\n, ?\r], min: 1)
  mention_char = ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_])

  # Parser combinator for mention names
  mention_name_parser =
    ignore(ascii_char([?@]))
    |> repeat(mention_char)
    |> reduce({List, :to_string, []})
    |> post_traverse({:track_offset, []})

  defcombinator(:mention_name, mention_name_parser)

  # Parser for message content
  content_parser =
    repeat(
      choice([
        parsec(:mention_name),
        ignore(whitespace),
        utf8_string([], 1)
      ])
    )

  defparsecp(:parse_content, content_parser)

  @doc """
  Parse mentions from message content.

  Scans the message content for @mentions and returns structured information
  about each mention found, including position information for highlighting.

  ## Parameters
    * content - The message content to parse
    * participants - Map of participant IDs to display names

  ## Returns
    * `{:ok, mentions}` - List of Mention structs for each valid mention
    * `{:error, :invalid_input}` - If content or participants are invalid
    * `{:error, {:unparsed_content, rest}}` - If parsing failed

  ## Examples

      content = "Hello @alice and @bob!"
      participants = %{
        "user1" => "alice",
        "user2" => "bob"
      }

      {:ok, mentions} = Parser.parse_mentions(content, participants)
      # Returns:
      # [
      #   %Mention{
      #     participant_id: "user1",
      #     display_name: "alice",
      #     offset: 6,
      #     length: 5
      #   },
      #   %Mention{
      #     participant_id: "user2",
      #     display_name: "bob",
      #     offset: 16,
      #     length: 3
      #   }
      # ]
  """
  @spec parse_mentions(content :: String.t(), participants :: %{String.t() => String.t()}) ::
          {:ok, [Mention.t()]} | {:error, :invalid_input | {:unparsed_content, String.t()}}
  def parse_mentions(content, participants) when is_binary(content) and is_map(participants) do
    case parse_content(content) do
      {:ok, tokens, "", _context, _line, _offset} ->
        mentions = create_mentions(tokens, participants)
        {:ok, mentions}

      {:ok, _tokens, rest, _context, _line, _offset} ->
        {:error, {:unparsed_content, rest}}
    end
  end

  def parse_mentions(_content, _participants), do: {:error, :invalid_input}

  # Private Helpers

  defp create_mentions(tokens, participants) do
    tokens
    |> Enum.filter(&is_tuple/1)
    |> Enum.flat_map(&create_mention(&1, participants))
  end

  defp create_mention({name, offset}, participants) do
    case find_participant(name, participants) do
      nil ->
        []

      {id, display_name} ->
        [
          %Mention{
            participant_id: id,
            display_name: display_name,
            offset: offset,
            length: String.length(name)
          }
        ]
    end
  end

  defp find_participant(name, participants) do
    Enum.find(participants, fn {_id, display_name} ->
      String.downcase(display_name) == String.downcase(name)
    end)
  end

  # NimbleParsec callbacks

  defp track_offset(rest, [name], context, _line, offset) do
    {rest, [{name, offset - String.length(name) - 1}], context}
  end

  @doc """
  Parse mentions from message content without participant information.

  This is a simplified version of parse_mentions/2 that doesn't require participant information.
  It's useful for initial parsing of messages before participant information is available.

  ## Parameters
    * content - The message content to parse

  ## Returns
    * `{:ok, parsed_content, mentions}` - The parsed content and a list of potential mentions
    * `{:error, reason}` - If parsing failed
  """
  @spec parse(content :: String.t()) ::
          {:ok, String.t(), [String.t()]} | {:error, atom()}
  def parse(content) when is_binary(content) do
    case parse_content(content) do
      {:ok, tokens, "", _context, _line, _offset} ->
        # Extract potential mention names without participant validation
        potential_mentions =
          tokens
          |> Enum.filter(&is_tuple/1)
          |> Enum.map(fn {name, _offset} -> name end)

        {:ok, content, potential_mentions}

      {:ok, _tokens, rest, _context, _line, _offset} ->
        {:error, {:unparsed_content, rest}}

      _ ->
        {:error, :parse_error}
    end
  end

  def parse(_content), do: {:error, :invalid_input}
end
