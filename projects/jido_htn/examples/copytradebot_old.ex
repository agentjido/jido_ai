# defmodule CopyTradingBot do
#   @moduledoc """
#   Domain for a cryptocurrency copy trading bot that mimics trades from a single observed wallet,
#   with support for managing partial positions (lots).
#   """

#   import StreamData

#   alias Jido.HTN
#   alias Jido.HTN.Domain
#   alias Jido.Action

#   require Logger

#   @type token :: atom()
#   @type amount :: float()
#   @type price :: float()
#   @type lot :: {amount(), price()}

#   defmodule Predicates do
#     @moduledoc false

#     def has_sufficient_balance?(state), do: state.available_balance >= state.trade_amount

#     def is_position_within_limits?(state) do
#       total_position_size(state, state.trade_token) + state.trade_amount <= state.max_position_size
#     end

#     def is_slippage_acceptable?(state) do
#       abs(state.expected_price - state.current_price) / state.expected_price <= state.max_slippage
#     end

#     def should_apply_risk_management?(state) do
#       Enum.any?(state.positions, fn {token, _lots} -> should_apply_risk_management_for_token?(state, token) end)
#     end

#     def has_open_positions?(state), do: map_size(state.positions) > 0

#     def observed_wallet_traded?(state), do: state.observed_wallet_action != nil

#     def has_sufficient_balance_for?(state, amount), do: state.available_balance >= amount

#     def is_position_within_limits_for?(state, token, amount) do
#       total_position_size(state, token) + amount <= state.max_position_size
#     end

#     def is_slippage_acceptable_for?(state, expected_price, current_price) do
#       abs(expected_price - current_price) / expected_price <= state.max_slippage
#     end

#     defp should_apply_risk_management_for_token?(state, token) do
#       current_price = state.asset_prices[token]
#       lots = state.positions[token]

#       Enum.any?(lots, fn {_amount, entry_price} ->
#         current_price <= entry_price * (1 - state.stop_loss) or
#           current_price >= entry_price * (1 + state.take_profit)
#       end)
#     end

#     defp total_position_size(state, token) do
#       state.positions
#       |> Map.get(token, [])
#       |> Enum.reduce(0, fn {amount, _price}, acc -> acc + amount end)
#     end
#   end

#   defmodule Transformers do
#     @moduledoc false

#     def update_balance(state) do
#       %{state | available_balance: state.available_balance - state.trade_amount}
#     end

#     def update_position(state) do
#       new_positions =
#         Map.update(state.positions, state.trade_token, [{state.trade_amount, state.trade_price}], fn lots ->
#           [{state.trade_amount, state.trade_price} | lots]
#         end)

#       %{state | positions: new_positions}
#     end

#     def apply_risk_management(state) do
#       Enum.reduce(state.positions, state, fn {token, lots}, acc_state ->
#         current_price = acc_state.asset_prices[token]

#         {lots_to_keep, lots_to_close} =
#           Enum.split_with(lots, fn {_amount, entry_price} ->
#             current_price > entry_price * (1 - acc_state.stop_loss) and
#               current_price < entry_price * (1 + acc_state.take_profit)
#           end)

#         acc_state = close_lots(acc_state, token, lots_to_close, current_price)

#         if lots_to_keep == [] do
#           %{acc_state | positions: Map.delete(acc_state.positions, token)}
#         else
#           %{acc_state | positions: Map.put(acc_state.positions, token, lots_to_keep)}
#         end
#       end)
#     end

#     def clear_observed_wallet_action(state) do
#       %{state | observed_wallet_action: nil}
#     end

#     defp close_lots(state, token, lots, current_price) do
#       Enum.reduce(lots, state, fn {amount, _entry_price}, acc_state ->
#         %{acc_state | available_balance: acc_state.available_balance + amount * current_price}
#       end)
#     end
#   end

#   defmodule CopyTradeWorkflow do
#     @moduledoc false
#     use Action,
#       name: "copy_trade_workflow",
#       description: "Copies a trade from the observed wallet",
#       schema: [
#         token: [type: :atom, required: true],
#         amount: [type: :float, required: true],
#         price: [type: :float, required: true]
#       ]

#     def run(%{token: token, amount: amount, price: price}, context) do
#       new_state =
#         context
#         |> Transformers.update_balance(amount * price)
#         |> Transformers.update_position(token, amount, price)
#         |> Transformers.clear_observed_wallet_action()

#       {:ok, new_state}
#     end
#   end

#   defmodule ApplyRiskManagementWorkflow do
#     @moduledoc false
#     use Action,
#       name: "apply_risk_management_workflow",
#       description: "Applies risk management rules to current positions"

#     def run(_params, context) do
#       new_state = Transformers.apply_risk_management(context)
#       {:ok, new_state}
#     end
#   end

#   defmodule StartSensorWorkflow do
#     @moduledoc false
#     use Action,
#       name: "start_sensor_workflow",
#       description: "Starts a price sensor for a specific token",
#       schema: [
#         token: [type: :atom, required: true]
#       ]

#     def run(%{token: token}, context) do
#       # In a real implementation, this would interact with an external system
#       # to start monitoring the price for the given token.
#       Logger.info("Started price sensor for #{token}")
#       {:ok, context}
#     end
#   end

