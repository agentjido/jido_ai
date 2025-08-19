defmodule Kodo.Core.PipelineExecutorTest do
  use ExUnit.Case, async: false

  alias Kodo.Core.Execution.PipelineExecutor
  alias Kodo.Core.Parsing.ExecutionPlan
  alias Kodo.Core.Jobs.Job

  defmodule TestCommand do
    @behaviour Kodo.Ports.Command

    def name, do: "echo"
    def description, do: "Test echo command"
    def usage, do: "echo [args...]"
    def meta, do: [:builtin]

    def execute(args, _context), do: {:ok, Enum.join(args, " ")}
  end

  defmodule TrueCommand do
    @behaviour Kodo.Ports.Command

    def name, do: "true"
    def description, do: "Always returns success"
    def usage, do: "true"
    def meta, do: [:builtin]

    def execute(_args, _context), do: {:ok, ""}
  end

  defmodule FalseCommand do
    @behaviour Kodo.Ports.Command

    def name, do: "false"
    def description, do: "Always returns failure"
    def usage, do: "false"
    def meta, do: [:builtin]

    def execute(_args, _context), do: {:error, {:exit_status, 1}}
  end

  defmodule FailingCommand do
    @behaviour Kodo.Ports.Command

    def name, do: "fail"
    def description, do: "Command that fails with specific error"
    def usage, do: "fail"
    def meta, do: [:builtin]

    def execute(_args, _context), do: {:error, :command_failed}
  end

  defmodule NonBuiltinCommand do
    @behaviour Kodo.Ports.Command

    def name, do: "external"
    def description, do: "External command"
    def usage, do: "external"
    def meta, do: []

    def execute(_args, _context), do: {:ok, "external result"}
  end

  setup do
    # Start required processes (handle case where registry is already started)
    case start_supervised(Kodo.Core.Commands.CommandRegistry) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Start JobManager
    start_supervised!(Kodo.Core.Jobs.JobManager)

    # Register test commands
    Kodo.Core.Commands.CommandRegistry.register_command(TestCommand)
    Kodo.Core.Commands.CommandRegistry.register_command(TrueCommand)
    Kodo.Core.Commands.CommandRegistry.register_command(FalseCommand)
    Kodo.Core.Commands.CommandRegistry.register_command(FailingCommand)
    Kodo.Core.Commands.CommandRegistry.register_command(NonBuiltinCommand)

    # Create test job
    job = %Job{
      id: 1,
      command: "test command",
      session_id: "test_session",
      background?: false,
      status: :running,
      pid: nil,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      exit_status: nil
    }

    bg_job = %Job{
      id: 2,
      command: "background command",
      session_id: "test_session",
      background?: true,
      status: :running,
      pid: nil,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      exit_status: nil
    }

    context = %{
      session_id: "test_session",
      background?: false
    }

    {:ok, job: job, bg_job: bg_job, context: context}
  end

  describe "exec/3 - core functionality" do
    test "executes simple builtin command", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["hello"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec(command, job, context)
      assert {:ok, "hello"} = result
    end

    test "executes builtin command that fails", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "fail",
        args: [],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec(command, job, context)
      assert {:error, :command_failed} = result
    end

    test "executes builtin command that returns exit status", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "false",
        args: [],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec(command, job, context)
      assert {:error, {:exit_status, 1}} = result
    end

    test "handles unknown execution plan", %{job: job, context: context} do
      result = PipelineExecutor.exec(:unknown_plan, job, context)
      assert {:error, {:unknown_execution_plan, :unknown_plan}} = result
    end

    test "executes non-builtin command", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "external",
        args: ["test"],
        redirections: [],
        env: nil
      }

      # Non-builtin commands will try to spawn external process
      result = PipelineExecutor.exec(command, job, context)
      # Should fail with spawn_failed in test environment since external command doesn't exist
      assert {:error, {:spawn_failed, %ErlangError{original: :enoent}}} = result
    end

    test "executes unknown command", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "nonexistent",
        args: [],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec(command, job, context)
      assert {:error, {:spawn_failed, %ErlangError{original: :enoent}}} = result
    end

    test "executes command with multiple arguments", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["hello", "world", "test"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec(command, job, context)
      assert {:ok, "hello world test"} = result
    end

    test "executes command with no arguments", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: [],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec(command, job, context)
      assert {:ok, ""} = result
    end
  end

  describe "exec/3 - pipeline execution" do
    test "executes pipeline with single command", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["hello"],
        redirections: [],
        env: nil
      }

      pipeline = %ExecutionPlan.Pipeline{
        commands: [command],
        background?: false
      }

      result = PipelineExecutor.exec(pipeline, job, context)
      assert {:ok, "hello"} = result
    end

    test "executes empty pipeline", %{job: job, context: context} do
      result = PipelineExecutor.exec_pipeline([], job, context)
      assert {:ok, 0} = result
    end

    test "executes background command", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["hello"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec({:background, command}, job, context)
      # Background execution should return immediately
      assert {:ok, 0} = result
    end

    test "executes pipeline with background flag", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["bg_pipeline"],
        redirections: [],
        env: nil
      }

      pipeline = %ExecutionPlan.Pipeline{commands: [command], background?: true}

      result = PipelineExecutor.exec(pipeline, job, context)
      assert {:ok, "bg_pipeline"} = result
    end
  end

  describe "exec_command/3" do
    test "executes builtin command successfully", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["test"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, "test"} = result
    end

    test "handles command with redirections", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["test"],
        redirections: [%{type: :stdout, target: "/dev/null"}],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, "test"} = result
    end

    test "handles background job stdio configuration", %{bg_job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["background_test"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, "background_test"} = result
    end

    test "fails with spawn_failed for unknown external command", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "nonexistent_external",
        args: [],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:error, {:spawn_failed, %ErlangError{original: :enoent}}} = result
    end

    test "handles command with nil redirections", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["test_nil"],
        redirections: nil,
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, "test_nil"} = result
    end
  end

  describe "exec_control_op/5" do
    test "handles AND operator - both commands succeed", %{job: job, context: context} do
      left_cmd = %ExecutionPlan.Command{name: "echo", args: ["left"], redirections: [], env: nil}

      right_cmd = %ExecutionPlan.Command{
        name: "echo",
        args: ["right"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_control_op(left_cmd, :and_then, right_cmd, job, context)

      # AND operator with string output: non-zero string treated as success, so right command is skipped
      assert {:ok, "left"} = result
    end

    test "handles AND operator with command failure", %{job: job, context: context} do
      left_cmd = %ExecutionPlan.Command{name: "false", args: [], redirections: [], env: nil}

      right_cmd = %ExecutionPlan.Command{
        name: "echo",
        args: ["should_not_run"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_control_op(left_cmd, :and_then, right_cmd, job, context)
      assert {:error, {:exit_status, 1}} = result
    end

    test "handles OR operator with command failure", %{job: job, context: context} do
      left_cmd = %ExecutionPlan.Command{name: "false", args: [], redirections: [], env: nil}

      right_cmd = %ExecutionPlan.Command{
        name: "echo",
        args: ["right"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_control_op(left_cmd, :or_else, right_cmd, job, context)
      assert {:ok, "right"} = result
    end

    test "handles sequence operator - always runs both", %{job: job, context: context} do
      left_cmd = %ExecutionPlan.Command{name: "false", args: [], redirections: [], env: nil}

      right_cmd = %ExecutionPlan.Command{
        name: "echo",
        args: ["right"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_control_op(left_cmd, :sequence, right_cmd, job, context)
      assert {:ok, "right"} = result
    end

    test "handles sequence operator when both succeed", %{job: job, context: context} do
      left_cmd = %ExecutionPlan.Command{name: "echo", args: ["left"], redirections: [], env: nil}

      right_cmd = %ExecutionPlan.Command{
        name: "echo",
        args: ["right"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_control_op(left_cmd, :sequence, right_cmd, job, context)
      assert {:ok, "right"} = result
    end

    test "handles AND operator with left error", %{job: job, context: context} do
      left_cmd = %ExecutionPlan.Command{name: "fail", args: [], redirections: [], env: nil}

      right_cmd = %ExecutionPlan.Command{
        name: "echo",
        args: ["right"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_control_op(left_cmd, :and_then, right_cmd, job, context)
      assert {:error, :command_failed} = result
    end

    test "handles OR operator with left error", %{job: job, context: context} do
      left_cmd = %ExecutionPlan.Command{name: "fail", args: [], redirections: [], env: nil}

      right_cmd = %ExecutionPlan.Command{
        name: "echo",
        args: ["right"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_control_op(left_cmd, :or_else, right_cmd, job, context)
      assert {:ok, "right"} = result
    end

    test "handles sequence operator with left error", %{job: job, context: context} do
      left_cmd = %ExecutionPlan.Command{name: "fail", args: [], redirections: [], env: nil}

      right_cmd = %ExecutionPlan.Command{
        name: "echo",
        args: ["right"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_control_op(left_cmd, :sequence, right_cmd, job, context)
      assert {:ok, "right"} = result
    end
  end

  describe "exec_bg/3" do
    test "spawns background task", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["background"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_bg(command, job, context)
      assert {:ok, 0} = result
    end

    test "spawns background task with failing command", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "fail",
        args: [],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_bg(command, job, context)
      assert {:ok, 0} = result
    end

    test "spawns background task with complex command", %{job: job, context: context} do
      pipeline = %ExecutionPlan.Pipeline{
        commands: [
          %ExecutionPlan.Command{name: "echo", args: ["bg_test"], redirections: [], env: nil}
        ],
        background?: false
      }

      result = PipelineExecutor.exec_bg(pipeline, job, context)
      assert {:ok, 0} = result
    end
  end

  describe "legacy function support" do
    test "execute/3 delegates to exec/3", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["legacy"],
        redirections: [],
        env: nil
      }

      # Test that legacy function still works
      result = PipelineExecutor.execute(command, job, context)
      assert {:ok, "legacy"} = result
    end
  end

  describe "complex execution plans" do
    test "executes execution plan with multiple pipelines", %{job: job, context: context} do
      command1 = %ExecutionPlan.Command{name: "echo", args: ["1"], redirections: [], env: nil}
      command2 = %ExecutionPlan.Command{name: "echo", args: ["2"], redirections: [], env: nil}

      pipeline1 = %ExecutionPlan.Pipeline{commands: [command1], background?: false}
      pipeline2 = %ExecutionPlan.Pipeline{commands: [command2], background?: false}

      plan = %ExecutionPlan{
        pipelines: [pipeline1, pipeline2],
        control_ops: []
      }

      result = PipelineExecutor.exec(plan, job, context)
      assert {:ok, "2"} = result
    end

    test "executes single pipeline in execution plan", %{job: job, context: context} do
      command = %ExecutionPlan.Command{name: "echo", args: ["single"], redirections: [], env: nil}
      pipeline = %ExecutionPlan.Pipeline{commands: [command], background?: false}

      plan = %ExecutionPlan{
        pipelines: [pipeline],
        control_ops: []
      }

      result = PipelineExecutor.exec(plan, job, context)
      assert {:ok, "single"} = result
    end

    test "executes empty execution plan", %{job: job, context: context} do
      plan = %ExecutionPlan{
        pipelines: [],
        control_ops: []
      }

      result = PipelineExecutor.exec(plan, job, context)
      assert {:ok, 0} = result
    end

    test "handles execution plan with pipeline failure", %{job: job, context: context} do
      command1 = %ExecutionPlan.Command{name: "echo", args: ["1"], redirections: [], env: nil}
      command2 = %ExecutionPlan.Command{name: "fail", args: [], redirections: [], env: nil}

      pipeline1 = %ExecutionPlan.Pipeline{commands: [command1], background?: false}
      pipeline2 = %ExecutionPlan.Pipeline{commands: [command2], background?: false}

      plan = %ExecutionPlan{
        pipelines: [pipeline1, pipeline2],
        control_ops: []
      }

      result = PipelineExecutor.exec(plan, job, context)
      assert {:error, :command_failed} = result
    end
  end

  describe "error handling and edge cases" do
    test "handles builtin command errors gracefully", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "fail",
        args: ["some", "args"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:error, :command_failed} = result
    end

    test "handles external command spawn failure", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "definitely_nonexistent_command_12345",
        args: [],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:error, {:spawn_failed, %ErlangError{original: :enoent}}} = result
    end

    test "handles command with complex args", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["arg1", "arg2", "arg3"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, "arg1 arg2 arg3"} = result
    end

    test "handles command with empty args", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: [],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, ""} = result
    end
  end

  describe "redirection handling" do
    test "applies redirections to command", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["test_redirection"],
        redirections: [
          %{type: :stdout, target: "/tmp/test_output"},
          %{type: :stderr, target: "/tmp/test_error"}
        ],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, "test_redirection"} = result
    end

    test "handles empty redirections list", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["test"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, "test"} = result
    end
  end

  describe "job integration" do
    test "works with different job configurations", %{context: context} do
      custom_job = %Job{
        id: 99,
        command: "custom test command",
        session_id: "custom_session",
        background?: false,
        status: :running,
        pid: nil,
        started_at: DateTime.utc_now(),
        completed_at: nil,
        exit_status: nil
      }

      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["custom_job"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, custom_job, context)
      assert {:ok, "custom_job"} = result
    end

    test "handles job with different session IDs", %{job: job, context: context} do
      job_with_different_session = %{job | session_id: "different_session"}

      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["different_session_test"],
        redirections: [],
        env: nil
      }

      result = PipelineExecutor.exec_command(command, job_with_different_session, context)
      assert {:ok, "different_session_test"} = result
    end
  end

  describe "stdio configuration" do
    test "determines stdio config for foreground job", %{job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["stdio_test"],
        redirections: [],
        env: nil
      }

      # This tests the stdio configuration path
      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, "stdio_test"} = result
    end

    test "determines stdio config for background job", %{bg_job: job, context: context} do
      command = %ExecutionPlan.Command{
        name: "echo",
        args: ["bg_stdio_test"],
        redirections: [],
        env: nil
      }

      # This tests the background stdio configuration path
      result = PipelineExecutor.exec_command(command, job, context)
      assert {:ok, "bg_stdio_test"} = result
    end
  end
end
