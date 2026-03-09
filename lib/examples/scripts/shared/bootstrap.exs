defmodule Jido.AI.Examples.Scripts.Bootstrap do
  @moduledoc false

  require Logger

  def init!(opts \\ []) do
    Logger.configure(level: :warning)
    load_dotenv!()
    ensure_env!(Keyword.get(opts, :required_env, []))
    :ok
  end

  def load_dotenv! do
    env_file = Path.join(File.cwd!(), ".env")

    cond do
      File.exists?(env_file) and Code.ensure_loaded?(Dotenvy) ->
        Dotenvy.source!([env_file])

      File.exists?(env_file) ->
        raise "Dotenvy is required to load #{env_file}"

      true ->
        :ok
    end
  end

  def ensure_env!(keys) when is_list(keys) do
    missing = Enum.reject(keys, &present_env?/1)

    if missing != [] do
      joined = Enum.join(missing, ", ")
      raise "Missing required environment variables: #{joined}"
    end

    :ok
  end

  def present_env?(key) do
    case System.get_env(key) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  def print_banner(title) do
    IO.puts("\n" <> String.duplicate("=", 72))
    IO.puts(title)
    IO.puts(String.duplicate("=", 72))
  end

  def assert!(true, _message), do: :ok

  def assert!(false, message) do
    raise RuntimeError, message
  end

  def assert_contains!(text, pattern, message) do
    case String.contains?(text, pattern) do
      true -> :ok
      false -> raise RuntimeError, message
    end
  end

  def start_named_jido!(name) do
    case Process.whereis(name) do
      nil ->
        {:ok, _pid} = Jido.start_link(name: name)
        :ok

      _pid ->
        :ok
    end
  end
end
