defmodule JidoTest.HTN.DomainFullTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.Domain
  @moduletag :capture_log
  defmodule OpenPositionWorkflow do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  defmodule ClosePositionWorkflow do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  defmodule CopyTradeDomain do
    @moduledoc false
    @behaviour Jido.HTN.DomainBehaviour

    defmodule Predicates do
      @moduledoc false
      def has_open_position?(state), do: Enum.any?(state.positions)
      def has_sufficient_balance?(state), do: state.balance >= state.required_amount
      def copied_wallet_action?(state, action), do: state.current_copied_action == action
    end

    defmodule Transformers do
      @moduledoc false
      def open_position(state) do
        new_position = %{
          asset: state.current_asset,
          amount: state.required_amount,
          entry_price: state.current_prices[state.current_asset]
        }

        %{
          state
          | positions: [new_position | state.positions],
            balance: state.balance - state.required_amount
        }
      end

      def close_position(state, asset) do
        {closed_position, remaining_positions} =
          Enum.split_with(state.positions, &(&1.asset == asset))

        case closed_position do
          [position] ->
            profit = calculate_profit(position, state.current_prices[asset])

            %{
              state
              | positions: remaining_positions,
                balance: state.balance + position.amount + profit,
                total_profit: state.total_profit + profit
            }

          [] ->
            state
        end
      end

      defp calculate_profit(position, current_price) do
        (current_price - position.entry_price) * position.amount
      end
    end

    def predicates, do: Predicates

    def transformers, do: Transformers

    def init(_opts \\ []) do
      alias Predicates, as: P
      alias Transformers, as: T

      "Copy Trade"
      |> Domain.new()
      |> Domain.compound("root",
        methods: [%{subtasks: ["manage_trades"]}]
      )
      |> Domain.compound("manage_trades",
        methods: [
          %{subtasks: ["handle_copied_wallet_actions"]}
        ]
      )
      |> Domain.compound("handle_copied_wallet_actions",
        methods: [
          %{
            conditions: [fn state -> P.copied_wallet_action?(state, :buy) end],
            subtasks: ["open_position"]
          },
          %{
            conditions: [fn state -> P.copied_wallet_action?(state, :sell) end],
            subtasks: ["close_position"]
          }
        ]
      )
      |> Domain.primitive("open_position",
        preconditions: [
          fn state -> not P.has_open_position?(state) end,
          fn state -> P.has_sufficient_balance?(state) end
        ],
        task: {Jido.Agent.CopyTradeBot.OpenPositionWorkflow, []},
        effects: [fn state -> T.open_position(state) end]
      )
      |> Domain.primitive("close_position",
        preconditions: [fn state -> P.has_open_position?(state) end],
        task: {ClosePositionWorkflow, []},
        effects: [fn state, params -> T.close_position(state, params) end]
      )
      |> Domain.allow("OpenPosition", OpenPositionWorkflow)
      |> Domain.allow("ClosePosition", ClosePositionWorkflow)
      |> Domain.build()
    end
  end

  describe "CopyTradeDomain.init/1" do
    setup do
      {:ok, domain} = CopyTradeDomain.init()
      %{domain: domain}
    end

    # test "creates a valid domain", %{domain: domain} do
    #   assert :ok = Domain.validate(domain)
    # end

    test "has the correct name", %{domain: domain} do
      assert domain.name == "Copy Trade"
    end

    #   test "has the expected tasks", %{domain: domain} do
    #     tasks = Domain.list_tasks(domain)
    #     assert "root" in tasks
    #     assert "manage_trades" in tasks
    #     assert "handle_copied_wallet_actions" in tasks
    #     assert "open_position" in tasks
    #     assert "close_position" in tasks
    #   end

    #   test "has the expected allowed workflows", %{domain: domain} do
    #     allowed_workflows = Domain.list_allowed_workflows(domain)
    #     assert Map.has_key?(allowed_workflows, "OpenPosition")
    #     assert Map.has_key?(allowed_workflows, "ClosePosition")
    #   end
    # end

    # describe "CopyTradeDomain.Predicates" do
    #   test "has_open_position?/2" do
    #     state = %{positions: [%{asset: "BTC", amount: 1.0}]}
    #     assert CopyTradeDomain.Predicates.has_open_position?(state, "BTC")
    #     refute CopyTradeDomain.Predicates.has_open_position?(state, "ETH")
    #   end

    #   test "has_sufficient_balance?/2" do
    #     state = %{balance: 1000}
    #     assert CopyTradeDomain.Predicates.has_sufficient_balance?(state, 500)
    #     refute CopyTradeDomain.Predicates.has_sufficient_balance?(state, 1500)
    #   end

    #   test "copied_wallet_action?/3" do
    #     state = %{copied_wallet_actions: %{"BTC" => :buy, "ETH" => :sell}}
    #     assert CopyTradeDomain.Predicates.copied_wallet_action?(state, "BTC", :buy)
    #     assert CopyTradeDomain.Predicates.copied_wallet_action?(state, "ETH", :sell)
    #     refute CopyTradeDomain.Predicates.copied_wallet_action?(state, "BTC", :sell)
    #   end
    # end

    # describe "CopyTradeDomain.Transformers" do
    #   test "open_position/3" do
    #     state = %{
    #       positions: [],
    #       balance: 1000,
    #       current_prices: %{"BTC" => 50_000}
    #     }

    #     new_state = CopyTradeDomain.Transformers.open_position(state, "BTC", 0.1)

    #     assert length(new_state.positions) == 1
    #     assert hd(new_state.positions).asset == "BTC"
    #     assert hd(new_state.positions).amount == 0.1
    #     assert hd(new_state.positions).entry_price == 50_000
    #     # 1000 - (0.1 * 50000)
    #     assert new_state.balance == 995
    #   end

    #   test "close_position/2" do
    #     state = %{
    #       positions: [%{asset: "BTC", amount: 0.1, entry_price: 50_000}],
    #       balance: 1000,
    #       current_prices: %{"BTC" => 55_000},
    #       total_profit: 0
    #     }

    #     new_state = CopyTradeDomain.Transformers.close_position(state, "BTC")

    #     assert Enum.empty?(new_state.positions)
    #     # 1000 + (0.1 * 55000)
    #     assert new_state.balance == 1500
    #     # (55000 - 50000) * 0.1
    #     assert new_state.total_profit == 500
    #   end
  end
end
