defmodule Jido.AI.ResponseParser do
  @moduledoc """
  Parses LLM responses to extract and validate JSON data.

  This module handles various LLM output formats, including:
  - Pure JSON responses
  - JSON wrapped in markdown code blocks
  - JSON with surrounding text
  - Malformed JSON that can be repaired

  ## Usage

      case ResponseParser.parse_json(response_content) do
        {:ok, data} -> # Use parsed data
        {:error, reason} -> # Handle parse error
      end

      # With schema validation
      case ResponseParser.parse_and_validate(response_content, MySchema) do
        {:ok, validated_data} -> # Use validated data
        {:error, errors} -> # Handle validation errors
      end
  """

  alias Jido.AI.SchemaValidator

  @doc """
  Parse JSON from LLM response content.

  Attempts multiple strategies to extract valid JSON:
  1. Direct JSON.decode
  2. Extract from markdown code blocks
  3. Find JSON object in mixed content
  4. Basic repair for common issues

  Returns `{:ok, parsed_data}` or `{:error, reason}`.

  ## Example

      iex> ResponseParser.parse_json(~s|{"name": "Alice"}|)
      {:ok, %{"name" => "Alice"}}

      iex> ResponseParser.parse_json("```json\\n{\\"name\\": \\"Bob\\"}\\n```")
      {:ok, %{"name" => "Bob"}}
  """
  def parse_json(content) when is_binary(content) do
    content
    |> String.trim()
    |> try_parse_strategies()
  end

  def parse_json(_content) do
    {:error, "Content must be a string"}
  end

  defp try_parse_strategies(content) do
    strategies = [
      &try_direct_parse/1,
      &try_markdown_extraction/1,
      &try_find_json_object/1,
      &try_repair_and_parse/1
    ]

    Enum.reduce_while(strategies, {:error, "No valid JSON found"}, fn strategy, _acc ->
      case strategy.(content) do
        {:ok, data} -> {:halt, {:ok, data}}
        {:error, _} -> {:cont, {:error, "No valid JSON found"}}
      end
    end)
  end

  defp try_direct_parse(content) do
    Jason.decode(content)
  rescue
    Jason.DecodeError -> {:error, "Not valid JSON"}
  end

  defp try_markdown_extraction(content) do
    # Match ```json ... ``` or ``` ... ```
    case Regex.run(~r/```(?:json)?\s*\n?(.*?)\n?```/s, content) do
      [_, json_content] ->
        try_direct_parse(String.trim(json_content))

      nil ->
        {:error, "No markdown code block found"}
    end
  end

  defp try_find_json_object(content) do
    # Try to find a JSON object anywhere in the content
    # Look for outermost { ... }
    case find_json_boundaries(content) do
      {start_pos, end_pos} when start_pos >= 0 and end_pos > start_pos ->
        json_str = String.slice(content, start_pos, end_pos - start_pos + 1)
        try_direct_parse(json_str)

      _ ->
        {:error, "No JSON object boundaries found"}
    end
  end

  defp find_json_boundaries(content) do
    # Find first { and matching }
    start_pos = :binary.match(content, "{")
    end_pos = find_matching_brace(content, start_pos)

    case {start_pos, end_pos} do
      {{pos, 1}, end_p} when is_integer(end_p) -> {pos, end_p}
      _ -> {-1, -1}
    end
  end

  defp find_matching_brace(content, {start, 1}) do
    # Count braces to find matching closing brace
    content
    |> String.slice((start + 1)..-1//1)
    |> String.graphemes()
    |> Enum.reduce_while({0, start + 1}, fn char, {depth, pos} ->
      case char do
        "{" -> {:cont, {depth + 1, pos + 1}}
        "}" when depth == 0 -> {:halt, {:found, pos}}
        "}" -> {:cont, {depth - 1, pos + 1}}
        _ -> {:cont, {depth, pos + 1}}
      end
    end)
    |> case do
      {:found, pos} -> pos
      _ -> -1
    end
  end

  defp find_matching_brace(_content, _no_match), do: -1

  defp try_repair_and_parse(content) do
    # Try common repairs
    repaired =
      content
      |> String.replace(~r/,\s*}/, "}")
      |> String.replace(~r/,\s*]/, "]")
      |> String.trim()

    try_direct_parse(repaired)
  end

  @doc """
  Parse JSON and validate against a schema.

  Combines JSON parsing with schema validation in a single step.

  Returns `{:ok, validated_data}` if both parsing and validation succeed,
  or `{:error, reason}` if either fails.

  ## Example

      case ResponseParser.parse_and_validate(content, MySchema) do
        {:ok, data} -> # data is parsed and validated
        {:error, reason} -> # either parsing or validation failed
      end
  """
  def parse_and_validate(content, schema_module) do
    with {:ok, parsed} <- parse_json(content),
         {:ok, validated} <- SchemaValidator.validate(parsed, schema_module) do
      {:ok, validated}
    else
      {:error, errors} when is_list(errors) ->
        # Schema validation errors
        {:error, SchemaValidator.format_errors(errors)}

      {:error, reason} ->
        # JSON parsing error
        {:error, "JSON parsing failed: #{reason}"}
    end
  end

  @doc """
  Extract JSON from response and return as map with atom keys.

  Similar to parse_json/1 but ensures the result has atom keys
  for easier pattern matching.

  ## Example

      iex> {:ok, data} = ResponseParser.parse_json_with_atoms(~s|{"name": "Alice"}|)
      iex> data.name
      "Alice"
  """
  def parse_json_with_atoms(content) do
    with {:ok, parsed} <- parse_json(content) do
      atomized = atomize_keys(parsed)
      {:ok, atomized}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_binary(k) ->
        try do
          {String.to_existing_atom(k), atomize_keys(v)}
        rescue
          ArgumentError -> {String.to_atom(k), atomize_keys(v)}
        end

      {k, v} when is_atom(k) ->
        {k, atomize_keys(v)}
    end)
    |> Enum.into(%{})
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value

  @doc """
  Check if content appears to contain JSON.

  Quick check without full parsing to determine if content
  is likely to contain JSON data.

  ## Example

      iex> ResponseParser.looks_like_json?(~s|{"key": "value"}|)
      true

      iex> ResponseParser.looks_like_json?("Just plain text")
      false
  """
  def looks_like_json?(content) when is_binary(content) do
    trimmed = String.trim(content)
    String.starts_with?(trimmed, "{") or String.contains?(trimmed, "```json")
  end

  def looks_like_json?(_), do: false
end
