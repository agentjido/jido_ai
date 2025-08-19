#!/usr/bin/env elixir

# Simple test script to verify the instance system works
Mix.install([{:kodo, path: "."}])

defmodule InstanceTest do
  def run do
    IO.puts("=== Kodo Instance System Test ===")

    # Start the application
    {:ok, _} = Application.ensure_all_started(:kodo)

    # Test 1: List instances (should include default)
    IO.puts("\n1. Testing list_instances...")
    instances = Kodo.list_instances()
    IO.puts("Active instances: #{inspect(instances)}")

    # Test 2: Start a new instance
    IO.puts("\n2. Testing start_instance...")
    case Kodo.start_instance(:test_instance) do
      {:ok, pid} ->
        IO.puts("Started test_instance with PID: #{inspect(pid)}")
      {:error, reason} ->
        IO.puts("Failed to start test_instance: #{inspect(reason)}")
    end

    # Test 3: List instances again
    IO.puts("\n3. Testing list_instances after adding new instance...")
    instances = Kodo.list_instances()
    IO.puts("Active instances: #{inspect(instances)}")

    # Test 4: Start sessions in different instances
    IO.puts("\n4. Testing start_session in different instances...")
    
    # Default instance session
    case Kodo.start_session(:default) do
      {:ok, session_id, pid} ->
        IO.puts("Started session in :default - ID: #{session_id}, PID: #{inspect(pid)}")
      {:error, reason} ->
        IO.puts("Failed to start session in :default: #{inspect(reason)}")
    end

    # Test instance session
    case Kodo.start_session(:test_instance) do
      {:ok, session_id, pid} ->
        IO.puts("Started session in :test_instance - ID: #{session_id}, PID: #{inspect(pid)}")
      {:error, reason} ->
        IO.puts("Failed to start session in :test_instance: #{inspect(reason)}")
    end

    # Test 5: Test VFS isolation
    IO.puts("\n5. Testing VFS isolation...")
    
    case Kodo.write_file(:default, "test.txt", "content from default") do
      :ok -> IO.puts("Wrote file to :default VFS")
      {:error, reason} -> IO.puts("Failed to write to :default VFS: #{inspect(reason)}")
    end

    case Kodo.write_file(:test_instance, "test.txt", "content from test_instance") do
      :ok -> IO.puts("Wrote file to :test_instance VFS")
      {:error, reason} -> IO.puts("Failed to write to :test_instance VFS: #{inspect(reason)}")
    end

    case Kodo.read_file(:default, "test.txt") do
      {:ok, content} -> IO.puts("Read from :default VFS: #{inspect(content)}")
      {:error, reason} -> IO.puts("Failed to read from :default VFS: #{inspect(reason)}")
    end

    case Kodo.read_file(:test_instance, "test.txt") do
      {:ok, content} -> IO.puts("Read from :test_instance VFS: #{inspect(content)}")
      {:error, reason} -> IO.puts("Failed to read from :test_instance VFS: #{inspect(reason)}")
    end

    # Test 6: Stop instance
    IO.puts("\n6. Testing stop_instance...")
    case Kodo.stop_instance(:test_instance) do
      :ok ->
        IO.puts("Stopped :test_instance successfully")
      {:error, reason} ->
        IO.puts("Failed to stop :test_instance: #{inspect(reason)}")
    end

    # Test 7: Final instance list
    IO.puts("\n7. Final instance list...")
    instances = Kodo.list_instances()
    IO.puts("Active instances: #{inspect(instances)}")

    IO.puts("\n=== Test Complete ===")
  end
end

InstanceTest.run()
