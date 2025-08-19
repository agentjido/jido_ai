defmodule Jido.AI.Provider.RegistryTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Provider.Registry

  # Registry key constant
  @registry_key {Registry, :providers}

  setup do
    # Clear registry state before each test
    :persistent_term.erase(@registry_key)
    on_exit(fn -> :persistent_term.erase(@registry_key) end)
    :ok
  end

  describe "clear/0" do
    test "clears registry" do
      :persistent_term.put(@registry_key, %{test: TestProvider})
      assert Registry.clear() == :ok
      assert :persistent_term.get(@registry_key, %{}) == %{}
    end
  end

  describe "register/2" do
    test "registers and manages providers" do
      # Single registration
      assert Registry.register(:openai, TestOpenAI) == :ok
      registry = :persistent_term.get(@registry_key, %{})
      assert registry[:openai] == TestOpenAI

      # Multiple registrations
      assert Registry.register(:anthropic, TestAnthropic) == :ok
      registry = :persistent_term.get(@registry_key, %{})
      assert registry[:anthropic] == TestAnthropic

      # Idempotent with same parameters
      assert Registry.register(:openai, TestOpenAI) == :ok

      # Error on overwrite with different module
      result = Registry.register(:openai, TestOpenAIV2)
      assert {:error, {:already_registered, TestOpenAI}} = result
    end
  end

  describe "list_providers/0" do
    test "lists providers correctly" do
      # Empty registry
      assert Registry.list_providers() == []

      # Single provider
      Registry.register(:openai, TestOpenAI)
      assert Registry.list_providers() == [:openai]

      # Multiple providers
      Registry.register(:anthropic, TestAnthropic)
      providers = Registry.list_providers()
      assert length(providers) == 2
      assert :openai in providers
      assert :anthropic in providers

      # After clear
      Registry.clear()
      assert Registry.list_providers() == []
    end
  end

  describe "provider lookup" do
    test "fetch/1 and fetch!/1 work correctly" do
      # Not found
      assert {:error, :not_found} = Registry.fetch(:nonexistent)

      assert_raise RuntimeError, "Provider not found: :nonexistent", fn ->
        Registry.fetch!(:nonexistent)
      end

      # Found
      Registry.register(:openai, TestOpenAI)
      assert {:ok, TestOpenAI} = Registry.fetch(:openai)
      assert TestOpenAI = Registry.fetch!(:openai)
    end

    test "get_provider/1 (deprecated) works correctly" do
      # Not found
      assert {:error, %Parameter{}} = Registry.get_provider(:nonexistent)

      # Found
      Registry.register(:openai, TestOpenAI)
      assert {:ok, TestOpenAI} = Registry.get_provider(:openai)
    end
  end

  describe "initialize/0" do
    test "initializes and reloads correctly" do
      Registry.clear()
      assert Registry.initialize() == :ok
      assert is_list(Registry.list_providers())

      # Reload is idempotent
      assert Registry.reload() == :ok
    end
  end

  describe "edge cases" do
    test "only accepts atom provider IDs" do
      Registry.register(:openai, TestOpenAI)

      # String keys should cause function clause error
      assert_raise FunctionClauseError, fn ->
        Registry.register("anthropic", TestAnthropic)
      end

      assert {:ok, TestOpenAI} = Registry.get_provider(:openai)
      assert {:error, _} = Registry.get_provider("openai")
    end
  end

  # Test modules
  defmodule TestOpenAI, do: nil
  defmodule TestOpenAIV2, do: nil
  defmodule TestAnthropic, do: nil
  defmodule TestProvider, do: nil
end
