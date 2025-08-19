defmodule Jido.AI.TestMacros do
  @moduledoc """
  Macros for table-driven testing and common test patterns.

  Provides `table_test/3` macro for generating multiple test cases from data tables
  while maintaining clear test names and isolated execution.
  """

  defmacro __using__(_opts) do
    quote do
      import Jido.AI.TestMacros
    end
  end

  @doc """
  Generates individual test cases from a data table.

  Creates a separate ExUnit test for each row in the table, maintaining
  clear test names and isolated execution. Supports various data formats.

  ## Examples

      # Simple list format
      table_test "validates input types", [123, [], nil], fn input ->
        assert {:error, _} = SomeModule.validate(input)
      end

      # Keyword list format with custom names
      table_test "handles HTTP status codes", [
        ok: {200, :success},
        not_found: {404, :error},
        server_error: {500, :error}
      ], fn {status, expected_result} ->
        assert expected_result == handle_status(status)
      end

      # Map format for complex test data
      table_test "provider error handling", [
        %{name: "timeout", status: 408, body: %{"error" => "timeout"}},
        %{name: "rate_limit", status: 429, body: %{"error" => "rate limited"}}
      ], fn test_case ->
        response = %Req.Response{status: test_case.status, body: test_case.body}
        assert {:error, _} = Provider.handle_response(response)
      end
  """
  defmacro table_test(description, test_data, test_body) do
    test_cases = generate_test_cases(description, test_data, test_body)

    quote do
      (unquote_splicing(test_cases))
    end
  end

  # Generate individual test cases based on data format
  defp generate_test_cases(base_description, test_data_ast, test_body) do
    case test_data_ast do
      # Handle literal lists at compile time
      items when is_list(items) ->
        Enum.with_index(items, 1)
        |> Enum.map(fn {item, index} ->
          test_name = generate_test_name(base_description, item, index)
          generate_single_test(test_name, item, test_body)
        end)

      # Handle runtime expressions - delegate to runtime generation
      _ ->
        [
          quote do
            for {item, index} <- Enum.with_index(unquote(test_data_ast), 1) do
              test_name =
                case item do
                  {key, _value} when is_atom(key) ->
                    "#{unquote(base_description)} (#{key})"

                  %{name: name} ->
                    "#{unquote(base_description)} (#{name})"

                  value when is_atom(value) or is_binary(value) or is_number(value) ->
                    short_value = value |> to_string() |> String.slice(0, 20)
                    "#{unquote(base_description)} (#{short_value})"

                  _ ->
                    "#{unquote(base_description)} (case #{index})"
                end

              test test_name do
                unquote(test_body).(item)
              end
            end
          end
        ]
    end
  end

  # Generate a descriptive test name based on the test data
  defp generate_test_name(base_description, item, index) do
    case item do
      # Keyword list format: use the key as part of name
      {key, _value} when is_atom(key) ->
        "#{base_description} (#{key})"

      # Map with :name field: use name for clarity
      %{name: name} ->
        "#{base_description} (#{name})"

      # Simple values: include the value if it's short and readable
      value when is_atom(value) or is_binary(value) or is_number(value) ->
        short_value = value |> to_string() |> String.slice(0, 20)
        "#{base_description} (#{short_value})"

      # Complex values: use index
      _ ->
        "#{base_description} (case #{index})"
    end
  end

  # Generate a single test case
  defp generate_single_test(test_name, test_item, test_body) do
    quote do
      test unquote(test_name) do
        unquote(test_body).(unquote(Macro.escape(test_item)))
      end
    end
  end
end
