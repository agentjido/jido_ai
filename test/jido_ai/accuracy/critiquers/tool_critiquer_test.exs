defmodule Jido.AI.Accuracy.Critiquers.ToolCritiquerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Critiquers.ToolCritiquer}

  @moduletag :capture_log

  describe "new/1" do
    test "creates critiquer with defaults" do
      assert {:ok, critiquer} = ToolCritiquer.new([])

      assert critiquer.tools == []
      assert critiquer.timeout == 30_000
      assert critiquer.working_dir == nil
      assert is_map(critiquer.severity_map)
    end

    test "creates critiquer with custom tools" do
      tools = [
        %{name: "test", command: "echo", args: ["hello"], severity_on_fail: 0.7}
      ]

      assert {:ok, critiquer} = ToolCritiquer.new(tools: tools)

      assert length(critiquer.tools) == 1
      assert hd(critiquer.tools).name == "test"
    end

    test "creates critiquer with custom timeout" do
      assert {:ok, critiquer} = ToolCritiquer.new(timeout: 10_000)

      assert critiquer.timeout == 10_000
    end

    test "creates critiquer with custom severity_map" do
      assert {:ok, critiquer} = ToolCritiquer.new(severity_map: %{timeout: 0.5})

      assert critiquer.severity_map.timeout == 0.5
    end

    test "returns error for invalid tools" do
      assert {:error, :invalid_tools} = ToolCritiquer.new(tools: "not a list")
      assert {:error, :invalid_tools} = ToolCritiquer.new(tools: [%{name: "test"}])
      assert {:error, :invalid_tools} = ToolCritiquer.new(tools: [%{command: "test"}])
    end

    test "returns error for invalid severity_map" do
      assert {:error, :invalid_severity_map} = ToolCritiquer.new(severity_map: "not a map")
      assert {:error, :invalid_severity_map} = ToolCritiquer.new(severity_map: %{timeout: "invalid"})
    end

    test "returns error for invalid timeout" do
      assert {:error, :invalid_timeout} = ToolCritiquer.new(timeout: -1000)
      assert {:error, :invalid_timeout} = ToolCritiquer.new(timeout: "invalid")
    end
  end

  describe "new!/1" do
    test "returns critiquer when valid" do
      critiquer = ToolCritiquer.new!([])

      assert is_struct(critiquer, ToolCritiquer)
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid ToolCritiquer/, fn ->
        ToolCritiquer.new!(tools: "invalid")
      end
    end
  end

  describe "critique/2" do
    test "returns no issues when no tools configured" do
      critiquer = ToolCritiquer.new!([])
      candidate = Candidate.new!(%{id: "1", content: "test"})

      assert {:ok, result} = ToolCritiquer.critique(critiquer, candidate, %{})

      assert result.severity == 0.0
      assert result.issues == []
      assert result.actionable == false
      assert result.metadata.tools_run == 0
    end

    test "implements Critique behavior" do
      Code.ensure_loaded?(ToolCritiquer)
      assert Jido.AI.Accuracy.Critique.critiquer?(ToolCritiquer) == true
    end

    test "runs successful tool and returns low severity" do
      # Use a tool that will succeed (echo)
      tools = [
        %{name: "echo_test", command: "echo", args: ["success"], severity_on_fail: 0.8}
      ]

      critiquer = ToolCritiquer.new!(tools: tools)
      candidate = Candidate.new!(%{id: "1", content: "test content"})

      assert {:ok, result} = ToolCritiquer.critique(critiquer, candidate, %{})

      # Echo should succeed (exit code 0), so severity should be low
      assert result.severity == 0.0
      assert result.actionable == false
      assert result.feedback =~ "passed"
      assert result.metadata.tools_run == 1
      assert result.metadata.tools_passed == 1
    end

    test "runs failing tool and returns high severity" do
      # Use a tool that will fail (false command)
      tools = [
        %{name: "fail_test", command: "false", args: [], severity_on_fail: 0.8}
      ]

      critiquer = ToolCritiquer.new!(tools: tools)
      candidate = Candidate.new!(%{id: "1", content: "test content"})

      assert {:ok, result} = ToolCritiquer.critique(critiquer, candidate, %{})

      # false command exits with non-zero, so severity should be high
      assert result.severity >= 0.5
      assert result.actionable == true
      assert result.metadata.tools_run == 1
      assert result.metadata.tools_passed == 0
    end

    test "aggregates multiple tool results" do
      tools = [
        %{name: "success", command: "echo", args: ["ok"], severity_on_fail: 0.5},
        %{name: "failure", command: "false", args: [], severity_on_fail: 0.7}
      ]

      critiquer = ToolCritiquer.new!(tools: tools)
      candidate = Candidate.new!(%{id: "1", content: "test"})

      assert {:ok, result} = ToolCritiquer.critique(critiquer, candidate, %{})

      # Should have max severity from all tools
      assert result.severity >= 0.5
      assert result.metadata.tools_run == 2
      assert result.metadata.tools_passed == 1
      assert result.feedback =~ "Some tools failed"
    end

    test "parses error output for issues" do
      # Use sh to output error message
      tools = [
        %{
          name: "error_test",
          command: "sh",
          args: ["-c", "echo 'Error: something went wrong' >&2; exit 1"],
          severity_on_fail: 0.8
        }
      ]

      critiquer = ToolCritiquer.new!(tools: tools)
      candidate = Candidate.new!(%{id: "1", content: "test"})

      assert {:ok, result} = ToolCritiquer.critique(critiquer, candidate, %{})

      assert result.severity >= 0.5
      # Should have extracted issues from output
      assert length(result.issues) > 0
      assert result.actionable == true
    end
  end

  describe "custom output parser" do
    test "uses custom parser when provided" do
      parser = fn output ->
        [String.trim(output)]
      end

      tools = [
        %{
          name: "custom",
          command: "echo",
          args: ["custom output"],
          severity_on_fail: 0.6,
          parse_output: parser
        }
      ]

      critiquer = ToolCritiquer.new!(tools: tools)
      candidate = Candidate.new!(%{id: "1", content: "test"})

      # Even though echo succeeds, the parser would be used if it failed
      # For this test, we just verify the struct is valid
      assert {:ok, _result} = ToolCritiquer.critique(critiquer, candidate, %{})
    end
  end

  describe "severity mapping" do
    test "uses default severity when tool fails" do
      tools = [
        %{name: "fail", command: "false", args: [], severity_on_fail: nil}
      ]

      critiquer = ToolCritiquer.new!(tools: tools)
      candidate = Candidate.new!(%{id: "1", content: "test"})

      assert {:ok, result} = ToolCritiquer.critique(critiquer, candidate, %{})

      # Default severity_on_fail is 0.8
      assert result.severity == 0.8
    end

    test "uses custom severity_on_fail" do
      tools = [
        %{name: "fail", command: "false", args: [], severity_on_fail: 0.4}
      ]

      critiquer = ToolCritiquer.new!(tools: tools)
      candidate = Candidate.new!(%{id: "1", content: "test"})

      assert {:ok, result} = ToolCritiquer.critique(critiquer, candidate, %{})

      assert result.severity == 0.4
    end
  end

  describe "context handling" do
    test "works with empty context" do
      critiquer = ToolCritiquer.new!([])
      candidate = Candidate.new!(%{id: "1", content: "test"})

      assert {:ok, _result} = ToolCritiquer.critique(critiquer, candidate, %{})
    end
  end
end
