defmodule Jido.AI.ReqLlmBridge.SessionAuthenticationTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Jido.AI.Keyring
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  setup do
    # Start a unique Keyring for testing
    test_keyring_name = :"test_keyring_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Keyring.start_link(name: test_keyring_name)

    on_exit(fn ->
      try do
        GenServer.stop(test_keyring_name)
      catch
        :exit, _ -> :ok
      end
    end)

    %{keyring: test_keyring_name}
  end

  describe "get_for_request/3 - session authentication for requests" do
    test "returns session_auth when session key exists", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "session-key")

      assert {:session_auth, options} =
               SessionAuthentication.get_for_request(:openai, %{})

      assert options[:api_key] == "session-key"
    end

    test "returns no_session_auth when no session key", %{keyring: _keyring} do
      SessionAuthentication.clear_for_provider(:openai)

      assert {:no_session_auth} =
               SessionAuthentication.get_for_request(:openai, %{})
    end

    test "session key overrides request options", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "session-key")

      existing_options = %{api_key: "request-key", other: "value"}

      {:session_auth, options} =
        SessionAuthentication.get_for_request(:openai, existing_options)

      assert options[:api_key] == "session-key"
      assert options[:other] == "value"
    end
  end

  describe "set_for_provider/3 - setting session authentication" do
    test "sets session key for provider", %{keyring: _keyring} do
      assert :ok = SessionAuthentication.set_for_provider(:openai, "test-key")

      {:session_auth, options} =
        SessionAuthentication.get_for_request(:openai, %{})

      assert options[:api_key] == "test-key"
    end

    test "updates existing session key", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "old-key")
      SessionAuthentication.set_for_provider(:openai, "new-key")

      {:session_auth, options} =
        SessionAuthentication.get_for_request(:openai, %{})

      assert options[:api_key] == "new-key"
    end

    test "sets different keys for different providers", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "openai-key")
      SessionAuthentication.set_for_provider(:anthropic, "anthropic-key")

      {:session_auth, openai_opts} =
        SessionAuthentication.get_for_request(:openai, %{})

      {:session_auth, anthropic_opts} =
        SessionAuthentication.get_for_request(:anthropic, %{})

      assert openai_opts[:api_key] == "openai-key"
      assert anthropic_opts[:api_key] == "anthropic-key"
    end
  end

  describe "clear_for_provider/2 - clearing session authentication" do
    test "clears session key for provider", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "test-key")
      assert :ok = SessionAuthentication.clear_for_provider(:openai)

      assert {:no_session_auth} =
               SessionAuthentication.get_for_request(:openai, %{})
    end

    test "clearing non-existent key succeeds", %{keyring: _keyring} do
      assert :ok = SessionAuthentication.clear_for_provider(:nonexistent)
    end
  end

  describe "has_session_auth?/2 - checking session authentication" do
    test "returns true when session auth exists", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "key")
      assert SessionAuthentication.has_session_auth?(:openai)
    end

    test "returns false when no session auth", %{keyring: _keyring} do
      SessionAuthentication.clear_for_provider(:openai)
      refute SessionAuthentication.has_session_auth?(:openai)
    end
  end

  describe "list_providers_with_auth/1 - listing authenticated providers" do
    test "returns empty list when no auth set", %{keyring: _keyring} do
      assert [] = SessionAuthentication.list_providers_with_auth()
    end

    test "returns list of providers with auth", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "key1")
      SessionAuthentication.set_for_provider(:anthropic, "key2")

      providers = SessionAuthentication.list_providers_with_auth()
      assert :openai in providers
      assert :anthropic in providers
      assert length(providers) == 2
    end
  end

  describe "clear_all/1 - clearing all session authentication" do
    test "clears all provider authentication", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "key1")
      SessionAuthentication.set_for_provider(:anthropic, "key2")
      SessionAuthentication.set_for_provider(:google, "key3")

      assert :ok = SessionAuthentication.clear_all()

      assert [] = SessionAuthentication.list_providers_with_auth()
    end
  end

  describe "transfer/3 - transferring authentication between processes" do
    test "transfers authentication to another process", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "transfer-key")

      # Create a target process
      {:ok, target_pid} =
        Task.start(fn ->
          receive do
            :check ->
              result = SessionAuthentication.has_session_auth?(:openai)
              send(self(), {:result, result})
          end

          receive do
            :stop -> :ok
          end
        end)

      # Transfer should succeed
      assert :ok = SessionAuthentication.transfer(:openai, self(), target_pid)

      # Verify target has the auth
      send(target_pid, :check)
      assert_receive {:result, true}, 1000

      # Clean up
      send(target_pid, :stop)
    end

    test "returns error when no auth to transfer", %{keyring: _keyring} do
      SessionAuthentication.clear_for_provider(:openai)

      {:ok, target_pid} =
        Task.start(fn ->
          receive do
            :stop -> :ok
          end
        end)

      assert {:error, :no_auth} =
               SessionAuthentication.transfer(:openai, self(), target_pid)

      send(target_pid, :stop)
    end
  end

  describe "inherit_from/2 - inheriting authentication from parent" do
    test "inherits all authentication from parent process", %{keyring: _keyring} do
      # Set up parent authentication
      SessionAuthentication.set_for_provider(:openai, "parent-key1")
      SessionAuthentication.set_for_provider(:anthropic, "parent-key2")

      parent_pid = self()

      # Create child process and inherit
      task =
        Task.async(fn ->
          inherited = SessionAuthentication.inherit_from(parent_pid)

          # Check inherited providers
          assert :openai in inherited
          assert :anthropic in inherited

          # Verify keys were inherited
          {:session_auth, openai_opts} =
            SessionAuthentication.get_for_request(:openai, %{})

          {:session_auth, anthropic_opts} =
            SessionAuthentication.get_for_request(:anthropic, %{})

          {openai_opts[:api_key], anthropic_opts[:api_key]}
        end)

      {openai_key, anthropic_key} = Task.await(task)
      assert openai_key == "parent-key1"
      assert anthropic_key == "parent-key2"
    end

    test "returns empty list when parent has no auth", %{keyring: _keyring} do
      SessionAuthentication.clear_all()

      parent_pid = self()

      task =
        Task.async(fn ->
          SessionAuthentication.inherit_from(parent_pid)
        end)

      inherited = Task.await(task)
      assert inherited == []
    end
  end

  describe "process isolation" do
    test "session auth is isolated per process", %{keyring: _keyring} do
      # Set in main process
      SessionAuthentication.set_for_provider(:openai, "main-key")

      # Check in another process
      task =
        Task.async(fn ->
          # Should not see main process's auth
          has_auth_before = SessionAuthentication.has_session_auth?(:openai)

          # Set different auth in this process
          SessionAuthentication.set_for_provider(:openai, "task-key")

          # Should see own auth
          {:session_auth, opts} =
            SessionAuthentication.get_for_request(:openai, %{})

          {has_auth_before, opts[:api_key]}
        end)

      {has_auth_before, task_key} = Task.await(task)
      assert has_auth_before == false
      assert task_key == "task-key"

      # Main process should still have its own auth
      {:session_auth, main_opts} =
        SessionAuthentication.get_for_request(:openai, %{})

      assert main_opts[:api_key] == "main-key"
    end

    test "clearing in one process doesn't affect another", %{keyring: _keyring} do
      SessionAuthentication.set_for_provider(:openai, "main-key")

      task =
        Task.async(fn ->
          # Set and then clear in task process
          SessionAuthentication.set_for_provider(:openai, "task-key")
          SessionAuthentication.clear_for_provider(:openai)

          SessionAuthentication.has_session_auth?(:openai)
        end)

      task_has_auth = Task.await(task)
      assert task_has_auth == false

      # Main process should still have auth
      assert SessionAuthentication.has_session_auth?(:openai)
    end
  end
end
