defmodule Jido.Signal.Bus.State do
  @moduledoc """
  Defines the state structure for the signal bus.

  This module contains the type definitions and operations for managing
  the internal state of the signal bus, including signal logs, subscriptions,
  snapshots, and router configuration. It provides functions for manipulating
  and querying this state.
  """

  use TypedStruct
  use ExDbug, enabled: false

  alias Jido.Signal
  alias Jido.Signal.Router

  typedstruct do
    field(:name, atom(), enforce: true)
    field(:router, Router.Router.t(), default: Router.new!())
    field(:log, %{String.t() => Signal.t()}, default: %{})
    field(:snapshots, %{String.t() => Signal.t()}, default: %{})
    field(:subscriptions, %{String.t() => Jido.Signal.Bus.Subscriber.t()}, default: %{})
    field(:child_supervisor, pid())
    field(:middleware, [Jido.Signal.Bus.MiddlewarePipeline.middleware_config()], default: [])
  end

  @doc """
  Merges a list of recorded signals into the existing log.
  Signals are added to the log keyed by their IDs.
  If a signal with the same ID already exists, it will be overwritten.

  ## Parameters
    - state: The current bus state
    - signals: List of recorded signals to merge

  ## Returns
    - `{:ok, new_state, recorded_signals}` with signals merged into log
    - `{:error, reason}` if there was an error processing the signals
  """
  @spec append_signals(t(), list(Jido.Signal.t() | {:ok, Jido.Signal.t()} | map())) ::
          {:ok, t(), list(Signal.t())} | {:error, term()}
  def append_signals(%__MODULE__{} = state, signals) when is_list(signals) do
    if signals == [] do
      {:ok, state, []}
    else
      try do
        {uuids, _timestamp} = Jido.Signal.ID.generate_batch(length(signals))

        new_log =
          uuids
          |> Enum.zip(signals)
          |> Enum.reduce(state.log, fn {uuid, signal}, acc ->
            # Use the UUID as the key for the signal
            Map.put(acc, uuid, signal)
          end)

        {:ok, %{state | log: new_log}, signals}
      rescue
        e in KeyError ->
          {:error, "Invalid signal format: #{Exception.message(e)}"}

        e ->
          {:error, "Error processing signals: #{Exception.message(e)}"}
      end
    end
  end

  @doc """
  Converts the signal log from a map to a sorted list.

  ## Parameters

  - `state`: The current bus state

  ## Returns

  A list of signals sorted by their IDs

  ## Examples

      iex> state = %Jido.Signal.Bus.State{log: %{"2" => signal2, "1" => signal1}}
      iex> signals = Jido.Signal.Bus.State.log_to_list(state)
      iex> length(signals)
      2
      iex> Enum.map(signals, & &1.id)
      ["1", "2"]
  """
  @spec log_to_list(t()) :: list(Signal.t())
  def log_to_list(%__MODULE__{} = state) do
    state.log
    |> Map.values()
    |> Enum.sort_by(fn signal -> signal.id end)
  end

  @doc """
  Truncates the signal log to the specified maximum size.
  Keeps the most recent signals and discards older ones.
  """
  @spec truncate_log(t(), non_neg_integer()) :: {:ok, t()}
  def truncate_log(%__MODULE__{} = state, max_size) when is_integer(max_size) and max_size >= 0 do
    if map_size(state.log) <= max_size do
      # No truncation needed
      {:ok, state}
    else
      sorted_signals =
        state.log
        |> Enum.sort_by(fn {key, _signal} -> key end)
        |> Enum.map(fn {_key, signal} -> signal end)

      # Keep only the most recent max_size signals
      to_keep = Enum.take(sorted_signals, -max_size)

      # Convert back to map
      truncated_log = Map.new(to_keep, fn signal -> {signal.id, signal} end)

      {:ok, %{state | log: truncated_log}}
    end
  end

  @doc """
  Clears all signals from the log.
  """
  @spec clear_log(t()) :: {:ok, t()}
  def clear_log(%__MODULE__{} = state) do
    {:ok, %{state | log: %{}}}
  end

  @doc """
  Adds a route to the router in the bus state.

  ## Parameters

  - `state`: The current bus state
  - `route`: The route to add to the router

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, reason}` if the route addition fails
  """
  @spec add_route(t(), Router.Route.t()) :: {:ok, t()} | {:error, term()}
  def add_route(%__MODULE__{} = state, route) do
    case Router.add(state.router, route) do
      {:ok, new_router} -> {:ok, %{state | router: new_router}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a route from the router in the bus state.

  ## Parameters

  - `state`: The current bus state
  - `route`: The route to remove (can be a Route struct or path string)

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, :route_not_found}` if the route doesn't exist
  """
  @spec remove_route(t(), Router.Route.t() | String.t()) :: {:ok, t()} | {:error, atom()}
  def remove_route(%__MODULE__{} = state, %Router.Route{} = route) do
    # Extract the path from the route
    path = route.path

    # Check if the route exists before trying to remove it
    {:ok, routes} = Router.list(state.router)
    route_exists = Enum.any?(routes, fn r -> r.path == path end)

    if route_exists do
      case Router.remove(state.router, path) do
        {:ok, new_router} -> {:ok, %{state | router: new_router}}
        _ -> {:error, :route_not_found}
      end
    else
      {:error, :route_not_found}
    end
  end

  def remove_route(%__MODULE__{} = state, path) when is_binary(path) do
    # Check if the route exists before trying to remove it
    {:ok, routes} = Router.list(state.router)
    route_exists = Enum.any?(routes, fn r -> r.path == path end)

    if route_exists do
      case Router.remove(state.router, path) do
        {:ok, new_router} -> {:ok, %{state | router: new_router}}
        _ -> {:error, :route_not_found}
      end
    else
      {:error, :route_not_found}
    end
  end

  @doc """
  Checks if a subscription exists in the bus state.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The ID of the subscription to check

  ## Returns

  `true` if the subscription exists, `false` otherwise
  """
  @spec has_subscription?(t(), String.t()) :: boolean()
  def has_subscription?(%__MODULE__{} = state, subscription_id) do
    Map.has_key?(state.subscriptions, subscription_id)
  end

  @doc """
  Retrieves a subscription from the bus state.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The ID of the subscription to retrieve

  ## Returns

  The subscription struct if found, `nil` otherwise
  """
  @spec get_subscription(t(), String.t()) :: Jido.Signal.Bus.Subscriber.t() | nil
  def get_subscription(%__MODULE__{} = state, subscription_id) do
    Map.get(state.subscriptions, subscription_id)
  end

  @doc """
  Adds a subscription to the bus state and creates a corresponding route.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The unique ID for the subscription
  - `subscription`: The subscription struct to add

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, :subscription_exists}` if a subscription with this ID already exists
  """
  @spec add_subscription(t(), String.t(), Jido.Signal.Bus.Subscriber.t()) ::
          {:ok, t()} | {:error, atom()}
  def add_subscription(%__MODULE__{} = state, subscription_id, subscription) do
    if has_subscription?(state, subscription_id) do
      {:error, :subscription_exists}
    else
      new_state = %{
        state
        | subscriptions: Map.put(state.subscriptions, subscription_id, subscription)
      }

      add_route(new_state, subscription_to_route(subscription))
    end
  end

  @doc """
  Removes a subscription from the bus state and its corresponding route.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The ID of the subscription to remove
  - `opts`: Options including:
    - `:delete_persistence` - Whether to delete persistence (default: true)

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, :subscription_not_found}` if the subscription doesn't exist
  """
  @spec remove_subscription(t(), String.t(), keyword()) :: {:ok, t()} | {:error, atom()}
  def remove_subscription(%__MODULE__{} = state, subscription_id, opts \\ []) do
    delete_persistence = Keyword.get(opts, :delete_persistence, true)

    if has_subscription?(state, subscription_id) && delete_persistence do
      {subscription, new_subscriptions} = Map.pop(state.subscriptions, subscription_id)
      new_state = %{state | subscriptions: new_subscriptions}

      case Router.remove(new_state.router, subscription.path) do
        {:ok, new_router} -> {:ok, %{new_state | router: new_router}}
        _ -> {:error, :route_not_found}
      end
    else
      {:error, :subscription_not_found}
    end
  end

  @spec subscription_to_route(Jido.Signal.Bus.Subscriber.t()) :: Router.Route.t()
  defp subscription_to_route(subscription) do
    %Router.Route{
      # Use the path pattern for matching
      path: subscription.path,
      target: subscription.dispatch,
      priority: 0,
      # Let the Router's path matching handle wildcards
      match: nil
    }
  end
end
