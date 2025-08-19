defmodule SparqTest.RoundtripCase do
  @moduledoc """
  Provides assertion helpers for testing parser roundtrips (parse -> format -> compare).

  ## Examples

      use RoundtripCase

      test "simple roundtrip" do
        assert_roundtrip("x = 1")
      end

      test "roundtrip with token validation" do
        assert_roundtrip "x = 1", fn tokens ->
          assert Enum.any?(tokens, &match?({:identifier, [], :x}, &1))
        end
      end
  """

  # Import ExUnit assertions
  import ExUnit.Assertions
  alias Sparq.Parser

  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case
      import SparqTest.RoundtripCase
    end
  end

  @doc """
  Asserts that parsing and then formatting a string results in the same string.
  Optionally accepts a function to validate the parsed tokens.

  ## Examples

      assert_roundtrip("x = 1")
      assert_roundtrip "x = 1", &validate_tokens/1
  """
  def assert_roundtrip(input, token_validator \\ fn _ -> :ok end) do
    case Parser.parse(input) do
      {:ok, tokens} ->
        # Run the optional token validation
        token_validator.(tokens)

        # Format tokens back to string
        formatted = Parser.format(tokens)

        if formatted != input do
          flunk("""
          Roundtrip failed!

          Input:
          #{inspect(input)}

          Parsed tokens:
          #{Parser.debug_format(tokens)}

          Formatted output:
          #{inspect(formatted)}
          """)
        end

      {:error, reason} ->
        flunk("""
        Failed to parse input!

        Input:
        #{inspect(input)}

        Error:
        #{inspect(reason)}
        """)
    end
  end
end
