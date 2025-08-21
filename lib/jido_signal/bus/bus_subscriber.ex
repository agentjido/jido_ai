defmodule Jido.Signal.Bus.Subscriber do
  @moduledoc """
  Defines the subscriber model and subscription management for the signal bus.

  This module contains the subscriber type definition and functions for creating,
  managing, and dispatching signals to subscribers. It supports both regular and
  persistent subscriptions, handling subscription lifetime and signal delivery.
  """

  use Private
  use TypedStruct

  alias Jido.Signal.Bus.State, as: BusState
  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.Error
  alias Jido.Signal.Router

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:path, String.t(), enforce: true)
    field(:dispatch, term(), enforce: true)
    field(:persistent?, boolean(), default: false)
    field(:persistence_pid, pid(), default: nil)
    field(:disconnected?, boolean(), default: false)
    field(:created_at, DateTime.t(), default: DateTime.utc_now())
  end

  @spec subscribe(BusState.t(), String.t(), String.t(), keyword()) ::
          {:ok, BusState.t()} | {:error, Exception.t()}
  def subscribe(%BusState{} = state, subscription_id, path, opts) do
    persistent? = Keyword.get(opts, :persistent?, false)
    dispatch = Keyword.get(opts, :dispatch)

    # Check if subscription already exists
    if BusState.has_subscription?(state, subscription_id) do
      {:error,
       Error.validation_error(
         "Subscription already exists",
         %{field: :subscription_id, value: subscription_id}
       )}
    else
      # Create the subscription struct
      subscription = %Subscriber{
        id: subscription_id,
        path: path,
        dispatch: dispatch,
        persistent?: persistent?,
        persistence_pid: nil,
        created_at: DateTime.utc_now()
      }

      if persistent? do
        # Extract the client PID from the dispatch configuration
        client_pid = extract_client_pid(dispatch)

        # Start the persistent subscription process under the bus supervisor
        persistent_sub_opts = [
          id: subscription_id,
          bus_pid: self(),
          bus_subscription: subscription,
          start_from: opts[:start_from] || :origin,
          max_in_flight: opts[:max_in_flight] || 1000,
          client_pid: client_pid
        ]

        case DynamicSupervisor.start_child(
               state.child_supervisor,
               {Jido.Signal.Bus.PersistentSubscription, persistent_sub_opts}
             ) do
          {:ok, pid} ->
            # Update subscription with persistence pid
            subscription = %{subscription | persistence_pid: pid}

            case BusState.add_subscription(state, subscription_id, subscription) do
              {:ok, new_state} ->
                {:ok, new_state}

              {:error, reason} ->
                {:error,
                 Error.execution_error(
                   "Failed to add subscription",
                   %{action: "add_subscription", reason: reason}
                 )}
            end

          {:error, reason} ->
            {:error,
             Error.execution_error(
               "Failed to start persistent subscription",
               %{action: "start_persistent_subscription", reason: reason}
             )}
        end
      else
        # Since we already confirmed subscription doesn't exist, directly add it
        new_state = %{
          state
          | subscriptions: Map.put(state.subscriptions, subscription_id, subscription)
        }

        # Create route for the subscription
        route = %Router.Route{
          path: subscription.path,
          target: subscription.dispatch,
          priority: 0,
          match: nil
        }

        case BusState.add_route(new_state, route) do
          {:ok, final_state} ->
            {:ok, final_state}

          {:error, reason} ->
            {:error,
             Error.execution_error(
               "Failed to add subscription route",
               %{action: "add_route", reason: reason}
             )}
        end
      end
    end
  end

  @doc """
  Unsubscribes from the bus by removing the subscription and cleaning up resources.

  For persistent subscriptions, this also terminates the associated process.

  ## Parameters

  - `state`: The current bus state
  - `subscription_id`: The unique identifier of the subscription to remove
  - `opts`: Additional options (currently unused)

  ## Returns

  - `{:ok, new_state}` if successful
  - `{:error, Exception.t()}` if the subscription doesn't exist or removal fails
  """
  @spec unsubscribe(BusState.t(), String.t(), keyword()) ::
          {:ok, BusState.t()} | {:error, Exception.t()}
  def unsubscribe(%BusState{} = state, subscription_id, _opts \\ []) do
    # Get the subscription before removing it
    subscription = BusState.get_subscription(state, subscription_id)

    case BusState.remove_subscription(state, subscription_id) do
      {:ok, new_state} ->
        # If this was a persistent subscription, terminate the process
        if subscription && subscription.persistent? && subscription.persistence_pid do
          # Send shutdown message to terminate the process gracefully
          Process.send(subscription.persistence_pid, {:shutdown, :normal}, [])
        end

        {:ok, new_state}

      {:error, :subscription_not_found} ->
        {:error,
         Error.validation_error(
           "Subscription does not exist",
           %{field: :subscription_id, value: subscription_id}
         )}
    end
  end

  # Helper function to extract client PID from dispatch configuration
  @spec extract_client_pid(term()) :: pid() | nil
  defp extract_client_pid({:pid, opts}) when is_list(opts) do
    Keyword.get(opts, :target)
  end

  defp extract_client_pid(_) do
    nil
  end
end
