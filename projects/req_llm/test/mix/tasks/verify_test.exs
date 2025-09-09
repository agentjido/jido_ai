# defmodule Mix.Tasks.ReqLlm.VerifyTest do
#   use ExUnit.Case, async: false
#   use Mimic

#   alias Mix.Tasks.ReqLlm.Verify

#   setup :verify_on_exit!
#   setup :set_mimic_global

#   setup do
#     # Capture original shell and restore after test
#     original_shell = Mix.shell()

#     on_exit(fn ->
#       Mix.shell(original_shell)
#     end)

#     :ok
#   end

#   describe "run/1" do
#     test "verifies single model successfully" do
#       Mix.Task
#       |> expect(:run, fn "app.start" -> :ok end)

#       ReqLLM.Capability
#       |> expect(:verify, fn "openai:gpt-4", [] -> :ok end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["openai:gpt-4"])

#       assert_received {:mix_shell, :info, ["✅ All capabilities verified successfully"]}
#     end

#     test "handles model verification failure" do
#       Mix.Task
#       |> expect(:run, fn "app.start" -> :ok end)

#       ReqLLM.Capability
#       |> expect(:verify, fn "invalid:model", [] -> :error end)

#       System
#       |> expect(:halt, fn 1 -> send(self(), :system_halt) end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["invalid:model"])

#       assert_received :system_halt
#       assert_received {:mix_shell, :error, ["❌ One or more capabilities failed verification"]}
#     end

#     test "passes timeout option to verification" do
#       Mix.Task
#       |> expect(:run, fn "app.start" -> :ok end)

#       ReqLLM.Capability
#       |> expect(:verify, fn "openai:gpt-4", opts ->
#         assert opts[:timeout] == 30000
#         :ok
#       end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["openai:gpt-4", "--timeout", "30000"])

#       assert_received {:mix_shell, :info, ["✅ All capabilities verified successfully"]}
#     end

#     test "passes only option as list to verification" do
#       Mix.Task
#       |> expect(:run, fn "app.start" -> :ok end)

#       ReqLLM.Capability
#       |> expect(:verify, fn "openai:gpt-4", opts ->
#         assert opts[:only] == ["generate_text", "tool_calling"]
#         :ok
#       end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["openai:gpt-4", "--only", "generate_text,tool_calling"])

#       assert_received {:mix_shell, :info, ["✅ All capabilities verified successfully"]}
#     end

#     test "shows help when requested" do
#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["--help"])

#       assert_received {:mix_shell, :info, [help_text]}
#       assert help_text =~ "Usage: mix req_llm.verify MODEL_ID|PROVIDER"
#     end

#     test "shows error for invalid options" do
#       System
#       |> expect(:halt, fn 1 -> send(self(), :system_halt) end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["--invalid-option"])

#       assert_received :system_halt
#       assert_received {:mix_shell, :error, [error_msg]}
#       assert error_msg =~ "Invalid options"
#     end

#     test "shows error for wrong number of arguments" do
#       System
#       |> expect(:halt, fn 1 -> send(self(), :system_halt) end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run([])

#       assert_received :system_halt
#       assert_received {:mix_shell, :error, ["Expected exactly one model ID or provider argument"]}
#     end

#     test "verifies provider models successfully" do
#       models_json = %{
#         "models" => [
#           %{"id" => "claude-3-sonnet"},
#           %{"id" => "claude-3-haiku"}
#         ]
#       }

#       Application
#       |> expect(:app_dir, fn :req_llm, "priv" -> "/fake/priv" end)

#       File
#       |> expect(:read, fn "/fake/priv/models_dev/anthropic.json" ->
#         {:ok, Jason.encode!(models_json)}
#       end)

#       Jason
#       |> expect(:decode, fn _json -> {:ok, models_json} end)

#       Mix.Task
#       |> expect(:run, fn "app.start" -> :ok end)

