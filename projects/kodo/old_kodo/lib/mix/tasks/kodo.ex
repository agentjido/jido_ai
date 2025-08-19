defmodule Mix.Tasks.Kodo do
  @moduledoc """
  Starts an interactive Kodo shell.

  ## Usage

      mix kodo

  This will drop you into a Kodo shell where you can run commands
  in the virtual filesystem environment.
  """

  use Mix.Task

  @shortdoc "Start an interactive Kodo shell"

  def run(args) do
    case args do
      ["--help"] ->
        show_help()

      ["--version"] ->
        show_version()

      _ ->
        start_shell(args)
    end
  end

  def show_help do
    IO.puts("Usage: mix kodo [options]")
    IO.puts("")
    IO.puts("Start an interactive Kodo shell")
    IO.puts("")
    IO.puts("Options:")
    IO.puts("  --help     Show this help")
    IO.puts("  --version  Show version")
  end

  def show_version do
    version = Application.spec(:kodo, :vsn) || "unknown"
    IO.puts("Kodo version #{version}")
  end

  def start_shell(_args) do
    # Set logger level to info to hide debug messages during interactive use
    Logger.configure(level: :info)

    Mix.Task.run("app.start")
    {:ok, pid} = Kodo.Shell.start()

    # Keep the shell process alive and wait for it to terminate
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end
end
