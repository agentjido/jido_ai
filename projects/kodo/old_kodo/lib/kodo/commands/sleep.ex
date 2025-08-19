defmodule Kodo.Commands.Sleep do
  @moduledoc """
  Sleep command for testing purposes.
  Pauses execution for the specified number of seconds.
  """
  @behaviour Kodo.Ports.Command

  @impl true
  def name, do: "sleep"

  @impl true
  def description, do: "Pause for the given amount of seconds"

  @impl true
  def usage, do: "sleep <seconds>"

  @impl true
  def meta, do: [:builtin, :pure]

  @impl true
  def execute([seconds_str], _context) do
    case Integer.parse(seconds_str) do
      {seconds, ""} when seconds >= 0 ->
        Process.sleep(seconds * 1_000)
        {:ok, ""}

      _ ->
        {:error, "Invalid number: #{seconds_str}"}
    end
  end

  def execute(_, _context) do
    {:error, "Usage: #{usage()}"}
  end
end
