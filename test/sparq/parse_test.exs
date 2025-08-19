# defmodule SayCommandTest do
#   use ExUnit.Case

#   defmodule SayParser do
#     import NimbleParsec

#     # Basic elements
#     whitespace = ascii_string([?\s], min: 1)
#     quote_mark = string("\"")
#     string_content = ascii_string([not: ?", not: ?\n], min: 1)
#     newline = string("\n")

#     # Say command

#     say_command =
#       string("say")
#       |> concat(whitespace)
#       |> concat(quote_mark)
#       |> concat(string_content)
#       |> concat(quote_mark)
#       |> wrap()
#       |> map(:build_say_command)

#     narrate_command =
#       string("narrate")
#       |> concat(whitespace)
#       |> concat(quote_mark)
#       |> concat(string_content)
#       |> concat(quote_mark)
#       |> wrap()
#       |> map(:build_narrate_command)

#     # Elixir block
#     elixir_start = string("elixir do")
#     elixir_end = string("end")

#     elixir_content =
#       times(
#         choice([
#           ascii_string([not: ?e, not: ?\n], min: 1),
#           string("\n")
#         ]),
#         min: 1
#       )
#       |> reduce({Enum, :join, [""]})

#     elixir_block =
#       elixir_start
#       |> concat(newline)
#       |> concat(elixir_content)
#       |> concat(elixir_end)
#       |> wrap()
#       |> map(:build_elixir_block)

#     # Combined command
#     single_command =
#       choice([
#         say_command,
#         narrate_command,
#         elixir_block
#       ])

#     # Modified commands parser to handle multiple newlines
#     commands =
#       single_command
#       |> repeat(
#         times(newline, min: 1)
#         |> ignore()
#         |> concat(single_command)
#       )

#     defp build_say_command([_action, _space, _quote1, content, _quote2]) do
#       {:say, :context, content}
#     end

#     defp build_narrate_command([_action, _space, _quote1, content, _quote2]) do
#       {:narrate, :context, content}
#     end

#     defp build_elixir_block([_start, _newline, content, _end]) do
#       {:elixir, :context, content}
#     end

#     defparsecp(:parse_commands, commands)

#     def parse(input) do
#       case parse_commands(input) do
#         {:ok, results, "", _, _, _} ->
#           {:ok, results}

#         # Handle trailing newlines more gracefully
#         {:ok, results, rest, _, _, _} when rest in ["\n", "\n\n", ""] ->
#           {:ok, results}

#         {:ok, results, rest, _, _, _} ->
#           # Try to parse remaining content
#           case parse_commands(rest) do
#             {:ok, more_results, final_rest, _, _, _} when final_rest in ["\n", "\n\n", ""] ->
#               {:ok, results ++ more_results}

#             _ ->
#               {:error, :parse_failed}
#           end

#         {:error, _, _, _, {line, col}, offset} ->
#           {:error, {{line, col}, offset}, :parse_failed}
#       end
#     end
#   end

#   describe "NimbleParsec parser" do
#     test "parses single say command" do
#       assert {:ok, [{:say, :context, "hello world"}]} ==
#                SayParser.parse(~s{say "hello world"})
#     end

#     test "parses single narrate command" do
#       assert {:ok, [{:narrate, :context, "testing narration"}]} ==
#                SayParser.parse(~s{narrate "testing narration"})
#     end

#     test "parses elixir block" do
#       input = """
#       elixir do
#         1 + 1
#       end
#       """

#       assert {:ok, [{:elixir, :context, "  1 + 1\n"}]} = SayParser.parse(input)
#     end

#     test "parses mixed commands" do
#       input = """
#       say "hello world"
#       narrate "test story"
#       elixir do
#         1 + 1
#       end
#       say "goodbye world"
#       """

#       expected = [
#         {:say, :context, "hello world"},
#         {:narrate, :context, "test story"},
#         {:elixir, :context, "  1 + 1\n"},
#         {:say, :context, "goodbye world"}
#       ]

#       assert {:ok, ^expected} = SayParser.parse(input)
#     end
#   end

#   describe "benchmarks" do
#     test "benchmark 10,000 mixed commands" do
#       commands =
#         for i <- 1..10 do
#           case rem(i, 3) do
#             0 ->
#               ~s{say "message number #{i}"}

#             1 ->
#               ~s{narrate "test story #{i}"}

#             2 ->
#               """
#               elixir do
#                 #{i} + 1
#               end
#               """
#           end
#         end

#       input = Enum.join(commands, "\n")
#       IO.puts("\nStarting benchmarks for 10,000 mixed commands...")

#       {nimble_time, nimble_result} =
#         :timer.tc(fn ->
#           SayParser.parse(input)
#         end)

#       IO.puts("""
#       Results:
#         NimbleParsec:      #{nimble_time} microseconds
#       Parse Success: #{match?({:ok, _}, nimble_result)}
#       """)

#       assert match?({:ok, _}, nimble_result)
#       {:ok, nimble_commands} = nimble_result
#       assert length(nimble_commands) == 10
#     end
#   end
# end