#       ReqLLM.Capability
#       |> expect(:verify, fn "anthropic:claude-3-sonnet", [] -> :ok end)
#       |> expect(:verify, fn "anthropic:claude-3-haiku", [] -> :ok end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["anthropic"])

#       assert_received {:mix_shell, :info, ["Found 2 models for provider anthropic"]}
#       assert_received {:mix_shell, :info, ["✅ All capabilities verified successfully"]}
#     end

#     test "handles provider with no models" do
#       models_json = %{"models" => []}

#       Application
#       |> expect(:app_dir, fn :req_llm, "priv" -> "/fake/priv" end)

#       File
#       |> expect(:read, fn "/fake/priv/models_dev/empty.json" ->
#         {:ok, Jason.encode!(models_json)}
#       end)

#       Jason
#       |> expect(:decode, fn _json -> {:ok, models_json} end)

#       Mix.Task
#       |> expect(:run, fn "app.start" -> :ok end)

#       System
#       |> expect(:halt, fn 1 -> send(self(), :system_halt) end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["empty"])

#       assert_received :system_halt
#       assert_received {:mix_shell, :error, [error_msg]}
#       assert error_msg =~ "No models found for provider"
#     end

#     test "handles missing provider file" do
#       Application
#       |> expect(:app_dir, fn :req_llm, "priv" -> "/fake/priv" end)

#       File
#       |> expect(:read, fn "/fake/priv/models_dev/nonexistent.json" ->
#         {:error, :enoent}
#       end)

#       Mix.Task
#       |> expect(:run, fn "app.start" -> :ok end)

#       System
#       |> expect(:halt, fn 1 -> send(self(), :system_halt) end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["nonexistent"])

#       assert_received :system_halt
#       assert_received {:mix_shell, :error, [error_msg]}
#       assert error_msg =~ "Provider nonexistent not found"
#     end

#     test "handles invalid JSON in provider file" do
#       Application
#       |> expect(:app_dir, fn :req_llm, "priv" -> "/fake/priv" end)

#       File
#       |> expect(:read, fn "/fake/priv/models_dev/invalid.json" ->
#         {:ok, "invalid json"}
#       end)

#       Jason
#       |> expect(:decode, fn "invalid json" -> {:error, "decode error"} end)

#       Mix.Task
#       |> expect(:run, fn "app.start" -> :ok end)

#       System
#       |> expect(:halt, fn 1 -> send(self(), :system_halt) end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["invalid"])

#       assert_received :system_halt
#       assert_received {:mix_shell, :error, [error_msg]}
#       assert error_msg =~ "Failed to decode provider file"
#     end

#     test "handles provider verification failure" do
#       models_json = %{
#         "models" => [
#           %{"id" => "working-model"},
#           %{"id" => "failing-model"}
#         ]
#       }

#       Application
#       |> expect(:app_dir, fn :req_llm, "priv" -> "/fake/priv" end)

#       File
#       |> expect(:read, fn "/fake/priv/models_dev/mixed.json" ->
#         {:ok, Jason.encode!(models_json)}
#       end)

#       Jason
#       |> expect(:decode, fn _json -> {:ok, models_json} end)

#       Mix.Task
#       |> expect(:run, fn "app.start" -> :ok end)

#       ReqLLM.Capability
#       |> expect(:verify, fn "mixed:working-model", [] -> :ok end)
#       |> expect(:verify, fn "mixed:failing-model", [] -> :error end)

#       System
#       |> expect(:halt, fn 1 -> send(self(), :system_halt) end)

#       Mix.shell(Mix.Shell.Process)

#       Verify.run(["mixed"])

#       assert_received :system_halt
#       assert_received {:mix_shell, :info, ["✅ mixed:working-model passed"]}
#       assert_received {:mix_shell, :error, ["❌ mixed:failing-model failed"]}
#       assert_received {:mix_shell, :error, ["❌ One or more capabilities failed verification"]}
#     end
#   end
# end
