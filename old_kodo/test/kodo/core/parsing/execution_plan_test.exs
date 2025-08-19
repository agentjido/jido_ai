defmodule Kodo.Core.ExecutionPlanTest do
  use ExUnit.Case, async: true

  alias Kodo.Core.Parsing.ExecutionPlan
  alias ExecutionPlan.{Pipeline, Command, Redirection}

  describe "ExecutionPlan struct creation" do
    test "creates empty execution plan" do
      plan = %ExecutionPlan{pipelines: [], control_ops: []}

      assert plan.pipelines == []
      assert plan.control_ops == []
    end

    test "creates execution plan with single pipeline" do
      command = %Command{name: "ls", args: ["-la"], redirections: [], env: nil}
      pipeline = %Pipeline{commands: [command], background?: false}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: []}

      assert length(plan.pipelines) == 1
      assert plan.control_ops == []
    end

    test "creates execution plan with multiple pipelines and control ops" do
      cmd1 = %Command{name: "make", args: [], redirections: [], env: nil}
      cmd2 = %Command{name: "make", args: ["test"], redirections: [], env: nil}

      pipeline1 = %Pipeline{commands: [cmd1], background?: false}
      pipeline2 = %Pipeline{commands: [cmd2], background?: false}

      plan = %ExecutionPlan{
        pipelines: [pipeline1, pipeline2],
        control_ops: [:and]
      }

      assert length(plan.pipelines) == 2
      assert plan.control_ops == [:and]
    end
  end

  describe "get_all_commands/1" do
    test "returns empty list for empty execution plan" do
      plan = %ExecutionPlan{pipelines: [], control_ops: []}

      assert ExecutionPlan.get_all_commands(plan) == []
    end

    test "returns all commands from single pipeline" do
      cmd1 = %Command{name: "ls", args: [], redirections: [], env: nil}
      cmd2 = %Command{name: "grep", args: ["txt"], redirections: [], env: nil}

      pipeline = %Pipeline{commands: [cmd1, cmd2], background?: false}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: []}

      commands = ExecutionPlan.get_all_commands(plan)
      assert length(commands) == 2
      assert Enum.at(commands, 0).name == "ls"
      assert Enum.at(commands, 1).name == "grep"
    end

    test "returns all commands from multiple pipelines" do
      cmd1 = %Command{name: "make", args: [], redirections: [], env: nil}
      cmd2 = %Command{name: "make", args: ["test"], redirections: [], env: nil}
      cmd3 = %Command{name: "echo", args: ["done"], redirections: [], env: nil}

      pipeline1 = %Pipeline{commands: [cmd1], background?: false}
      pipeline2 = %Pipeline{commands: [cmd2, cmd3], background?: false}

      plan = %ExecutionPlan{
        pipelines: [pipeline1, pipeline2],
        control_ops: [:and]
      }

      commands = ExecutionPlan.get_all_commands(plan)
      assert length(commands) == 3
      assert Enum.map(commands, & &1.name) == ["make", "make", "echo"]
    end
  end

  describe "has_background_process?/1" do
    test "returns false for execution plan with no background processes" do
      cmd = %Command{name: "ls", args: [], redirections: [], env: nil}
      pipeline = %Pipeline{commands: [cmd], background?: false}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: []}

      assert ExecutionPlan.has_background_process?(plan) == false
    end

    test "returns true when pipeline is marked as background" do
      cmd = %Command{name: "long_process", args: [], redirections: [], env: nil}
      pipeline = %Pipeline{commands: [cmd], background?: true}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: []}

      assert ExecutionPlan.has_background_process?(plan) == true
    end

    test "returns true when control_ops contains background operator" do
      cmd = %Command{name: "process", args: [], redirections: [], env: nil}
      pipeline = %Pipeline{commands: [cmd], background?: false}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: [:background]}

      assert ExecutionPlan.has_background_process?(plan) == true
    end

    test "returns true when both pipeline and control_ops indicate background" do
      cmd = %Command{name: "process", args: [], redirections: [], env: nil}
      pipeline = %Pipeline{commands: [cmd], background?: true}
      plan = %ExecutionPlan{pipelines: [pipeline], control_ops: [:background]}

      assert ExecutionPlan.has_background_process?(plan) == true
    end

    test "returns false when only non-background control_ops are present" do
      cmd1 = %Command{name: "make", args: [], redirections: [], env: nil}
      cmd2 = %Command{name: "test", args: [], redirections: [], env: nil}

      pipeline1 = %Pipeline{commands: [cmd1], background?: false}
      pipeline2 = %Pipeline{commands: [cmd2], background?: false}

      plan = %ExecutionPlan{
        pipelines: [pipeline1, pipeline2],
        control_ops: [:and, :or, :semicolon]
      }

      assert ExecutionPlan.has_background_process?(plan) == false
    end
  end

  describe "get_pipelines/1" do
    test "returns empty list for empty execution plan" do
      plan = %ExecutionPlan{pipelines: [], control_ops: []}

      assert ExecutionPlan.get_pipelines(plan) == []
    end

    test "returns all pipelines" do
      cmd1 = %Command{name: "ls", args: [], redirections: [], env: nil}
      cmd2 = %Command{name: "grep", args: ["txt"], redirections: [], env: nil}

      pipeline1 = %Pipeline{commands: [cmd1], background?: false}
      pipeline2 = %Pipeline{commands: [cmd2], background?: false}

      plan = %ExecutionPlan{
        pipelines: [pipeline1, pipeline2],
        control_ops: [:and]
      }

      pipelines = ExecutionPlan.get_pipelines(plan)
      assert length(pipelines) == 2
      assert pipelines == [pipeline1, pipeline2]
    end
  end

  describe "has_redirection?/2" do
    test "returns false when command has no redirections" do
      command = %Command{name: "ls", args: [], redirections: [], env: nil}

      assert ExecutionPlan.has_redirection?(command, :output) == false
      assert ExecutionPlan.has_redirection?(command, :input) == false
      assert ExecutionPlan.has_redirection?(command, :append) == false
    end

    test "returns true when command has redirection of specified type" do
      output_redir = %Redirection{type: :output, target: "file.txt"}
      input_redir = %Redirection{type: :input, target: "input.txt"}

      command = %Command{
        name: "grep",
        args: ["pattern"],
        redirections: [output_redir, input_redir],
        env: nil
      }

      assert ExecutionPlan.has_redirection?(command, :output) == true
      assert ExecutionPlan.has_redirection?(command, :input) == true
      assert ExecutionPlan.has_redirection?(command, :append) == false
    end
  end

  describe "get_redirections/2" do
    test "returns empty list when command has no redirections of specified type" do
      command = %Command{name: "ls", args: [], redirections: [], env: nil}

      assert ExecutionPlan.get_redirections(command, :output) == []
    end

    test "returns redirections of specified type" do
      output_redir1 = %Redirection{type: :output, target: "file1.txt"}
      output_redir2 = %Redirection{type: :output, target: "file2.txt"}
      input_redir = %Redirection{type: :input, target: "input.txt"}

      command = %Command{
        name: "cmd",
        args: [],
        redirections: [output_redir1, input_redir, output_redir2],
        env: nil
      }

      output_redirections = ExecutionPlan.get_redirections(command, :output)
      input_redirections = ExecutionPlan.get_redirections(command, :input)

      assert length(output_redirections) == 2
      assert output_redirections == [output_redir1, output_redir2]

      assert length(input_redirections) == 1
      assert input_redirections == [input_redir]
    end
  end

  describe "Command struct" do
    test "creates command with all fields" do
      redirection = %Redirection{type: :output, target: "file.txt"}
      env = %{"PATH" => "/usr/bin", "HOME" => "/home/user"}

      command = %Command{
        name: "grep",
        args: ["pattern", "file"],
        redirections: [redirection],
        env: env
      }

      assert command.name == "grep"
      assert command.args == ["pattern", "file"]
      assert command.redirections == [redirection]
      assert command.env == env
    end

    test "creates command with nil env" do
      command = %Command{
        name: "ls",
        args: ["-la"],
        redirections: [],
        env: nil
      }

      assert command.env == nil
    end
  end

  describe "Pipeline struct" do
    test "creates pipeline with background flag" do
      command = %Command{name: "long_process", args: [], redirections: [], env: nil}

      pipeline = %Pipeline{commands: [command], background?: true}

      assert pipeline.background? == true
      assert length(pipeline.commands) == 1
    end

    test "creates pipeline without background flag" do
      command = %Command{name: "ls", args: [], redirections: [], env: nil}

      pipeline = %Pipeline{commands: [command], background?: false}

      assert pipeline.background? == false
    end
  end

  describe "Redirection struct" do
    test "creates input redirection" do
      redirection = %Redirection{type: :input, target: "input.txt"}

      assert redirection.type == :input
      assert redirection.target == "input.txt"
    end

    test "creates output redirection" do
      redirection = %Redirection{type: :output, target: "output.txt"}

      assert redirection.type == :output
      assert redirection.target == "output.txt"
    end

    test "creates append redirection" do
      redirection = %Redirection{type: :append, target: "log.txt"}

      assert redirection.type == :append
      assert redirection.target == "log.txt"
    end
  end
end
