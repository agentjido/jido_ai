# defmodule ReqLLM.Capability.ReporterTest do
#   use ExUnit.Case, async: false
#   use Mimic

#   alias ReqLLM.Capability.Reporter
#   alias ReqLLM.Capability.Result

#   copy Jason
#   copy IO

#   setup :verify_on_exit!
#   setup :set_mimic_global

#   describe "dispatch/2" do
#     test "defaults to pretty format" do
#       results = [
#         Result.passed("openai:gpt-4", :generate_text, 150, "success")
#       ]

#       IO
#       |> expect(:puts, fn output ->
#         assert output =~ "✓"
#         assert output =~ "openai:gpt-4"
#         assert output =~ "generate_text"
#         assert output =~ "(150ms)"
#         :ok
#       end)

#       assert Reporter.dispatch(results, []) == :ok
#     end

#     test "uses specified format" do
#       results = [
#         Result.passed("openai:gpt-4", :generate_text, 150, "success")
#       ]

#       Jason
#       |> expect(:encode!, fn result ->
#         assert result.model == "openai:gpt-4"
#         ~s({"model":"openai:gpt-4"})
#       end)

#       IO
#       |> expect(:puts, fn json_string ->
#         assert json_string == ~s({"model":"openai:gpt-4"})
#         :ok
#       end)

#       assert Reporter.dispatch(results, format: :json) == :ok
#     end
#   end

#   describe "output_json/1" do
#     test "outputs each result as JSON line" do
#       results = [
#         Result.passed("openai:gpt-4", :generate_text, 150, "success"),
#         Result.failed("anthropic:claude", :tool_calling, 250, "error")
#       ]

#       Jason
#       |> expect(:encode!, fn result ->
#         case result.model do
#           "anthropic:claude" -> ~s({"model":"anthropic:claude","status":"failed"})
#           "openai:gpt-4" -> ~s({"model":"openai:gpt-4","status":"passed"})
#         end
#       end)
#       |> expect(:encode!, fn result ->
#         case result.model do
#           "anthropic:claude" -> ~s({"model":"anthropic:claude","status":"failed"})
#           "openai:gpt-4" -> ~s({"model":"openai:gpt-4","status":"passed"})
#         end
#       end)

#       IO
#       |> expect(:puts, fn json -> assert json =~ "failed"; :ok end)
#       |> expect(:puts, fn json -> assert json =~ "passed"; :ok end)

#       assert Reporter.output_json(results) == :ok
#     end
#   end

#   describe "output_pretty/1" do
#     test "outputs formatted results with icons and timing" do
#       results = [
#         Result.passed("openai:gpt-4", :generate_text, 150),
#         Result.failed("anthropic:claude", :tool_calling, 2500, "timeout")
#       ]

#       IO
#       |> expect(:puts, fn output ->
#         assert output =~ "✗"
#         assert output =~ "anthropic:claude"
#         assert output =~ "tool_calling"
#         assert output =~ "(2.5s)"
#         :ok
#       end)
#       |> expect(:puts, fn output ->
#         assert output =~ "✓"
#         assert output =~ "openai:gpt-4"
#         assert output =~ "generate_text"
#         assert output =~ "(150ms)"
#         :ok
#       end)

#       assert Reporter.output_pretty(results) == :ok
#     end

#     test "handles timing display correctly" do
#       results = [
#         Result.passed("test:model", :test_cap, 500),
#         Result.passed("test:model", :test_cap, 1500)
#       ]

#       IO
#       |> expect(:puts, fn output ->
#         assert output =~ "(1.5s)"
#         :ok
#       end)
#       |> expect(:puts, fn output ->
#         assert output =~ "(500ms)"
#         :ok
#       end)

#       assert Reporter.output_pretty(results) == :ok
#     end
#   end

#   describe "output_debug/1" do
#     test "shows detailed error information for failed results" do
#       results = [
#         Result.passed("openai:gpt-4", :generate_text, 150),
#         Result.failed("anthropic:claude", :tool_calling, 250, {:error, "Schema validation failed"})
#       ]

#       IO
#       |> expect(:puts, fn output ->
#         assert output =~ "✗"
#         assert output =~ "anthropic:claude"
#         :ok
#       end)
#       |> expect(:puts, fn error_output ->
#         assert error_output =~ "Error:"
#         assert error_output =~ "Schema validation failed"
#         :ok
#       end)
#       |> expect(:puts, fn output ->
#         assert output =~ "✓"
#         assert output =~ "openai:gpt-4"
#         :ok
#       end)

#       assert Reporter.output_debug(results) == :ok
#     end

#     test "does not show error details for passed results in debug mode" do
#       results = [
#         Result.passed("openai:gpt-4", :generate_text, 150, "success details")
#       ]

#       IO
#       |> expect(:puts, 1, fn output ->
#         assert output =~ "✓"
#         refute output =~ "Error:"
#         :ok
#       end)

#       assert Reporter.output_debug(results) == :ok
#     end
#   end
# end
