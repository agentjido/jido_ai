defmodule Kodo.Commands.Help do
  @moduledoc """
  Help command for listing available commands and their usage.
  """
  @behaviour Kodo.Ports.Command

  @impl true
  def name, do: "help"

  @impl true
  def description, do: "Display help information about available commands"

  @impl true
  def usage, do: "help [command]"

  @impl true
  def meta, do: [:builtin, :pure]

  @impl true
  def execute([], context) do
    # Use instance-specific command registry
    instance = Map.get(context, :instance, :default)
    command_registry = {:via, Registry, {Kodo.InstanceRegistry, {:command_registry, instance}}}
    commands = Kodo.Core.Commands.CommandRegistry.list_commands(command_registry)

    help_text =
      commands
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, module} ->
        "  #{String.pad_trailing(name, 10)} #{module.description()}"
      end)
      |> Enum.join("\n")

    {:ok, "Available commands:\n#{help_text}"}
  end

  def execute([command], context) do
    # Use instance-specific command registry
    instance = Map.get(context, :instance, :default)
    command_registry = {:via, Registry, {Kodo.InstanceRegistry, {:command_registry, instance}}}

    case Kodo.Core.Commands.CommandRegistry.get_command(command_registry, command) do
      {:ok, module} ->
        {:ok,
         """
         #{module.name()} - #{module.description()}

         Usage: #{module.usage()}
         """}

      :error ->
        {:error, "No help available for '#{command}'. Command not found."}
    end
  end

  def execute(_args, _context) do
    {:error, "Usage: #{usage()}"}
  end
end