#   defmodule StopSensorWorkflow do
#     @moduledoc false
#     use Action,
#       name: "stop_sensor_workflow",
#       description: "Stops a price sensor for a specific token",
#       schema: [
#         token: [type: :atom, required: true]
#       ]

#     def run(%{token: token}, context) do
#       # In a real implementation, this would interact with an external system
#       # to stop monitoring the price for the given token.
#       Logger.info("Stopped price sensor for #{token}")
#       {:ok, context}
#     end
#   end

#   def init do
#     alias Predicates, as: P
#     alias Transformers, as: T

#     "CopyTradingBot"
#     |> Domain.new()
#     |> Domain.compound("root",
#       methods: [%{subtasks: ["monitor_and_trade"]}]
#     )
#     |> Domain.compound("monitor_and_trade",
#       methods: [
#         %{conditions: [&P.should_apply_risk_management?/1], subtasks: ["apply_risk_management"]},
#         %{conditions: [&P.observed_wallet_traded?/1], subtasks: ["copy_observed_trade"]},
#         %{conditions: [], subtasks: ["wait_for_action"]}
#       ]
#     )
#     |> Domain.compound("copy_observed_trade",
#       methods: [
#         %{
#           conditions: [&P.has_sufficient_balance?/1, &P.is_position_within_limits?/1, &P.is_slippage_acceptable?/1],
#           subtasks: ["execute_copy_trade", "start_price_sensor"]
#         },
#         %{conditions: [], subtasks: ["log_failed_copy"]}
#       ]
#     )
#     |> Domain.primitive(
#       "execute_copy_trade",
#       {CopyTradeWorkflow, %{}},
#       preconditions: [&P.has_sufficient_balance?/1, &P.is_position_within_limits?/1, &P.is_slippage_acceptable?/1],
#       effects: [&T.update_balance/1, &T.update_position/1, &T.clear_observed_wallet_action/1]
#     )
#     |> Domain.primitive(
#       "apply_risk_management",
#       {ApplyRiskManagementWorkflow, %{}},
#       preconditions: [&P.should_apply_risk_management?/1],
#       effects: [&T.apply_risk_management/1]
#     )
#     |> Domain.primitive(
#       "start_price_sensor",
#       {StartSensorWorkflow, %{token: :placeholder}},
#       preconditions: [],
#       effects: []
#     )
#     |> Domain.primitive(
#       "stop_price_sensor",
#       {StopSensorWorkflow, %{token: :placeholder}},
#       preconditions: [],
#       effects: []
#     )
#     |> Domain.primitive(
#       "log_failed_copy",
#       {Action, %{name: "log_failed_copy"}},
#       preconditions: [],
#       effects: []
#     )
#     |> Domain.primitive(
#       "wait_for_action",
#       {Action, %{name: "wait_for_action"}},
#       preconditions: [],
#       effects: []
#     )
#     |> Domain.allow("CopyTrade", CopyTradeWorkflow)
#     |> Domain.allow("ApplyRiskManagement", ApplyRiskManagementWorkflow)
#     |> Domain.allow("StartSensor", StartSensorWorkflow)
#     |> Domain.allow("StopSensor", StopSensorWorkflow)
#   end

#   @doc """
#   Plans actions for the CopyTradingBot given a world state.
#   """
#   @spec plan(map()) :: {:ok, list()} | {:error, String.t()}
#   def plan(world_state) do
#     with :ok <- assert_valid_state(world_state) do
#       domain = init()
#       HTN.plan(domain, "root", world_state)
#     end
#   end

#   @doc """
#   Asserts that the given world state is valid for this domain.
#   """
#   @spec assert_valid_state(map()) :: :ok | {:error, String.t()}
#   def assert_valid_state(state) do
#     schema = [
#       observed_wallet: [type: :string, required: true],
#       bot_wallet: [type: :string, required: true],
#       positions: [type: {:map, :atom, {:list, {:tuple, [:float, :float]}}}, required: true],
#       asset_prices: [type: {:map, :atom, :float}, required: true],
#       available_balance: [type: :float, required: true],
#       max_position_size: [type: :float, required: true],
#       max_slippage: [type: :float, required: true],
#       stop_loss: [type: :float, required: true],
#       take_profit: [type: :float, required: true],
#       observed_wallet_action: [
#         type: {:or, [:atom, {:tuple, [:atom, :float, :float]}]},
#         required: true
#       ]
#     ]

#     case NimbleOptions.validate(state, schema) do
#       {:ok, _} -> :ok
#       {:error, %NimbleOptions.ValidationError{} = error} -> {:error, Exception.message(error)}
#     end
#   end

#   @doc """
#   Returns the initial state for the CopyTradingBot.
#   """
#   @spec initial_state() :: map()
#   def initial_state do
#     %{
#       observed_wallet: "solana_address_here",
#       bot_wallet: "bot_solana_address_here",
#       positions: %{},
#       asset_prices: %{},
#       available_balance: 1000.0,
#       max_position_size: 100.0,
#       max_slippage: 0.01,
#       stop_loss: 0.05,
#       take_profit: 0.10,
#       observed_wallet_action: nil
#     }
#   end
# end
