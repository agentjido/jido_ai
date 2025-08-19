defmodule Kodo.Commands.Env do
  @moduledoc """
  Environment variables command.
  """
  @behaviour Kodo.Ports.Command

  @impl true
  def name, do: "env"

  @impl true
  def description, do: "Display or modify environment variables"

  @impl true
  def usage, do: "env [NAME[=VALUE]]"

  @impl true
  def meta, do: [:builtin]

  @impl true
  def execute([], context) do
    formatted =
      context.env
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join("\n")

    {:ok, formatted}
  end

  @impl true
  def execute([setting], context) when is_binary(setting) do
    case String.contains?(setting, "=") do
      true ->
        case String.split(setting, "=", parts: 2) do
          [name, value] ->
            # Instead of calling Session directly, return a description of the state change
            {:ok, "#{name}=#{value}", %{session_updates: %{set_env: %{name => value}}}}

          _ ->
            {:error, "Invalid format. Usage: #{usage()}"}
        end

      false ->
        case Map.fetch(context.env, setting) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, "Environment variable '#{setting}' not found"}
        end
    end
  end

  def execute(_args, _context) do
    {:error, "Usage: #{usage()}"}
  end
end
