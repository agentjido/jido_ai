defmodule JidoTest.Signal.RegistryTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Registry
  alias Jido.Signal.Registry.Subscription

  describe "new/0" do
    test "creates an empty registry" do
      registry = Registry.new()
      assert %Registry{subscriptions: subscriptions} = registry
      assert map_size(subscriptions) == 0
    end
  end

  describe "register/4" do
    test "successfully registers a new subscription" do
      registry = Registry.new()
      dispatch_config = {:pid, self()}

      assert {:ok, updated_registry} =
               Registry.register(registry, "sub1", "user.created", dispatch_config)

      assert %Registry{subscriptions: subscriptions} = updated_registry
      assert map_size(subscriptions) == 1
      assert Map.has_key?(subscriptions, "sub1")

      subscription = subscriptions["sub1"]

      assert %Subscription{
               id: "sub1",
               path: "user.created",
               dispatch: ^dispatch_config,
               created_at: %DateTime{}
             } = subscription
    end

    test "returns error when subscription ID already exists" do
      registry = Registry.new()
      dispatch_config1 = {:pid, self()}
      dispatch_config2 = {:http, "http://example.com"}

      {:ok, registry} = Registry.register(registry, "sub1", "user.created", dispatch_config1)

      assert {:error, :already_exists} =
               Registry.register(registry, "sub1", "user.updated", dispatch_config2)
    end

    test "can register multiple subscriptions with different IDs" do
      registry = Registry.new()

      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})

      {:ok, registry} =
        Registry.register(registry, "sub2", "user.updated", {:http, "http://example.com"})

      assert Registry.count(registry) == 2
    end

    test "can register subscriptions with same path but different IDs" do
      registry = Registry.new()

      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})

      {:ok, registry} =
        Registry.register(registry, "sub2", "user.created", {:http, "http://example.com"})

      assert Registry.count(registry) == 2

      subscriptions = Registry.find_by_path(registry, "user.created")
      assert length(subscriptions) == 2
    end
  end

  describe "unregister/2" do
    test "successfully removes an existing subscription" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})

      assert Registry.count(registry) == 1

      assert {:ok, updated_registry} = Registry.unregister(registry, "sub1")
      assert Registry.count(updated_registry) == 0
      assert %Registry{subscriptions: subscriptions} = updated_registry
      assert map_size(subscriptions) == 0
    end

    test "returns error when subscription ID does not exist" do
      registry = Registry.new()

      assert {:error, :not_found} = Registry.unregister(registry, "nonexistent")
    end

    test "unregistering one subscription does not affect others" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})

      {:ok, registry} =
        Registry.register(registry, "sub2", "user.updated", {:http, "http://example.com"})

      assert Registry.count(registry) == 2

      {:ok, registry} = Registry.unregister(registry, "sub1")
      assert Registry.count(registry) == 1

      assert {:ok, _subscription} = Registry.lookup(registry, "sub2")
      assert {:error, :not_found} = Registry.lookup(registry, "sub1")
    end
  end

  describe "lookup/2" do
    test "returns subscription when ID exists" do
      registry = Registry.new()
      dispatch_config = {:pid, self()}
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", dispatch_config)

      assert {:ok, subscription} = Registry.lookup(registry, "sub1")

      assert %Subscription{
               id: "sub1",
               path: "user.created",
               dispatch: ^dispatch_config
             } = subscription
    end

    test "returns error when ID does not exist" do
      registry = Registry.new()

      assert {:error, :not_found} = Registry.lookup(registry, "nonexistent")
    end
  end

  describe "find_by_path/2" do
    test "returns empty list when no subscriptions match" do
      registry = Registry.new()
      assert [] = Registry.find_by_path(registry, "user.created")
    end

    test "returns exact path matches" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})

      {:ok, registry} =
        Registry.register(registry, "sub2", "user.updated", {:http, "http://example.com"})

      subscriptions = Registry.find_by_path(registry, "user.created")
      assert length(subscriptions) == 1
      assert [%Subscription{id: "sub1", path: "user.created"}] = subscriptions
    end

    test "returns multiple subscriptions for same path" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})

      {:ok, registry} =
        Registry.register(registry, "sub2", "user.created", {:http, "http://example.com"})

      subscriptions = Registry.find_by_path(registry, "user.created")
      assert length(subscriptions) == 2
      subscription_ids = Enum.map(subscriptions, & &1.id)
      assert "sub1" in subscription_ids
      assert "sub2" in subscription_ids
    end

    test "returns wildcard pattern matches" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.*", {:pid, self()})

      {:ok, registry} =
        Registry.register(registry, "sub2", "order.created", {:http, "http://example.com"})

      # Should match wildcard pattern
      subscriptions = Registry.find_by_path(registry, "user.created")
      assert length(subscriptions) == 1
      assert [%Subscription{id: "sub1", path: "user.*"}] = subscriptions

      # Should not match
      subscriptions = Registry.find_by_path(registry, "order.updated")
      assert subscriptions == []
    end

    test "handles complex routing patterns" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.**", {:pid, self()})

      {:ok, registry} =
        Registry.register(registry, "sub2", "user.*.profile", {:http, "http://example.com"})

      {:ok, registry} =
        Registry.register(registry, "sub3", "admin.user.created", {:logger, :info})

      # Test deep wildcard
      subscriptions = Registry.find_by_path(registry, "user.123.profile.updated")
      subscription_ids = Enum.map(subscriptions, & &1.id)
      assert "sub1" in subscription_ids

      # Test single segment wildcard
      subscriptions = Registry.find_by_path(registry, "user.123.profile")
      subscription_ids = Enum.map(subscriptions, & &1.id)
      assert "sub1" in subscription_ids
      assert "sub2" in subscription_ids

      # Test exact match
      subscriptions = Registry.find_by_path(registry, "admin.user.created")
      assert [%Subscription{id: "sub3"}] = subscriptions
    end

    test "validates path parameter is binary" do
      registry = Registry.new()
      subscriptions = Registry.find_by_path(registry, "valid.path")
      assert is_list(subscriptions)
    end
  end

  describe "count/1" do
    test "returns 0 for empty registry" do
      registry = Registry.new()
      assert Registry.count(registry) == 0
    end

    test "returns correct count for registry with subscriptions" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})
      assert Registry.count(registry) == 1

      {:ok, registry} =
        Registry.register(registry, "sub2", "user.updated", {:http, "http://example.com"})

      assert Registry.count(registry) == 2

      {:ok, registry} = Registry.unregister(registry, "sub1")
      assert Registry.count(registry) == 1
    end
  end

  describe "all/1" do
    test "returns empty list for empty registry" do
      registry = Registry.new()
      assert Registry.all(registry) == []
    end

    test "returns all subscriptions" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})

      {:ok, registry} =
        Registry.register(registry, "sub2", "user.updated", {:http, "http://example.com"})

      all_subscriptions = Registry.all(registry)
      assert length(all_subscriptions) == 2

      subscription_ids = Enum.map(all_subscriptions, & &1.id)
      assert "sub1" in subscription_ids
      assert "sub2" in subscription_ids
    end

    test "returns subscriptions in consistent order" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})

      {:ok, registry} =
        Registry.register(registry, "sub2", "user.updated", {:http, "http://example.com"})

      all1 = Registry.all(registry)
      all2 = Registry.all(registry)
      assert all1 == all2
    end
  end

  describe "subscription struct" do
    test "has required fields" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})
      {:ok, subscription} = Registry.lookup(registry, "sub1")

      assert %Subscription{
               id: "sub1",
               path: "user.created",
               dispatch: {:pid, _pid},
               created_at: %DateTime{}
             } = subscription

      # Verify created_at is a valid DateTime
      assert DateTime.diff(DateTime.utc_now(), subscription.created_at) >= 0
    end

    test "created_at is set automatically" do
      registry = Registry.new()

      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})
      {:ok, subscription} = Registry.lookup(registry, "sub1")

      # Verify the timestamp is recent (within last 5 seconds)
      now = DateTime.utc_now()
      time_diff_seconds = DateTime.diff(now, subscription.created_at, :second)
      assert time_diff_seconds >= 0
      assert time_diff_seconds <= 5
    end
  end

  describe "dispatch configuration types" do
    test "supports pid dispatch" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:pid, self()})

      {:ok, subscription} = Registry.lookup(registry, "sub1")
      assert {:pid, pid} = subscription.dispatch
      assert is_pid(pid)
    end

    test "supports http dispatch" do
      registry = Registry.new()
      url = "http://example.com/webhook"
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:http, url})

      {:ok, subscription} = Registry.lookup(registry, "sub1")
      assert {:http, ^url} = subscription.dispatch
    end

    test "supports logger dispatch" do
      registry = Registry.new()
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", {:logger, :info})

      {:ok, subscription} = Registry.lookup(registry, "sub1")
      assert {:logger, :info} = subscription.dispatch
    end

    test "supports custom dispatch configuration" do
      registry = Registry.new()
      custom_dispatch = {:custom_adapter, %{endpoint: "tcp://localhost:5000", format: :msgpack}}
      {:ok, registry} = Registry.register(registry, "sub1", "user.created", custom_dispatch)

      {:ok, subscription} = Registry.lookup(registry, "sub1")
      assert ^custom_dispatch = subscription.dispatch
    end
  end

  describe "error cases and edge conditions" do
    test "handles empty string IDs" do
      registry = Registry.new()
      assert {:ok, registry} = Registry.register(registry, "", "user.created", {:pid, self()})
      assert {:ok, _subscription} = Registry.lookup(registry, "")
    end

    test "handles complex path patterns" do
      registry = Registry.new()
      complex_path = "namespace.service.domain.entity.action.version"
      {:ok, registry} = Registry.register(registry, "sub1", complex_path, {:pid, self()})

      subscriptions = Registry.find_by_path(registry, complex_path)
      assert length(subscriptions) == 1
    end

    test "registry operations are immutable" do
      original_registry = Registry.new()

      {:ok, registry_after_register} =
        Registry.register(original_registry, "sub1", "user.created", {:pid, self()})

      # Original registry should be unchanged
      assert Registry.count(original_registry) == 0
      assert Registry.count(registry_after_register) == 1
    end
  end
end
