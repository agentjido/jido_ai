defmodule Kodo.Shell do
  @moduledoc """
  Main public facade for the Kodo shell system.

  This module provides the primary interface for starting shell sessions,
  evaluating commands, and managing the shell environment.
  """

  @doc """
  Starts an interactive shell session with the given options.

  ## Options

    * `:prompt` - Custom prompt string (default: "kodo> ")
    * `:transport` - Transport module to use (default: Kodo.Transports.IEx)

  ## Examples

      # Starting a shell session
      {:ok, pid} = Kodo.Shell.start()
      is_pid(pid)  # => true
  """
  def start(opts \\ []) do
    transport = Keyword.get(opts, :transport, Kodo.Transports.IEx)
    transport.start_link(opts)
  end

  @doc """
  Stops a shell session.

  ## Examples

      # Stopping a shell session
      {:ok, pid} = Kodo.Shell.start()
      Process.alive?(pid)  # => true
  """
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid)
  end

  @doc """
  Evaluates a command in the context of a session.

  ## Examples

      # Evaluating a command
      {:ok, _session_id, session_pid} = Kodo.Core.SessionSupervisor.start_session()
      {:ok, output} = Kodo.Shell.eval("help", session_pid)
      is_binary(output)  # => true
  """
  def eval(command, session_pid) when is_binary(command) and is_pid(session_pid) do
    Kodo.Execute.execute_command(command, session_pid)
  end

  @doc """
  Gets the current working directory for a session.

  ## Examples

      # Getting current directory
      {:ok, _session_id, session_pid} = Kodo.Core.SessionSupervisor.start_session()
      {:ok, pwd} = Kodo.Shell.pwd(session_pid)
      is_binary(pwd)  # => true
  """
  def pwd(session_pid) when is_pid(session_pid) do
    case Kodo.Core.Sessions.Session.get_env(session_pid, "PWD") do
      {:ok, pwd} -> {:ok, pwd}
      :error -> {:ok, "/"}
    end
  end

  @doc """
  Changes the current working directory for a session.

  ## Examples

      # Changing directory
      {:ok, _session_id, session_pid} = Kodo.Core.SessionSupervisor.start_session()
      Kodo.Shell.cd(session_pid, "/tmp")  # => :ok
  """
  def cd(session_pid, path) when is_pid(session_pid) and is_binary(path) do
    Kodo.Core.Sessions.Session.set_env(session_pid, "PWD", path)
  end

  @doc """
  Gets an environment variable for a session.

  ## Examples

      # Getting environment variable
      {:ok, _session_id, session_pid} = Kodo.Core.SessionSupervisor.start_session()
      {:ok, shell} = Kodo.Shell.get_env(session_pid, "SHELL")
      shell  # => "kodo"
  """
  def get_env(session_pid, var_name) when is_pid(session_pid) and is_binary(var_name) do
    Kodo.Core.Sessions.Session.get_env(session_pid, var_name)
  end

  @doc """
  Sets an environment variable for a session.

  ## Examples

      # Setting environment variable
      {:ok, _session_id, session_pid} = Kodo.Core.SessionSupervisor.start_session()
      Kodo.Shell.set_env(session_pid, "MY_VAR", "my_value")  # => :ok
  """
  def set_env(session_pid, var_name, value)
      when is_pid(session_pid) and is_binary(var_name) and is_binary(value) do
    Kodo.Core.Sessions.Session.set_env(session_pid, var_name, value)
  end

  @doc """
  Lists files in the given directory path for a session.

  ## Examples

      # Listing directory contents
      {:ok, _session_id, session_pid} = Kodo.Core.SessionSupervisor.start_session()
      result = Kodo.Shell.ls(session_pid, "/")
      case result do
        {:ok, _} -> true
        {:error, _} -> true
      end  # => true
  """
  def ls(session_pid, path \\ ".") when is_pid(session_pid) and is_binary(path) do
    eval("ls #{path}", session_pid)
  end
end
