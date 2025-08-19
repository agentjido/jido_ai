defmodule Jido.AI.TestSupport.KeyringCase do
  @moduledoc """
  ExUnit case template for Keyring-based tests.

  Provides isolated Keyring environment with cleanup and helper macros.
  """

  use ExUnit.CaseTemplate

  alias Jido.AI.Keyring

  using do
    quote do
      import Jido.AI.TestSupport.KeyringCase

      alias Jido.AI.Keyring
    end
  end

  setup _tags do
    # Clear any existing state - Keyring is started by Application
    Keyring.clear_all_session_values()
    Keyring.set_test_env_vars(%{})

    # Auto-cleanup on test exit
    on_exit(fn ->
      Keyring.clear_all_session_values()
      Keyring.set_test_env_vars(%{})
    end)

    :ok
  end

  @doc """
  Sets environment variable for the test with automatic cleanup.

  ## Examples

      env(openai_api_key: "test-key-123") do
        # Test code that expects OPENAI_API_KEY environment variable
      end
  """
  defmacro env(env_vars, do: block) do
    quote do
      # Set new env vars
      env_map =
        unquote(env_vars)
        |> Map.new(fn {key, value} ->
          env_key = key |> Atom.to_string() |> String.upcase()
          {env_key, value}
        end)

      Keyring.set_test_env_vars(env_map)

      try do
        unquote(block)
      after
        # Clear test env vars - they'll be reset by the test setup
        Keyring.set_test_env_vars(%{})
      end
    end
  end

  @doc """
  Sets session value for the test with automatic cleanup.

  ## Examples

      session(openai_api_key: "session-key") do
        # Test code that expects session override
      end
  """
  defmacro session(session_vars, do: block) do
    quote do
      # Save current session values that we'll be changing
      keys_to_change = Keyword.keys(unquote(session_vars))

      previous_values =
        for key <- keys_to_change, into: %{} do
          {key, Keyring.get(key, :__no_value__)}
        end

      # Set new session values
      Enum.each(unquote(session_vars), fn {key, value} ->
        Keyring.set_session_value(key, value)
      end)

      try do
        unquote(block)
      after
        # Restore previous values
        Enum.each(previous_values, fn {key, previous_value} ->
          if previous_value == :__no_value__ do
            # Key didn't exist before, remove it
            Keyring.clear_session_value(key)
          else
            # Restore previous value
            Keyring.set_session_value(key, previous_value)
          end
        end)
      end
    end
  end

  @doc """
  Asserts that Keyring returns the expected value for a key.

  ## Examples

      assert_value(:openai_api_key, "expected-value")
  """
  defmacro assert_value(key, expected_value) do
    quote do
      actual_value = Keyring.get(unquote(key), nil)

      assert actual_value == unquote(expected_value),
             "Expected #{inspect(unquote(key))} to be #{inspect(unquote(expected_value))}, got #{inspect(actual_value)}"
    end
  end

  @doc """
  Asserts that Keyring returns nil (or default) for a key.

  ## Examples

      refute_value(:missing_key)
  """
  defmacro refute_value(key, default \\ nil) do
    quote do
      actual_value = Keyring.get(unquote(key), unquote(default))

      assert actual_value == unquote(default),
             "Expected #{inspect(unquote(key))} to be #{inspect(unquote(default))}, got #{inspect(actual_value)}"
    end
  end
end
