defmodule Kodo.Core.CommandContextTest do
  use ExUnit.Case, async: true

  alias Kodo.Core.Execution.CommandContext

  describe "new/3" do
    test "creates a command context with defaults" do
      session_id = "test-session"
      session_pid = self()

      context = CommandContext.new(session_id, session_pid)

      assert context.session_id == session_id
      assert context.session_pid == session_pid
      assert context.env == %{}
      assert is_binary(context.working_dir)
      assert context.stdin == :inherit
      assert context.stdout == :inherit
      assert context.stderr == :inherit
      assert context.job_id == nil
      assert context.background? == false
      assert context.opts == %{}
    end

    test "creates a command context with options" do
      session_id = "test-session"
      session_pid = self()

      opts = %{
        env: %{"TEST" => "value"},
        working_dir: "/tmp",
        stdin: :pipe,
        stdout: :capture,
        stderr: :capture,
        job_id: 123,
        background?: true,
        custom_opt: "custom"
      }

      context = CommandContext.new(session_id, session_pid, opts)

      assert context.env == %{"TEST" => "value"}
      assert context.working_dir == "/tmp"
      assert context.stdin == :pipe
      assert context.stdout == :capture
      assert context.stderr == :capture
      assert context.job_id == 123
      assert context.background? == true
      assert context.opts == %{custom_opt: "custom"}
    end
  end

  describe "from_legacy/1" do
    test "converts legacy context format" do
      session_pid = self()

      legacy_context = %{
        session_pid: session_pid,
        env: %{"PATH" => "/bin"},
        current_dir: "/home",
        opts: %{debug: true}
      }

      context = CommandContext.from_legacy(legacy_context)

      assert context.session_pid == session_pid
      assert context.env == %{"PATH" => "/bin"}
      assert context.working_dir == "/home"
      assert context.opts == %{debug: true}
      assert String.starts_with?(context.session_id, "session_")
    end

    test "handles legacy context with session_id" do
      session_pid = self()

      legacy_context = %{
        session_id: "existing-session",
        session_pid: session_pid
      }

      context = CommandContext.from_legacy(legacy_context)

      assert context.session_id == "existing-session"
    end
  end

  describe "to_legacy/1" do
    test "converts to legacy format" do
      session_pid = self()

      context =
        CommandContext.new("test", session_pid, %{
          env: %{"TEST" => "value"},
          working_dir: "/tmp",
          custom: "option"
        })

      legacy = CommandContext.to_legacy(context)

      assert legacy.session_pid == session_pid
      assert legacy.env == %{"TEST" => "value"}
      assert legacy.current_dir == "/tmp"
      assert legacy.opts == %{custom: "option"}
    end
  end

  describe "set_job_id/2" do
    test "sets job ID" do
      context = CommandContext.new("test", self())
      updated = CommandContext.set_job_id(context, 456)

      assert updated.job_id == 456
    end
  end

  describe "set_background/2" do
    test "sets background flag" do
      context = CommandContext.new("test", self())
      updated = CommandContext.set_background(context, true)

      assert updated.background? == true
    end
  end

  describe "set_stdio/4" do
    test "sets stdio streams" do
      context = CommandContext.new("test", self())
      updated = CommandContext.set_stdio(context, :pipe, :capture, :capture)

      assert updated.stdin == :pipe
      assert updated.stdout == :capture
      assert updated.stderr == :capture
    end
  end

  describe "set_working_dir/2" do
    test "updates working directory" do
      context = CommandContext.new("test", self())
      updated = CommandContext.set_working_dir(context, "/new/path")

      assert updated.working_dir == "/new/path"
    end
  end

  describe "update_env/2" do
    test "merges environment variables" do
      context = CommandContext.new("test", self(), %{env: %{"EXISTING" => "value"}})
      updated = CommandContext.update_env(context, %{"NEW" => "variable"})

      assert updated.env == %{"EXISTING" => "value", "NEW" => "variable"}
    end

    test "overwrites existing variables" do
      context = CommandContext.new("test", self(), %{env: %{"TEST" => "old"}})
      updated = CommandContext.update_env(context, %{"TEST" => "new"})

      assert updated.env == %{"TEST" => "new"}
    end
  end

  describe "put_env/3" do
    test "sets single environment variable" do
      context = CommandContext.new("test", self())
      updated = CommandContext.put_env(context, "KEY", "value")

      assert updated.env == %{"KEY" => "value"}
    end
  end

  describe "get_env/3" do
    test "gets environment variable" do
      context = CommandContext.new("test", self(), %{env: %{"TEST" => "value"}})

      assert CommandContext.get_env(context, "TEST") == "value"
      assert CommandContext.get_env(context, "MISSING") == nil
      assert CommandContext.get_env(context, "MISSING", "default") == "default"
    end
  end

  describe "background?/1" do
    test "returns background flag" do
      context = CommandContext.new("test", self())
      assert CommandContext.background?(context) == false

      context = CommandContext.set_background(context, true)
      assert CommandContext.background?(context) == true
    end
  end

  describe "has_stdio_redirection?/1" do
    test "detects stdio redirection" do
      context = CommandContext.new("test", self())
      assert CommandContext.has_stdio_redirection?(context) == false

      context = CommandContext.set_stdio(context, :pipe, :inherit, :inherit)
      assert CommandContext.has_stdio_redirection?(context) == true

      context = CommandContext.set_stdio(context, :inherit, :capture, :inherit)
      assert CommandContext.has_stdio_redirection?(context) == true

      context = CommandContext.set_stdio(context, :inherit, :inherit, :capture)
      assert CommandContext.has_stdio_redirection?(context) == true
    end
  end

  describe "capture_output/1" do
    test "creates context for output capture" do
      context = CommandContext.new("test", self())
      captured = CommandContext.capture_output(context)

      assert captured.stdin == :pipe
      assert captured.stdout == :capture
      assert captured.stderr == :capture
    end
  end

  describe "background_context/1" do
    test "creates background context with proper stdio" do
      context = CommandContext.new("test", self())
      bg_context = CommandContext.background_context(context)

      assert bg_context.background? == true
      assert bg_context.stdin == {:file, "/dev/null", [:read]}
      assert bg_context.stdout == {:file, "/dev/null", [:write]}
      assert bg_context.stderr == {:file, "/dev/null", [:write]}
    end
  end
end
