defmodule Kodo.Commands.Pwd do
  @moduledoc """
  Print working directory command.
  """
  @behaviour Kodo.Ports.Command

  @impl true
  def name, do: "pwd"

  @impl true
  def description, do: "Print the current working directory"

  @impl true
  def usage, do: "pwd"

  @impl true
  def meta, do: [:builtin, :pure]

  @impl true
  def execute([], %{current_dir: dir}) do
    {:ok, dir}
  end

  def execute(_args, _context) do
    {:error, "Usage: #{usage()}"}
  end
end
