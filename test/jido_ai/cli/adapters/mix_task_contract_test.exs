defmodule Mix.Tasks.JidoAi.ContractTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapter
  alias Mix.Tasks.JidoAi, as: JidoAiTask

  describe "option_parser_config/0" do
    test "accepts documented long and short options" do
      argv = [
        "--type",
        "got",
        "--model",
        "openai:gpt-4.1",
        "--max-iterations",
        "7",
        "--stdin",
        "--timeout",
        "15000",
        "--trace",
        "--format",
        "json",
        "-q"
      ]

      {opts, _args, invalid} = OptionParser.parse(argv, JidoAiTask.option_parser_config())

      assert invalid == []
      assert opts[:type] == "got"
      assert opts[:model] == "openai:gpt-4.1"
      assert opts[:max_iterations] == 7
      assert opts[:stdin] == true
      assert opts[:timeout] == 15_000
      assert opts[:trace] == true
      assert opts[:format] == "json"
      assert opts[:quiet] == true
    end
  end

  describe "build_config/1" do
    test "maps parsed options to runtime config" do
      config =
        JidoAiTask.build_config(
          type: "cot",
          model: "anthropic:claude-haiku-4-5",
          max_iterations: 12,
          system: "Reason carefully.",
          format: "json",
          quiet: true,
          timeout: 90_000,
          stdin: true,
          trace: true
        )

      assert config.type == "cot"
      assert config.model == "anthropic:claude-haiku-4-5"
      assert config.max_iterations == 12
      assert config.system_prompt == "Reason carefully."
      assert config.format == "json"
      assert config.quiet == true
      assert config.timeout == 90_000
      assert config.stdin == true
      assert config.trace == true
      assert config.user_agent_module == nil
      assert config.tools == nil
    end

    test "applies defaults for omitted options" do
      config = JidoAiTask.build_config([])

      assert config.type == nil
      assert config.model == nil
      assert config.max_iterations == nil
      assert config.system_prompt == nil
      assert config.format == "text"
      assert config.quiet == false
      assert config.timeout == 60_000
      assert config.stdin == false
      assert config.trace == false
      assert config.user_agent_module == nil
      assert config.tools == nil
    end
  end

  describe "format_error/1" do
    test "formats standard and fallback errors" do
      assert JidoAiTask.format_error(:timeout) == "Timeout waiting for agent completion"
      assert JidoAiTask.format_error(:not_found) == "Agent process not found"
      assert JidoAiTask.format_error("explicit failure") == "explicit failure"
      assert JidoAiTask.format_error({:bad_state, 2}) == "{:bad_state, 2}"
    end
  end

  describe "supported_types/0" do
    test "stays aligned with adapter resolution types" do
      assert JidoAiTask.supported_types() == Adapter.supported_types()
      assert JidoAiTask.supported_types() == ~w(react aot cod cot tot got trm adaptive)
    end
  end
end
