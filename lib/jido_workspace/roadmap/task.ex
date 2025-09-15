defmodule JidoWorkspace.Roadmap.Task do
  @moduledoc """
  Represents a task checkbox found in a roadmap markdown file.
  """

  defstruct [:id, :title, :line_number, :file_path, :completed, :owner, :estimate, :raw_line]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t(),
          line_number: integer(),
          file_path: String.t(),
          completed: boolean(),
          owner: String.t() | nil,
          estimate: String.t() | nil,
          raw_line: String.t()
        }

  @checkbox_regex ~r/^- \[(?<status>[ x])\] (?<title>.+?)(?:\s+\*\((?<meta>[^)]+)\))?\s*(?:\((?<id>[A-Z]+-\d+)\))?$/

  @doc """
  Parses a markdown checkbox line into a Task struct.
  """
  def parse(line, line_number, file_path) when is_binary(line) do
    case Regex.named_captures(@checkbox_regex, String.trim(line)) do
      %{"status" => status, "title" => title} = captures ->
        {owner, estimate} = parse_meta(Map.get(captures, "meta", ""))
        
        %__MODULE__{
          id: Map.get(captures, "id"),
          title: String.trim(title),
          line_number: line_number,
          file_path: file_path,
          completed: status == "x",
          owner: owner,
          estimate: estimate,
          raw_line: line
        }
      
      nil ->
        nil
    end
  end

  @doc """
  Checks if a line is a task checkbox.
  """
  def task_line?(line) do
    String.trim(line) |> String.match?(@checkbox_regex)
  end

  @doc """
  Generates the next task ID for the given prefix and existing tasks.
  """
  def next_id(prefix, existing_tasks) when is_binary(prefix) and is_list(existing_tasks) do
    existing_numbers = 
      existing_tasks
      |> Enum.filter(&(&1.id && String.starts_with?(&1.id, prefix <> "-")))
      |> Enum.map(&(&1.id |> String.replace_prefix(prefix <> "-", "") |> String.to_integer()))
      |> Enum.max(fn -> 0 end)

    "#{prefix}-#{existing_numbers + 1}"
  end

  @doc """
  Converts task back to markdown checkbox format.
  """
  def to_markdown(%__MODULE__{} = task) do
    status = if task.completed, do: "x", else: " "
    
    meta_part = 
      case {task.owner, task.estimate} do
        {nil, nil} -> ""
        {owner, nil} -> " *(#{owner})*"
        {nil, estimate} -> " *(#{estimate})*"
        {owner, estimate} -> " *(#{owner}, #{estimate})*"
      end

    id_part = if task.id, do: " (#{task.id})", else: ""

    "- [#{status}] #{task.title}#{meta_part}#{id_part}"
  end

  # Private function to parse meta information (owner, estimate)
  defp parse_meta(""), do: {nil, nil}
  defp parse_meta(meta) do
    parts = String.split(meta, ",") |> Enum.map(&String.trim/1)
    
    case parts do
      [owner_or_estimate] ->
        if String.starts_with?(owner_or_estimate, "@") do
          {owner_or_estimate, nil}
        else
          {nil, owner_or_estimate}
        end
      
      [owner, estimate] ->
        {String.trim(owner), String.trim(estimate)}
      
      _ ->
        {nil, nil}
    end
  end
end
