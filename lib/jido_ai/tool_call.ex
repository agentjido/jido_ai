defmodule Jido.AI.ToolCall do
  @moduledoc """
  Consolidated tool call normalization for Jido.AI.

  This module provides a single canonical way to normalize tool calls from
  various formats (ReqLLM.ToolCall structs, maps with atom or string keys)
  into a consistent map format.

  ## Example

      iex> Jido.AI.ToolCall.normalize(%ReqLLM.ToolCall{id: "tc_1", function: %{name: "calc", arguments: %{a: 1}}})
      %{id: "tc_1", name: "calc", arguments: %{a: 1}}

      iex> Jido.AI.ToolCall.normalize(%{"id" => "tc_2", "name" => "search", "arguments" => "{\"q\": \"test\"}"})
      %{id: "tc_2", name: "search", arguments: %{"q" => "test"}}
  """

  @doc """
  Normalizes a tool call to a standard map format.

  Accepts `ReqLLM.ToolCall` structs or maps with atom/string keys.
  Arguments are parsed from JSON if provided as a string.

  ## Arguments

    * `tool_call` - A ReqLLM.ToolCall struct or map

  ## Returns

    A normalized map with `:id`, `:name`, and `:arguments` keys.

  ## Examples

      iex> Jido.AI.ToolCall.normalize(%ReqLLM.ToolCall{id: "tc_1", function: %{name: "calc", arguments: %{a: 1}}})
      %{id: "tc_1", name: "calc", arguments: %{a: 1}}
  """
  @spec normalize(struct() | map()) :: map()
  def normalize(%ReqLLM.ToolCall{} = tc) do
    %{
      id: tc.id || generate_id(),
      name: ReqLLM.ToolCall.name(tc),
      arguments: ReqLLM.ToolCall.args_map(tc) || %{}
    }
  end

  def normalize(tool_call) when is_map(tool_call) do
    %{
      id: tool_call[:id] || tool_call["id"] || generate_id(),
      name: tool_call[:name] || tool_call["name"],
      arguments: parse_arguments(tool_call[:arguments] || tool_call["arguments"] || %{})
    }
  end

  @doc """
  Parses tool call arguments, handling JSON strings.

  ## Arguments

    * `args` - Arguments as a map or JSON string

  ## Returns

    A map of parsed arguments.

  ## Examples

      iex> Jido.AI.ToolCall.parse_arguments(%{a: 1})
      %{a: 1}

      iex> Jido.AI.ToolCall.parse_arguments("{\"a\": 1}")
      %{"a" => 1}
  """
  @spec parse_arguments(term()) :: map()
  def parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end

  def parse_arguments(args) when is_map(args), do: args
  def parse_arguments(_), do: %{}

  defp generate_id, do: "call_#{:erlang.unique_integer([:positive])}"
end
