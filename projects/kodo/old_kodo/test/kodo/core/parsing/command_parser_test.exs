defmodule Kodo.Core.CommandParserTest do
  use ExUnit.Case, async: true

  alias Kodo.Core.Parsing.{CommandParser, ExecutionPlan}
  alias ExecutionPlan.{Pipeline, Command, Redirection}

  describe "parse/1" do
    test "parses simple command into execution plan" do
      assert {:ok, plan} = CommandParser.parse("ls -la")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "ls", args: ["-la"], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "parses complex command with pipes" do
      assert {:ok, plan} = CommandParser.parse("ls | grep txt")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{name: "ls", args: [], redirections: []},
                     %Command{name: "grep", args: ["txt"], redirections: []}
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "parses command with redirections" do
      assert {:ok, plan} = CommandParser.parse("echo hello > output.txt")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{
                       name: "echo",
                       args: ["hello"],
                       redirections: [%Redirection{type: :output, target: "output.txt"}]
                     }
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "parses command with control operators" do
      assert {:ok, plan} = CommandParser.parse("make && make test")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "make", args: [], redirections: []}],
                   background?: false
                 },
                 %Pipeline{
                   commands: [%Command{name: "make", args: ["test"], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: [:and]
             } = plan
    end

    test "returns error for malformed input" do
      assert {:error, _reason} = CommandParser.parse("echo 'unclosed")
    end
  end

  describe "parse_simple/1" do
    test "parses simple command string" do
      assert {"ls", ["-la"], []} = CommandParser.parse_simple("ls -la")
    end

    test "parses command with options" do
      assert {"ls", [], [verbose: true]} = CommandParser.parse_simple("ls --verbose")
    end

    test "parses command with mixed args and options" do
      assert {"grep", ["pattern", "file.txt"], [recursive: true]} =
               CommandParser.parse_simple("grep pattern file.txt --recursive")
    end

    test "handles empty input" do
      assert {"", [], []} = CommandParser.parse_simple("")
    end

    test "handles command with no arguments" do
      assert {"ls", [], []} = CommandParser.parse_simple("ls")
    end

    test "parses aliased options" do
      assert {"ls", [], [verbose: true, recursive: true]} =
               CommandParser.parse_simple("ls -v -r")
    end

    test "handles quoted arguments" do
      assert {"echo", ["hello world"], []} =
               CommandParser.parse_simple(~s(echo "hello world"))
    end
  end

  describe "to_simple/1" do
    test "converts simple execution plan to tuple format" do
      command = %Command{name: "ls", args: ["-la"], redirections: [], env: nil}
      pipeline = %Pipeline{commands: [command], background?: false}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: []}

      assert {"ls", ["-la"], []} = CommandParser.to_simple(plan)
    end

    test "returns :complex for execution plan with multiple commands" do
      cmd1 = %Command{name: "ls", args: [], redirections: [], env: nil}
      cmd2 = %Command{name: "grep", args: ["txt"], redirections: [], env: nil}
      pipeline = %Pipeline{commands: [cmd1, cmd2], background?: false}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: []}

      assert :complex = CommandParser.to_simple(plan)
    end

    test "returns :complex for execution plan with multiple pipelines" do
      cmd1 = %Command{name: "make", args: [], redirections: [], env: nil}
      cmd2 = %Command{name: "test", args: [], redirections: [], env: nil}

      pipeline1 = %Pipeline{commands: [cmd1], background?: false}
      pipeline2 = %Pipeline{commands: [cmd2], background?: false}

      plan = %ExecutionPlan{pipelines: [pipeline1, pipeline2], control_ops: [:and]}

      assert :complex = CommandParser.to_simple(plan)
    end

    test "returns :complex for execution plan with control operators" do
      command = %Command{name: "ls", args: [], redirections: [], env: nil}
      pipeline = %Pipeline{commands: [command], background?: false}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: [:background]}

      assert :complex = CommandParser.to_simple(plan)
    end

    test "returns :complex for execution plan with redirections" do
      redirection = %Redirection{type: :output, target: "file.txt"}
      command = %Command{name: "echo", args: ["hello"], redirections: [redirection], env: nil}
      pipeline = %Pipeline{commands: [command], background?: false}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: []}

      assert :complex = CommandParser.to_simple(plan)
    end
  end

  describe "backward compatibility" do
    test "legacy parse_simple interface works as expected" do
      # Test that existing code using parse_simple continues to work
      {cmd, args, opts} = CommandParser.parse_simple("ls -la --verbose")

      assert cmd == "ls"
      assert args == ["-la"]
      assert opts == [verbose: true]
    end

    test "new parse interface handles complex commands" do
      # Test that new interface can handle what old one couldn't
      assert {:ok, _plan} = CommandParser.parse("ls | grep txt > output.txt")

      # This would not work with the old parse_simple
      assert {"ls", ["grep", "txt", ">", "output.txt"], []} =
               CommandParser.parse_simple("ls grep txt > output.txt")
    end
  end

  describe "error handling" do
    test "provides helpful error messages for parsing failures" do
      assert {:error, reason} = CommandParser.parse("echo 'unclosed quote")
      assert is_binary(reason)
      assert String.contains?(reason, "Parse error")
    end

    test "handles empty and whitespace-only input gracefully" do
      assert {:ok, plan} = CommandParser.parse("")
      assert %ExecutionPlan{pipelines: [], control_ops: []} = plan

      assert {:ok, plan} = CommandParser.parse("   ")
      assert %ExecutionPlan{pipelines: [], control_ops: []} = plan
    end
  end
end
