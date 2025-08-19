defmodule Jido.Eval.ConfigTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.{Config, RunConfig}

  describe "struct creation" do
    test "creates with default values" do
      config = %Config{}

      assert config.run_id == nil
      assert %RunConfig{} = config.run_config
      assert config.reporters == [{Jido.Eval.Reporter.Console, []}]
      assert config.stores == []
      assert config.broadcasters == [{Jido.Eval.Broadcaster.Telemetry, [prefix: [:jido, :eval]]}]
      assert config.processors == []
      assert config.middleware == [Jido.Eval.Middleware.Tracing]
      assert config.tags == %{}
      assert config.notes == ""
    end

    test "creates with custom values" do
      run_config = %RunConfig{max_workers: 8}

      config = %Config{
        run_id: "test-run",
        run_config: run_config,
        reporters: [{MyReporter, []}],
        stores: [{MyStore, [path: "/tmp"]}],
        broadcasters: [{MyBroadcaster, []}],
        processors: [{MyProcessor, :pre, []}],
        middleware: [MyMiddleware],
        tags: %{"experiment" => "test"},
        notes: "Test run"
      }

      assert config.run_id == "test-run"
      assert config.run_config == run_config
      assert config.reporters == [{MyReporter, []}]
      assert config.stores == [{MyStore, [path: "/tmp"]}]
      assert config.broadcasters == [{MyBroadcaster, []}]
      assert config.processors == [{MyProcessor, :pre, []}]
      assert config.middleware == [MyMiddleware]
      assert config.tags == %{"experiment" => "test"}
      assert config.notes == "Test run"
    end
  end

  describe "ensure_run_id/1" do
    test "generates UUID when run_id is nil" do
      config = %Config{run_id: nil}

      {:ok, updated_config} = Config.ensure_run_id(config)

      assert is_binary(updated_config.run_id)
      # UUID length
      assert String.length(updated_config.run_id) == 36
      assert updated_config.run_config.run_id == updated_config.run_id
    end

    test "preserves existing run_id" do
      config = %Config{run_id: "existing-id"}

      {:ok, updated_config} = Config.ensure_run_id(config)

      assert updated_config.run_id == "existing-id"
      assert updated_config.run_config.run_id == "existing-id"
    end

    test "syncs run_id between config and run_config" do
      config = %Config{
        run_id: "test-id",
        run_config: %RunConfig{run_id: nil}
      }

      {:ok, updated_config} = Config.ensure_run_id(config)

      assert updated_config.run_id == "test-id"
      assert updated_config.run_config.run_id == "test-id"
    end
  end

  describe "doctests" do
    doctest Config
  end
end
