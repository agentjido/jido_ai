defmodule Jido.Signal.RouterTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Router

  @moduletag :capture_log

  setup do
    test_pid = self()

    routes = [
      # Static route - adds 1 to value
      {"user.created", :add},

      # Single wildcard route - multiplies value by 2
      {"user.*.updated", :multiply},

      # Multi-level wildcard route - subtracts 1 from value
      {"order.**.completed", :subtract},

      # Priority route - formats user data
      {"user.format", :format_user, 100},

      # Pattern match route - enriches user data if email present
      {
        "user.enrich",
        fn signal -> Map.has_key?(signal.data, :email) end,
        :enrich_user_data,
        90
      },

      # Single dispatch route - logs events
      {"audit.event", {:logger, [level: :info]}},

      # Multiple dispatch route - metrics and alerts
      {"system.error",
       [
         {:noop, [type: :error]},
         {:pid, [delivery_mode: :async, target: test_pid]}
       ]}
    ]

    {:ok, router} = Router.new(routes)
    {:ok, %{router: router, test_pid: test_pid}}
  end

  describe "route/2" do
    test "routes static path signal", %{router: router} do
      signal = %Signal{
        id: Jido.Signal.ID.generate!(),
        source: "/test",
        type: "user.created",
        data: %{value: 5}
      }

      assert {:ok, [:add]} = Router.route(router, signal)
    end

    test "routes single wildcard signal", %{router: router} do
      signal = %Signal{
        id: Jido.Signal.ID.generate!(),
        source: "/test",
        type: "user.123.updated",
        data: %{value: 10}
      }

      assert {:ok, [:multiply]} = Router.route(router, signal)
    end

    test "routes multi-level wildcard signal", %{router: router} do
      signal = %Signal{
        id: Jido.Signal.ID.generate!(),
        source: "/test",
        type: "order.123.payment.completed",
        data: %{value: 20}
      }

      assert {:ok, [:subtract]} = Router.route(router, signal)
    end

    test "routes by priority", %{router: router} do
      signal = %Signal{
        id: Jido.Signal.ID.generate!(),
        source: "/test",
        type: "user.format",
        data: %{
          name: "John Doe",
          email: "john@example.com",
          age: 30
        }
      }

      assert {:ok, [:format_user]} = Router.route(router, signal)
    end

    test "routes pattern matched signal", %{router: router} do
      signal = %Signal{
        id: Jido.Signal.ID.generate!(),
        source: "/test",
        type: "user.enrich",
        data: %{
          formatted_name: "John Doe",
          email: "john@example.com"
        }
      }

      assert {:ok, [:enrich_user_data]} = Router.route(router, signal)
    end

    test "does not route pattern matched signal when condition fails", %{router: router} do
      signal = %Signal{
        id: Jido.Signal.ID.generate!(),
        source: "/test",
        type: "user.enrich",
        data: %{
          formatted_name: "John Doe"
          # Missing email field
        }
      }

      assert {:error, error} = Router.route(router, signal)
      # error type assertion removed since new error structure doesn't have class field
      assert error.message == "No matching handlers found for signal"
    end

    test "returns error for unmatched path", %{router: router} do
      signal = %Signal{
        id: Jido.Signal.ID.generate!(),
        source: "/test",
        type: "unknown.path",
        data: %{}
      }

      assert {:error, error} = Router.route(router, signal)
      # error type assertion removed since new error structure doesn't have class field
      assert error.message == "No matching handlers found for signal"
    end

    test "routes to single dispatch target", %{router: router} do
      signal = %Signal{
        id: Jido.Signal.ID.generate!(),
        source: "/test",
        type: "audit.event",
        data: %{message: "Test event"}
      }

      assert {:ok, [{:logger, [level: :info]}]} = Router.route(router, signal)
    end

    test "routes to multiple dispatch targets", %{router: router, test_pid: test_pid} do
      signal = %Signal{
        id: Jido.Signal.ID.generate!(),
        source: "/test",
        type: "system.error",
        data: %{message: "Critical error"}
      }

      assert {:ok, targets} = Router.route(router, signal)
      assert length(targets) == 2
      assert Enum.member?(targets, {:noop, [type: :error]})
      assert Enum.member?(targets, {:pid, [delivery_mode: :async, target: test_pid]})
    end
  end

  describe "router edge cases" do
    test "handles path pattern edge cases", %{router: _router} do
      # Test empty path segments
      {:error, _error} = Router.new({"user..created", :test_action})
      # error type assertion removed since new error structure doesn't have class field

      # Test paths ending in wildcard
      {:ok, router} = Router.new({"user.*", :test_action})
      signal = %Signal{type: "user.anything", source: "/test", id: Jido.Signal.ID.generate!()}
      {:ok, [action]} = Router.route(router, signal)
      assert action == :test_action

      # Test paths starting with wildcard
      {:ok, router} = Router.new({"*.created", :test_action})
      signal = %Signal{type: "anything.created", source: "/test", id: Jido.Signal.ID.generate!()}
      {:ok, [action]} = Router.route(router, signal)
      assert action == :test_action

      # Test multiple consecutive wildcards
      {:error, error} = Router.new({"user.**.**.created", :test_action})
      # error type assertion removed since new error structure doesn't have class field
      assert error.message == "Path cannot contain multiple wildcards"
    end

    test "handles priority edge cases", %{router: _router} do
      # Test priority bounds
      {:error, _error} =
        Router.new({
          "test",
          :test_action,
          # Above max
          101
        })

      # error type assertion removed since new error structure doesn't have class field

      {:error, _error} =
        Router.new({
          "test",
          :test_action,
          # Below min
          -101
        })

      # error type assertion removed since new error structure doesn't have class field

      # Test same priority ordering
      {:ok, router} =
        Router.new([
          {"test", :action1, 0},
          {"test", :action2, 0}
        ])

      signal = %Signal{type: "test", source: "/test", id: Jido.Signal.ID.generate!()}
      {:ok, actions} = Router.route(router, signal)
      # Should maintain registration order
      assert [:action1, :action2] = actions
    end

    test "handles pattern matching edge cases" do
      # Test pattern function that raises
      {:error, _error} =
        Router.new({
          "test",
          fn _signal -> raise "boom" end,
          :test_action
        })

      # error type assertion removed since new error structure doesn't have class field

      # Test pattern function returning non-boolean
      pattern_fn = fn _signal -> "not a boolean" end

      {:error, _error} =
        Router.new({
          "test",
          pattern_fn,
          :test_action
        })

      # error type assertion removed since new error structure doesn't have class field

      # Test pattern function with nil signal data
      {:ok, router} =
        Router.new({
          "test",
          fn signal -> Map.get(signal.data, :key) == "value" end,
          :test_action
        })

      signal = %Signal{type: "test", source: "/test", id: Jido.Signal.ID.generate!(), data: nil}
      {:error, _error} = Router.route(router, signal)
      # error type assertion removed since new error structure doesn't have class field
    end

    test "handles route management edge cases" do
      # Test adding duplicate routes
      {:ok, router} = Router.new({"test", :action1})
      {:ok, router} = Router.add(router, {"test", :action2})
      signal = %Signal{type: "test", source: "/test", id: Jido.Signal.ID.generate!()}
      {:ok, actions} = Router.route(router, signal)
      # Should have both actions
      assert length(actions) == 2

      # Test removing non-existent route
      {:ok, router} = Router.remove(router, "nonexistent")
      # Should not error

      # Test removing last route
      {:ok, router} = Router.remove(router, "test")
      signal = %Signal{type: "test", source: "/test", id: Jido.Signal.ID.generate!()}
      {:error, error} = Router.route(router, signal)
      # error type assertion removed since new error structure doesn't have class field
      assert error.message == "No matching handlers found for signal"
    end

    test "handles signal type edge cases", %{router: router} do
      # Test empty signal type
      signal = %Signal{type: "", source: "/test", id: Jido.Signal.ID.generate!()}
      {:error, _error} = Router.route(router, signal)
      # error type assertion removed since new error structure doesn't have class field

      # Test very long path
      long_type = String.duplicate("a.", 100) <> "end"
      signal = %Signal{type: long_type, source: "/test", id: Jido.Signal.ID.generate!()}
      {:error, _error} = Router.route(router, signal)
      # error type assertion removed since new error structure doesn't have class field

      # Test invalid characters in type
      signal = %Signal{type: "user@123", source: "/test", id: Jido.Signal.ID.generate!()}
      {:error, _error} = Router.route(router, signal)
      # error type assertion removed since new error structure doesn't have class field
    end

    test "handles complex wildcard interactions" do
      {:ok, router} =
        Router.new([
          {"**", :catch_all, -100},
          {"*.*.created", :action1},
          {"user.**", :action2},
          {"user.*.created", :action3},
          {"user.123.created", :action4}
        ])

      # Test overlapping wildcards
      signal = %Signal{type: "user.123.created", source: "/test", id: Jido.Signal.ID.generate!()}
      {:ok, actions} = Router.route(router, signal)
      # Should match all patterns in correct priority order
      assert [:action4, :action3, :action2, :action1, :catch_all] = actions
    end

    test "handles trie node edge cases" do
      # Test very deep nesting - over 10 and the tests are really slow
      deep_path = String.duplicate("nested.", 10) <> "end"

      {:ok, router} =
        Router.new({
          deep_path,
          :test_action
        })

      signal = %Signal{type: deep_path, source: "/test", id: Jido.Signal.ID.generate!()}
      {:ok, [action]} = Router.route(router, signal)
      assert action == :test_action

      # Test wide trie (many siblings)
      wide_routes =
        for n <- 1..1000 do
          {"parent.#{n}", :test_action}
        end

      {:ok, router} = Router.new(wide_routes)

      signal = %Signal{type: "parent.500", source: "/test", id: Jido.Signal.ID.generate!()}
      {:ok, [action]} = Router.route(router, signal)
      assert action == :test_action
    end

    test "handles dispatch config edge cases" do
      test_pid = self()
      # Test multiple dispatch configs with same priority
      {:ok, router} =
        Router.new({
          "test",
          [
            {:logger, [level: :info]},
            {:noop, [type: :test]},
            {:pid, [delivery_mode: :async, target: test_pid]}
          ]
        })

      signal = %Signal{type: "test", source: "/test", id: Jido.Signal.ID.generate!()}
      {:ok, targets} = Router.route(router, signal)
      assert length(targets) == 3

      # Test dispatch config with pattern matching
      {:ok, router} =
        Router.new({
          "test",
          fn signal -> Map.get(signal.data, :important) == true end,
          {:pid, [delivery_mode: :async, target: test_pid]}
        })

      signal = %Signal{
        type: "test",
        source: "/test",
        id: Jido.Signal.ID.generate!(),
        data: %{important: true}
      }

      {:ok, targets} = Router.route(router, signal)
      assert length(targets) == 1
      assert Enum.member?(targets, {:pid, [delivery_mode: :async, target: test_pid]})

      # Test mixing actions and dispatch configs
      {:ok, router} =
        Router.new([
          {"test", :test_action},
          {"test", {:logger, [level: :info]}}
        ])

      signal = %Signal{type: "test", source: "/test", id: Jido.Signal.ID.generate!()}
      {:ok, targets} = Router.route(router, signal)
      assert length(targets) == 2
      assert Enum.any?(targets, &(&1 == :test_action))
      assert Enum.any?(targets, &match?({:logger, [level: :info]}, &1))
    end
  end
end
