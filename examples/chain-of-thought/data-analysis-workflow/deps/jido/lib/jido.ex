defmodule Jido do
  @moduledoc """
  自動 (Jido) - A foundational framework for building autonomous, distributed agent systems in Elixir.

  This module provides the main interface for interacting with Jido components, including:
  - Managing and interacting with Agents through a high-level API
  - Listing and retrieving Actions, Sensors, and Domains
  - Filtering and paginating results
  - Generating unique slugs for components

  ## Agent Interaction Examples

      # Find and act on an agent
      "agent-id"
      |> Jido.get_agent_by_id()
      |> Jido.act(:command, %{param: "value"})

      # Act asynchronously
      {:ok, agent} = Jido.get_agent_by_id("agent-id")
      Jido.act_async(agent, :command)

      # Send management commands
      {:ok, agent} = Jido.get_agent_by_id("agent-id")
      Jido.manage(agent, :pause)
  """
  @type component_metadata :: %{
          module: module(),
          name: String.t(),
          description: String.t(),
          slug: String.t(),
          category: atom() | nil,
          tags: [atom()] | nil
        }
  @type server ::
          pid() | atom() | binary() | {name :: atom() | binary(), registry :: module()}
  @callback config() :: keyword()

  defmacro __using__(opts) do
    quote do
      @behaviour unquote(__MODULE__)

      @otp_app unquote(opts)[:otp_app] ||
                 raise(ArgumentError, """
                 You must provide `otp_app: :your_app` to use Jido, e.g.:

                     use Jido, otp_app: :my_app
                 """)

      # Public function to retrieve config from application environment
      def config do
        Application.get_env(@otp_app, __MODULE__, [])
        |> Keyword.put_new(:agent_registry, Jido.Registry)
      end

      # Get the configured agent registry
      def agent_registry, do: config()[:agent_registry]

      # Provide a child spec so we can be placed directly under a Supervisor
      @spec child_spec(any()) :: Supervisor.child_spec()
      def child_spec(_arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, []},
          shutdown: 5000,
          type: :supervisor
        }
      end

      # Entry point for starting the Jido supervisor
      @spec start_link() :: Supervisor.on_start()
      def start_link do
        unquote(__MODULE__).ensure_started(__MODULE__)
      end

      # Delegate high-level API methods to Jido module
      # defdelegate cmd(agent, action, args \\ %{}, opts \\ []), to: Jido
      # defdelegate get_agent(id), to: Jido
      # defdelegate get_agent_status(agent_or_id), to: Jido
      # defdelegate get_agent_supervisor(agent_or_id), to: Jido
      # defdelegate get_agent_state(agent_or_id), to: Jido
    end
  end

  @doc """
  Retrieves a running Agent by its ID.

  ## Parameters

  - `id`: String or atom ID of the agent to retrieve
  - `opts`: Optional keyword list of options:
    - `:registry`: Override the default agent registry

  ## Returns

  - `{:ok, pid}` if agent is found and running
  - `{:error, :not_found}` if agent doesn't exist

  ## Examples

      iex> {:ok, agent} = Jido.get_agent("my-agent")
      {:ok, #PID<0.123.0>}

      # Using a custom registry
      iex> {:ok, agent} = Jido.get_agent("my-agent", registry: MyApp.Registry)
      {:ok, #PID<0.123.0>}
  """
  @spec get_agent(String.t() | atom(), keyword()) :: {:ok, pid()} | {:error, :not_found}
  def get_agent(id, opts \\ []) when is_binary(id) or is_atom(id) do
    registry = opts[:registry] || Jido.Registry

    case Registry.lookup(registry, id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Pipe-friendly version of get_agent that raises on errors.

  ## Parameters

  - `id`: String or atom ID of the agent to retrieve
  - `opts`: Optional keyword list of options:
    - `:registry`: Override the default agent registry

  ## Returns

  - `pid` if agent is found
  - Raises `RuntimeError` if agent not found

  ## Examples

      iex> "my-agent" |> Jido.get_agent!() |> Jido.cmd(:command)
      :ok
  """
  @spec get_agent!(String.t() | atom(), keyword()) :: pid()
  def get_agent!(id, opts \\ []) do
    case get_agent(id, opts) do
      {:ok, pid} -> pid
      {:error, :not_found} -> raise "Agent not found: #{id}"
    end
  end

  @doc """
  Gets the current state of an agent.

  ## Parameters

  - `agent_or_id`: Agent pid, ID, or return value from get_agent

  ## Returns

  - `{:ok, state}` with the agent's current state
  - `{:error, reason}` if state couldn't be retrieved

  ## Examples

      iex> {:ok, state} = Jido.get_agent_state("my-agent")
      {:ok, %Jido.Agent.Server.State{...}}
  """
  @spec get_agent_state(pid() | {:ok, pid()} | String.t()) :: {:ok, term()} | {:error, term()}
  def get_agent_state({:ok, pid}), do: get_agent_state(pid)

  def get_agent_state(pid) when is_pid(pid) do
    Jido.Agent.Server.state(pid)
  end

  def get_agent_state(id) when is_binary(id) or is_atom(id) do
    case get_agent(id) do
      {:ok, pid} -> get_agent_state(pid)
      error -> error
    end
  end

  @doc """
  Clones an existing agent with a new ID.

  ## Parameters

  - `source_id`: ID of the agent to clone
  - `new_id`: ID for the new cloned agent
  - `opts`: Optional keyword list of options to override for the new agent

  ## Returns

  - `{:ok, pid}` with the new agent's process ID
  - `{:error, reason}` if cloning fails

  ## Examples

      iex> {:ok, new_pid} = Jido.clone_agent("source-agent", "cloned-agent")
      {:ok, #PID<0.125.0>}
  """
  @spec clone_agent(String.t() | atom(), String.t() | atom(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def clone_agent(source_id, new_id, opts \\ []) do
    with {:ok, source_pid} <- get_agent(source_id),
         {:ok, source_state} <- Jido.Agent.Server.state(source_pid) do
      # Create new agent with updated ID but same config
      agent = %{source_state.agent | id: to_string(new_id)}

      # Merge original options with any overrides, keeping source config
      new_opts =
        source_state
        |> Map.take([
          :mode,
          :log_level,
          :max_queue_size,
          :registry,
          :dispatch,
          :skills
        ])
        |> Map.to_list()
        |> Keyword.merge([agent: agent], fn _k, _v1, v2 -> v2 end)
        |> Keyword.merge(opts, fn _k, _v1, v2 -> v2 end)

      # Ensure we have required fields from server state
      new_opts =
        new_opts
        |> Keyword.put_new(:max_queue_size, 10_000)
        |> Keyword.put_new(:mode, :auto)
        |> Keyword.put_new(:log_level, :info)
        |> Keyword.put_new(:registry, Jido.Registry)
        |> Keyword.put_new(
          :dispatch,
          {:logger, []}
        )
        |> Keyword.put_new(:skills, [])

      Jido.Agent.Server.start_link(new_opts)
    end
  end

  @doc """
  Callback used by the generated `start_link/0` function.
  This is where we actually call Jido.Supervisor.start_link.
  """
  @spec ensure_started(module()) :: Supervisor.on_start()
  def ensure_started(jido_module) do
    config = jido_module.config()
    Jido.Supervisor.start_link(jido_module, config)
  end

  @spec resolve_pid(server()) :: {:ok, pid()} | {:error, :server_not_found}
  def resolve_pid(pid) when is_pid(pid), do: {:ok, pid}

  def resolve_pid({name, registry})
      when (is_atom(name) or is_binary(name)) and is_atom(registry) do
    name = if is_atom(name), do: Atom.to_string(name), else: name

    case Registry.lookup(registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :server_not_found}
    end
  end

  def resolve_pid(name) when is_atom(name) or is_binary(name) do
    name = if is_atom(name), do: Atom.to_string(name), else: name
    resolve_pid({name, Jido.Registry})
  end

  # Component Discovery
  defdelegate list_actions(opts \\ []), to: Jido.Discovery
  defdelegate list_sensors(opts \\ []), to: Jido.Discovery
  defdelegate list_agents(opts \\ []), to: Jido.Discovery
  defdelegate list_skills(opts \\ []), to: Jido.Discovery
  defdelegate list_demos(opts \\ []), to: Jido.Discovery

  defdelegate get_action_by_slug(slug), to: Jido.Discovery
  defdelegate get_sensor_by_slug(slug), to: Jido.Discovery
  defdelegate get_agent_by_slug(slug), to: Jido.Discovery
  defdelegate get_skill_by_slug(slug), to: Jido.Discovery
  defdelegate get_demo_by_slug(slug), to: Jido.Discovery
end
