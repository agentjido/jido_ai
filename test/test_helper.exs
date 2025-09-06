ExUnit.start(capture_log: true)

defmodule Kagi.TestHelpers do
  @moduledoc false

  import ExUnit.Callbacks

  def with_temp_env_files(files_map, callback) do
    temp_dir = System.tmp_dir!()
    envs_dir = Path.join(temp_dir, "envs")
    File.mkdir_p!(envs_dir)

    Enum.each(files_map, fn {filename, content} ->
      file_path =
        case Path.extname(filename) do
          "" -> Path.join(temp_dir, ".env")
          _ -> Path.join(envs_dir, filename)
        end

      File.write!(file_path, content)
    end)

    original_cwd = File.cwd!()

    try do
      File.cd!(temp_dir)
      callback.()
    after
      File.cd!(original_cwd)
      # Use a more specific temp directory that we have permission to delete
      case File.rm_rf(temp_dir) do
        {:ok, _} -> :ok
        # Ignore cleanup errors in tests
        {:error, _reason, _file} -> :ok
      end
    end
  end

  def with_env_vars(env_vars, callback) when is_map(env_vars) do
    original_env = System.get_env()

    Enum.each(env_vars, fn {key, value} ->
      System.put_env(key, value)
    end)

    try do
      callback.()
    after
      current_env = System.get_env()

      Enum.each(env_vars, fn {key, _value} ->
        if not Map.has_key?(original_env, key) do
          System.delete_env(key)
        end
      end)

      Enum.each(original_env, fn {key, value} ->
        if Map.get(current_env, key) != value do
          System.put_env(key, value)
        end
      end)
    end
  end

  def with_app_config(config, callback) do
    original_config = Application.get_env(:kagi, :keyring)

    try do
      Application.put_env(:kagi, :keyring, config)
      callback.()
    after
      if original_config do
        Application.put_env(:kagi, :keyring, original_config)
      else
        Application.delete_env(:kagi, :keyring)
      end
    end
  end

  def start_kagi_server(opts \\ []) do
    case GenServer.start_link(Kagi.Server, opts, name: Kagi.Server) do
      {:ok, pid} ->
        register_cleanup_for_pid(pid)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      error ->
        error
    end
  end

  defp register_cleanup_for_pid(pid) do
    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid, :normal, 1000)
      end
    end)
  end

  def stop_kagi_server do
    if Process.whereis(Kagi.Server) do
      GenServer.stop(Kagi.Server, :normal, 1000)
    end
  end
end
