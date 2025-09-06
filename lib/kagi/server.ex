defmodule Kagi.Server do
  @moduledoc """
  A GenServer that manages environment variables and application configuration.
  """

  use GenServer

  require Logger

  @env_table :kagi_env_cache

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @impl true
  def init(_opts) do
    if :ets.whereis(@env_table) != :undefined do
      :ets.delete(@env_table)
    end

    env_table = :ets.new(@env_table, [:set, :protected, :named_table, read_concurrency: true])

    env_vars = load_from_env()
    app_config = load_from_app_config()
    all_vars = Map.merge(app_config, env_vars)

    Enum.each(all_vars, fn {key, value} ->
      :ets.insert(env_table, {key, value})
      livebook_key = to_livebook_key(key)
      :ets.insert(env_table, {livebook_key, value})
    end)

    Logger.debug("Kagi.Server loaded #{map_size(all_vars)} configuration variables")

    {:ok, %{env_table: env_table}}
  end

  @impl true
  def handle_call({:get, key, default}, _from, %{env_table: env_table} = state) do
    normalized_key = normalize_key(key)

    result =
      case get_hierarchical_value(env_table, normalized_key) do
        nil -> default
        value -> value
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list, _from, %{env_table: env_table} = state) do
    keys = :ets.foldr(fn {key, _value}, acc -> [key | acc] end, [], env_table)
    {:reply, keys, state}
  end

  @impl true
  def handle_call({:put, key, value}, _from, %{env_table: env_table} = state) do
    normalized_key = normalize_key(key)
    :ets.insert(env_table, {normalized_key, value})
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:reload, _opts}, %{env_table: env_table} = state) do
    :ets.delete_all_objects(env_table)

    env_vars = load_from_env()
    app_config = load_from_app_config()
    all_vars = Map.merge(app_config, env_vars)

    Enum.each(all_vars, fn {key, value} ->
      :ets.insert(env_table, {key, value})
      livebook_key = to_livebook_key(key)
      :ets.insert(env_table, {livebook_key, value})
    end)

    Logger.debug("Kagi.Server reloaded #{map_size(all_vars)} configuration variables")

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{env_table: _env_table}) do
    if :ets.whereis(@env_table) != :undefined do
      :ets.delete(@env_table)
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  @doc false
  @spec load_from_env() :: map()
  defp load_from_env do
    env_dir_prefix = Path.expand("./envs/")
    current_env = get_environment()

    env_sources =
      Dotenvy.source!([
        Path.join(File.cwd!(), ".env"),
        Path.absname(".env", env_dir_prefix),
        Path.absname(".#{current_env}.env", env_dir_prefix),
        Path.absname(".#{current_env}.overrides.env", env_dir_prefix),
        System.get_env()
      ])

    Enum.reduce(env_sources, %{}, fn {key, value}, acc ->
      normalized_key = normalize_env_key(key)
      Map.put(acc, normalized_key, value)
    end)
  rescue
    error ->
      Logger.warning("Failed to load environment variables: #{inspect(error)}")
      %{}
  end

  @doc false
  @spec get_environment() :: atom()
  defp get_environment do
    Application.get_env(:kagi, :env) || :prod
  end

  @doc false
  @spec normalize_env_key(String.t()) :: String.t()
  defp normalize_env_key(env_var) do
    env_var
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
  end

  @doc false
  @spec normalize_key(atom() | String.t()) :: String.t()
  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> normalize_env_key()
  defp normalize_key(key) when is_binary(key), do: normalize_env_key(key)

  @doc false
  @spec load_from_app_config() :: map()
  defp load_from_app_config do
    case Application.get_env(:kagi, :keyring) do
      nil ->
        %{}

      config when is_map(config) ->
        Enum.reduce(config, %{}, fn {key, value}, acc ->
          str_key = normalize_key(key)
          Map.put(acc, str_key, value)
        end)

      _ ->
        %{}
    end
  end

  @doc false
  @spec to_livebook_key(String.t()) :: String.t()
  defp to_livebook_key(key), do: "lb_#{key}"

  @doc false
  @spec get_hierarchical_value(atom(), String.t()) :: String.t() | nil
  defp get_hierarchical_value(env_table, normalized_key) do
    case :ets.lookup(env_table, normalized_key) do
      [{^normalized_key, value}] ->
        value

      [] ->
        livebook_key = to_livebook_key(normalized_key)

        case :ets.lookup(env_table, livebook_key) do
          [{^livebook_key, value}] -> value
          [] -> nil
        end
    end
  end
end
