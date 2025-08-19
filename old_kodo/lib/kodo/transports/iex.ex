defmodule Kodo.Transports.IEx do
  @moduledoc """
  IEx-based transport implementation for interactive shell sessions.
  """
  use GenServer
  @behaviour Kodo.Ports.Transport
  require Logger
  import IO.ANSI

  # Transport Behaviour Implementation

  @impl true
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def stop(pid) do
    GenServer.stop(pid)
  end

  @impl true
  def write(pid, text) do
    GenServer.cast(pid, {:write, text})
  end

  # GenServer Implementation

  @impl true
  def init(opts) do
    prompt = Keyword.get(opts, :prompt, "#{green()}kodo>#{reset()} ")
    instance = Keyword.get(opts, :instance, :default)

    # Use instance-specific session supervisor
    session_supervisor_name =
      {:via, Registry, {Kodo.InstanceRegistry, {:session_supervisor, instance}}}

    {:ok, _session_id, session_pid} =
      Kodo.Core.Sessions.SessionSupervisor.new(session_supervisor_name, instance)

    state = %{
      prompt: prompt,
      session_pid: session_pid,
      history: [],
      instance: instance
    }

    # Start reading input after initialization
    schedule_read_input()

    {:ok, state}
  end

  @impl true
  def handle_info(:read_input, state) do
    # Read user input
    input = IO.gets(state.prompt)

    case handle_input(input, state) do
      {:ok, new_state} ->
        schedule_read_input()
        {:noreply, new_state}

      {:stop, reason} ->
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_cast({:write, text}, state) do
    IO.puts(format_output(text))
    {:noreply, state}
  end

  # Private Functions

  defp schedule_read_input do
    send(self(), :read_input)
  end

  def handle_input(input, state) when is_binary(input) do
    input = String.trim(input)

    case input do
      "exit" ->
        IO.puts("\n#{yellow()}Exiting shell session...#{reset()}")
        {:stop, :normal}

      "" ->
        {:ok, state}

      _ ->
        execute_command(input, state)
    end
  end

  def handle_input(:eof, _state) do
    IO.puts("\n#{yellow()}Received EOF, terminating...#{reset()}")
    {:stop, :normal}
  end

  defp execute_command(input, state) do
    case Kodo.Execute.execute_command(input, state.session_pid) do
      {:ok, output} when is_binary(output) ->
        IO.puts(format_output(output))
        {:ok, %{state | history: [input | state.history]}}

      {:error, error} ->
        IO.puts(:stderr, format_error(error))
        {:ok, state}

      other ->
        IO.puts(cyan() <> "Command result: " <> reset() <> inspect(other))
        {:ok, state}
    end
  end

  # Output Formatting

  def format_output(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map(&format_line/1)
    |> Enum.join("\n")
  end

  def format_output(other), do: inspect(other)

  def format_line("" <> _rest = line) do
    cond do
      String.starts_with?(line, "warning:") -> yellow() <> line <> reset()
      String.starts_with?(line, "error:") -> red() <> line <> reset()
      String.starts_with?(line, "info:") -> cyan() <> line <> reset()
      true -> line
    end
  end

  def format_error(error) do
    [
      red(),
      "Error: ",
      reset(),
      error,
      "\n",
      # dim(),
      "Type 'help' for available commands",
      reset()
    ]
    |> IO.ANSI.format()
    |> IO.chardata_to_string()
  end
end
