defmodule ReqAI.Test.Macros do
  @moduledoc """
  Test utility macros and helper functions for ReqAI testing.

  Provides macros for parameterized testing, scenario-based testing,
  and common assertion patterns to improve test readability and reduce duplication.
  """

  @doc """
  Creates parameterized tests that run the same test logic with multiple data sets.

  ## Examples

      defmodule MyTest do
        use ExUnit.Case
        import ReqAI.Test.Macros

        parameterized_test "validates input", [
          {"valid string", "hello", true},
          {"empty string", "", false},
          {"nil input", nil, false}
        ], fn {description, input, expected} ->
          assert MyModule.valid?(input) == expected
        end
      end

  """
  defmacro parameterized_test(description, test_cases, test_body) do
    for {case_name, data, expected} <- test_cases do
      test_name = "#{description} - #{case_name}"

      quote do
        test unquote(test_name) do
          case_data = {unquote(case_name), unquote(data), unquote(expected)}
          unquote(test_body).(case_data)
        end
      end
    end
  end

  @doc """
  Creates tests for multiple scenarios using a shared setup and assertion pattern.

  ## Examples

      defmodule MyTest do
        use ExUnit.Case
        import ReqAI.Test.Macros

        with_cases "message validation", %{
          "user message" => %{role: :user, content: "hello"},
          "system message" => %{role: :system, content: "you are helpful"},
          "empty content" => %{role: :user, content: "", expected: :error}
        }, fn scenario_name, data ->
          message = Message.new(data.role, data.content)
          expected = Map.get(data, :expected, :ok)

          case expected do
            :ok -> assert Message.valid?(message)
            :error -> refute Message.valid?(message)
          end
        end
      end

  """
  defmacro with_cases(description, scenarios, test_body) do
    for {scenario_name, scenario_data} <- scenarios do
      test_name = "#{description} - #{scenario_name}"

      quote do
        test unquote(test_name) do
          unquote(test_body).(unquote(scenario_name), unquote(scenario_data))
        end
      end
    end
  end

  @doc """
  Asserts that a function returns an ok tuple with expected value.

  ## Examples

      iex> assert_ok({:ok, "result"}, "result")
      "result"

      iex> assert_ok({:error, "failed"})
      # Raises assertion error

  """
  defmacro assert_ok(expr) do
    quote do
      result = unquote(expr)

      case result do
        {:ok, value} ->
          value

        {:error, reason} ->
          flunk("Expected {:ok, _}, got {:error, #{inspect(reason)}}")

        other ->
          flunk("Expected {:ok, _}, got #{inspect(other)}")
      end
    end
  end

  defmacro assert_ok(expr, expected) do
    quote do
      result = unquote(expr)

      case result do
        {:ok, value} ->
          assert value == unquote(expected)
          value

        {:error, reason} ->
          flunk("Expected {:ok, _}, got {:error, #{inspect(reason)}}")

        other ->
          flunk("Expected {:ok, _}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts that a function returns an error tuple with optional reason check.

  ## Examples

      iex> assert_error({:error, "invalid"})
      "invalid"

      iex> assert_error({:error, "invalid"}, "invalid")
      "invalid"

  """
  defmacro assert_error(expr, expected_reason \\ nil) do
    quote do
      result = unquote(expr)

      case result do
        {:error, reason} ->
          if unquote(expected_reason) do
            assert reason == unquote(expected_reason)
          end

          reason

        {:ok, value} ->
          flunk("Expected {:error, _}, got {:ok, #{inspect(value)}}")

        other ->
          flunk("Expected {:error, _}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts that a struct has the expected fields and values.

  ## Examples

      iex> message = %Message{role: :user, content: "hello"}
      iex> assert_struct(message, Message, role: :user, content: "hello")
      %Message{role: :user, content: "hello"}

  """
  defmacro assert_struct(expr, expected_type, expected_fields \\ []) do
    quote do
      result = unquote(expr)

      assert %unquote(expected_type){} = result

      for {field, expected_value} <- unquote(expected_fields) do
        actual_value = Map.get(result, field)

        assert actual_value == expected_value,
               "Expected #{field} to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
      end

      result
    end
  end

  @doc """
  Asserts that a list contains items matching the given patterns.

  ## Examples

      iex> messages = [%Message{role: :user}, %Message{role: :assistant}]
      iex> assert_list_contains(messages, [
      ...>   %{role: :user},
      ...>   %{role: :assistant}
      ...> ])

  """
  defmacro assert_list_contains(list_expr, patterns) do
    quote do
      list = unquote(list_expr)
      patterns = unquote(patterns)

      assert is_list(list), "Expected a list, got #{inspect(list)}"

      assert length(list) >= length(patterns),
             "List has #{length(list)} items, but #{length(patterns)} patterns provided"

      Enum.zip(list, patterns)
      |> Enum.each(fn {item, pattern} ->
        assert_match(item, pattern)
      end)

      list
    end
  end

  @doc """
  Asserts that an item matches a pattern using pattern matching.

  ## Examples

      iex> assert_match(%Message{role: :user}, %{role: :user})

  """
  defmacro assert_match(expr, pattern) do
    quote do
      item = unquote(expr)
      pattern = unquote(pattern)

      cond do
        is_map(pattern) ->
          Enum.each(pattern, fn {key, expected_value} ->
            actual_value = Map.get(item, key)

            assert actual_value == expected_value,
                   "Expected #{key} to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
          end)

        true ->
          assert item == pattern
      end

      item
    end
  end

  @doc """
  Creates a temporary file with given content for testing.

  ## Examples

      iex> with_temp_file("test content", fn path ->
      ...>   content = File.read!(path)
      ...>   assert content == "test content"
      ...> end)

  """
  @spec with_temp_file(String.t(), (String.t() -> any())) :: any()
  def with_temp_file(content, fun) do
    temp_file = System.tmp_dir!() |> Path.join("req_ai_test_#{:rand.uniform(1_000_000)}")

    try do
      File.write!(temp_file, content)
      fun.(temp_file)
    after
      File.rm(temp_file)
    end
  end

  @doc """
  Captures ExUnit output for testing logging and IO operations.

  ## Examples

      iex> {result, output} = capture_output(fn ->
      ...>   IO.puts("test output")
      ...>   :result
      ...> end)
      iex> assert result == :result
      iex> assert output =~ "test output"

  """
  @spec capture_output((-> any())) :: {any(), String.t()}
  def capture_output(fun) do
    ExUnit.CaptureIO.capture_io(fn ->
      result = fun.()
      {result, :captured}
    end)
    |> case do
      {result, :captured} ->
        # If we're here, the function returned normally
        output = ExUnit.CaptureIO.capture_io(fn -> nil end)
        {result, output || ""}

      output when is_binary(output) ->
        # The function itself produced output
        {:ok, output}
    end
  end

  @doc """
  Asserts that a function raises an exception with the expected message.

  ## Examples

      iex> assert_raises_with_message(ArgumentError, "invalid input", fn ->
      ...>   raise ArgumentError, "invalid input"
      ...> end)

  """
  defmacro assert_raises_with_message(expected_exception, expected_message, fun) do
    quote do
      exception = assert_raise unquote(expected_exception), unquote(fun)
      assert Exception.message(exception) == unquote(expected_message)
      exception
    end
  end

  @doc """
  Retries a test assertion with exponential backoff for async operations.

  ## Examples

      iex> eventually(fn ->
      ...>   assert some_async_condition()
      ...> end, timeout: 5000, interval: 100)

  """
  @spec eventually((-> any()), keyword()) :: any()
  def eventually(assertion_fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 50)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_eventually(assertion_fun, deadline, interval)
  end

  defp do_eventually(assertion_fun, deadline, interval) do
    try do
      assertion_fun.()
    rescue
      error ->
        now = System.monotonic_time(:millisecond)

        if now >= deadline do
          reraise error, __STACKTRACE__
        else
          Process.sleep(interval)
          do_eventually(assertion_fun, deadline, interval)
        end
    end
  end

  @doc """
  Generates a unique test identifier for isolating test data.

  ## Examples

      iex> id = test_id()
      iex> assert String.length(id) > 0

  """
  @spec test_id() :: String.t()
  def test_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Creates test configuration with common settings.

  ## Examples

      iex> config = test_config(temperature: 0.5)
      iex> assert config.temperature == 0.5

  """
  @spec test_config(keyword()) :: map()
  def test_config(opts \\ []) do
    %{
      temperature: Keyword.get(opts, :temperature, 0.0),
      max_tokens: Keyword.get(opts, :max_tokens, 100),
      timeout: Keyword.get(opts, :timeout, 5000),
      retries: Keyword.get(opts, :retries, 0)
    }
  end

  @doc """
  Mocks a provider response for testing.

  ## Examples

      iex> mock_response(%{content: "Hello", usage: %{tokens: 10}})
      %{body: %{content: "Hello", usage: %{tokens: 10}}, status: 200}

  """
  @spec mock_response(map(), keyword()) :: map()
  def mock_response(content, opts \\ []) do
    %{
      status: Keyword.get(opts, :status, 200),
      headers: Keyword.get(opts, :headers, %{}),
      body: content
    }
  end
end
