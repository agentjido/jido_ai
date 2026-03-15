defmodule Jido.AI.Examples.Scripts.Bootstrap do
  @moduledoc false

  require Logger

  @examples_root Path.expand("../..", __DIR__)
  @examples_lib Path.join(@examples_root, "lib")

  def init!(opts \\ []) do
    Logger.configure(level: :warning)
    load_dotenv!()
    ensure_env!(Keyword.get(opts, :required_env, []))
    :ok
  end

  def load_dotenv! do
    env_file =
      [Path.join(File.cwd!(), ".env"), Path.expand("../.env", File.cwd!())]
      |> Enum.find(&File.exists?/1)

    cond do
      is_binary(env_file) and Code.ensure_loaded?(Dotenvy) ->
        Dotenvy.source!([env_file])

      is_binary(env_file) ->
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

  def load_examples! do
    @examples_lib
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.filter(&loadable_example?/1)
    |> Enum.sort_by(&load_order/1)
    |> Enum.each(&Code.require_file/1)

    :ok
  end

  defp load_order(file) do
    basename = Path.basename(file)

    if String.ends_with?(basename, "_agent.ex") do
      {1, file}
    else
      {0, file}
    end
  end

  defp loadable_example?(file) do
    cond do
      github_example_file?(file) and not github_tool_pack_available?() ->
        false

      true ->
        true
    end
  end

  defp github_example_file?(file) do
    file == Path.join(@examples_lib, "agents/issue_triage_agent.ex") or
      file == Path.join(@examples_lib, "tools/github.ex")
  end

  defp github_tool_pack_available? do
    Enum.all?(
      [
        Jido.Tools.Github.Issues.List,
        Jido.Tools.Github.Issues.Filter,
        Jido.Tools.Github.Issues.Find,
        Jido.Tools.Github.Issues.Update
      ],
      &Code.ensure_loaded?/1
    )
  end
end

Jido.AI.Examples.Scripts.Bootstrap.load_examples!()
