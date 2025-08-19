defmodule Kodo.Demo do
  @moduledoc """
  Demo script showing the public Kodo API functionality.
  """
  require Logger

  @doc """
  Run a demo of the Kodo public API.
  """
  def run do
    Logger.info("=== Kodo Public API Demo ===")

    # Show default instance
    Logger.info("Default instance exists: #{Kodo.exists?(:default)}")
    Logger.info("Active instances: #{inspect(Kodo.list())}")

    # Create new instances using public API
    Logger.info("\n--- Creating new instances ---")
    {:ok, dev_pid} = Kodo.start(:development)
    {:ok, test_pid} = Kodo.start(:testing)
    Logger.info("Created development instance: #{inspect(dev_pid)}")
    Logger.info("Created testing instance: #{inspect(test_pid)}")

    # List all instances
    Logger.info("All instances: #{inspect(Kodo.list())}")

    # Session management (placeholders)
    Logger.info("\n--- Session management (placeholders) ---")
    {:ok, session_id, session_pid} = Kodo.session(:development)
    Logger.info("Created session #{session_id}: #{inspect(session_pid)}")

    {:ok, result} = Kodo.eval(:development, session_id, "1 + 1")
    Logger.info("Eval result: #{inspect(result)}")

    # Component access
    Logger.info("\n--- Component access ---")
    {:ok, commands_pid} = Kodo.commands(:development)
    {:ok, jobs_pid} = Kodo.jobs(:development)
    {:ok, vfs_pid} = Kodo.vfs(:development)

    Logger.info("Development instance components:")
    Logger.info("  Commands: #{inspect(commands_pid)}")
    Logger.info("  Jobs: #{inspect(jobs_pid)}")
    Logger.info("  VFS: #{inspect(vfs_pid)}")

    # Command and job management (placeholders)
    Logger.info("\n--- Command and job management (placeholders) ---")
    :ok = Kodo.add_command(:development, MyTestCommand)
    Logger.info("Added command: MyTestCommand")

    {:ok, job_id} = Kodo.job(:development, %{cmd: "echo"}, "echo hello", session_id, false)
    Logger.info("Started job #{job_id}")

    {:ok, jobs} = Kodo.list_jobs(:development)
    Logger.info("Jobs: #{inspect(jobs)}")

    # VFS operations (placeholders)
    Logger.info("\n--- VFS operations (placeholders) ---")
    :ok = Kodo.mount(:development, "/data", SomeAdapter, name: :DataFS)
    Logger.info("Mounted /data")

    {root_fs, mounts} = Kodo.mounts(:development)
    Logger.info("Mounts: #{inspect({root_fs, mounts})}")

    # File operations show not implemented
    {:error, :not_implemented} = Kodo.read(:development, "/test.txt")
    {:error, :not_implemented} = Kodo.write(:development, "/test.txt", "content")
    Logger.info("File operations return :not_implemented as expected")

    false = Kodo.file_exists?(:development, "/test.txt")
    Logger.info("file_exists? returns false as expected")

    # Clean up
    Logger.info("\n--- Cleaning up ---")
    :ok = Kodo.stop(:development)
    :ok = Kodo.stop(:testing)
    Logger.info("Final instances: #{inspect(Kodo.list())}")

    Logger.info("=== Demo complete ===")
  end
end
