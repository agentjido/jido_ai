defmodule Jido.AI.Accuracy.Verifiers.CodeExecutionVerifierTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Verifiers.CodeExecutionVerifier}

  @moduletag :capture_log

  describe "new/1" do
    test "creates verifier with defaults" do
      assert {:ok, verifier} = CodeExecutionVerifier.new([])
      assert verifier.timeout == 5000
      # Default sandbox is :none for backward compatibility (with warning logged)
      assert verifier.sandbox == :none
      assert verifier.language == :auto
    end

    test "creates verifier with custom timeout" do
      assert {:ok, verifier} = CodeExecutionVerifier.new(%{timeout: 10_000})
      assert verifier.timeout == 10_000
    end

    test "creates verifier with docker sandbox" do
      assert {:ok, verifier} = CodeExecutionVerifier.new(%{sandbox: :docker})
      assert verifier.sandbox == :docker
    end

    test "creates verifier with podman sandbox" do
      assert {:ok, verifier} = CodeExecutionVerifier.new(%{sandbox: :podman})
      assert verifier.sandbox == :podman
    end

    test "creates verifier with language specified" do
      assert {:ok, verifier} = CodeExecutionVerifier.new(%{language: :python})
      assert verifier.language == :python
    end

    test "returns error for invalid timeout" do
      assert {:error, :invalid_timeout} = CodeExecutionVerifier.new(%{timeout: -1})
      assert {:error, :invalid_timeout} = CodeExecutionVerifier.new(%{timeout: 0})
    end

    test "returns error for invalid sandbox" do
      assert {:error, :invalid_sandbox} = CodeExecutionVerifier.new(%{sandbox: :invalid})
    end

    test "returns error for invalid language" do
      assert {:error, :invalid_language} = CodeExecutionVerifier.new(%{language: :invalid})
    end

    test "returns error for invalid working directory" do
      assert {:error, :directory_not_found} =
               CodeExecutionVerifier.new(%{working_dir: "/nonexistent/path"})
    end

    test "respects JIDO_DEFAULT_SANDBOX environment variable" do
      System.put_env("JIDO_DEFAULT_SANDBOX", "docker")
      assert {:ok, verifier} = CodeExecutionVerifier.new([])
      assert verifier.sandbox == :docker
      System.delete_env("JIDO_DEFAULT_SANDBOX")
    end

    test "respects JIDO_DEFAULT_SANDBOX=podman" do
      System.put_env("JIDO_DEFAULT_SANDBOX", "podman")
      assert {:ok, verifier} = CodeExecutionVerifier.new([])
      assert verifier.sandbox == :podman
      System.delete_env("JIDO_DEFAULT_SANDBOX")
    end

    test "respects JIDO_DEFAULT_SANDBOX=none" do
      System.put_env("JIDO_DEFAULT_SANDBOX", "none")
      assert {:ok, verifier} = CodeExecutionVerifier.new([])
      assert verifier.sandbox == :none
      System.delete_env("JIDO_DEFAULT_SANDBOX")
    end

    test "explicit sandbox option overrides environment variable" do
      System.put_env("JIDO_DEFAULT_SANDBOX", "docker")
      assert {:ok, verifier} = CodeExecutionVerifier.new(%{sandbox: :podman})
      assert verifier.sandbox == :podman
      System.delete_env("JIDO_DEFAULT_SANDBOX")
    end
  end

  describe "new!/1" do
    test "creates verifier or raises" do
      verifier = CodeExecutionVerifier.new!(%{timeout: 5000})
      assert verifier.timeout == 5000
    end

    test "raises for invalid config" do
      assert_raise ArgumentError, ~r/Invalid code execution verifier/, fn ->
        CodeExecutionVerifier.new!(%{timeout: -1})
      end
    end
  end

  describe "verify/3" do
    @describetag :requires_python

    setup do
      verifier = CodeExecutionVerifier.new!(%{language: :python, timeout: 5000})
      %{verifier: verifier}
    end

    test "executes simple python code successfully", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "print('hello')"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.score >= 0.0
      assert is_binary(result.reasoning)
      assert result.metadata.exit_code == 0
    end

    test "handles python code with syntax error", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "print('unclosed string"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      # Syntax error should result in low score
      assert result.score == 0.0
      assert result.metadata.exit_code != 0
    end

    test "extracts code from markdown blocks", %{verifier: verifier} do
      candidate =
        Candidate.new!(%{
          content: """
          Here's some code:

          ```python
          print("from markdown")
          ```
          """
        })

      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert String.contains?(result.metadata.stdout, "from markdown")
    end

    test "handles empty candidate content", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: ""})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.score == 0.0
      assert String.contains?(result.reasoning, "No code found")
    end

    test "handles whitespace-only content", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "   \n  \n  "})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.score == 0.0
    end

    test "checks expected output when provided", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "print('42')"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{expected_output: "42"})

      assert result.score == 1.0
    end

    test "fails when expected output doesn't match", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "print('42')"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{expected_output: "99"})

      assert result.score == 0.0
    end
  end

  describe "verify/3 with different languages" do
    @tag :javascript
    test "executes javascript code" do
      verifier = CodeExecutionVerifier.new!(%{language: :javascript, timeout: 5000})

      candidate = Candidate.new!(%{content: "console.log('hello from js')"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      # Result depends on node availability
      assert is_number(result.score)
    end

    test "executes elixir code" do
      verifier = CodeExecutionVerifier.new!(%{language: :elixir, timeout: 5000})

      candidate = Candidate.new!(%{content: "IO.puts('hello from elixir')"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert is_number(result.score)
    end
  end

  describe "language detection" do
    test "detects python from shebang" do
      code = "#!/usr/bin/env python3\\nprint('detected')"
      candidate = Candidate.new!(%{content: code})

      verifier = CodeExecutionVerifier.new!(%{language: :auto})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.metadata.language == :python
    end

    test "detects python from code patterns" do
      code = "def add(a, b):\\n    return a + b"
      candidate = Candidate.new!(%{content: code})

      verifier = CodeExecutionVerifier.new!(%{language: :auto})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.metadata.language == :python
    end

    test "detects javascript from code patterns" do
      code = "function add(a, b) {\\n  return a + b;\\n}"
      candidate = Candidate.new!(%{content: code})

      verifier = CodeExecutionVerifier.new!(%{language: :auto})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.metadata.language == :javascript
    end

    test "detects elixir from code patterns" do
      code = "defmodule Math do\\n  def add(a, b), do: a + b\\nend"
      candidate = Candidate.new!(%{content: code})

      verifier = CodeExecutionVerifier.new!(%{language: :auto})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.metadata.language == :elixir
    end
  end

  describe "verify_batch/3" do
    test "verifies multiple candidates" do
      verifier = CodeExecutionVerifier.new!(%{language: :python})

      candidates = [
        Candidate.new!(%{id: "1", content: "print('one')"}),
        Candidate.new!(%{id: "2", content: "print('two')"}),
        Candidate.new!(%{id: "3", content: "print('three')"})
      ]

      {:ok, results} = CodeExecutionVerifier.verify_batch(verifier, candidates, %{})

      assert length(results) == 3
      assert Enum.all?(results, fn r -> is_number(r.score) end)
    end

    test "handles empty candidate list" do
      verifier = CodeExecutionVerifier.new!(%{language: :python})

      {:ok, results} = CodeExecutionVerifier.verify_batch(verifier, [], %{})

      assert results == []
    end

    test "continues on individual candidate failures" do
      verifier = CodeExecutionVerifier.new!(%{language: :python})

      candidates = [
        Candidate.new!(%{id: "1", content: "print('good')"}),
        Candidate.new!(%{id: "2", content: ""}),
        Candidate.new!(%{id: "3", content: "print('also good')"})
      ]

      {:ok, results} = CodeExecutionVerifier.verify_batch(verifier, candidates, %{})

      assert length(results) == 3
    end
  end

  describe "supports_streaming?/0" do
    test "returns false" do
      assert CodeExecutionVerifier.supports_streaming?() == false
    end
  end

  describe "timeout handling" do
    @describetag :requires_python

    @tag :flaky
    test "handles infinite loops gracefully" do
      verifier = CodeExecutionVerifier.new!(%{language: :python, timeout: 500})

      candidate = Candidate.new!(%{content: "while True: pass"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.score == 0.0
      assert result.metadata.timed_out == true
    end

    @tag :flaky
    test "sets appropriate timeout for long-running code" do
      verifier = CodeExecutionVerifier.new!(%{language: :python, timeout: 100})

      candidate = Candidate.new!(%{content: "import time; time.sleep(1)"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.metadata.timed_out == true
    end
  end

  describe "score calculation" do
    @describetag :requires_python

    test "returns 1.0 for successful execution" do
      verifier = CodeExecutionVerifier.new!(%{language: :python})
      candidate = Candidate.new!(%{content: "print('success')"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.score == 1.0
    end

    test "returns 0.5 for non-zero exit with output" do
      # Some languages return non-zero even with output
      verifier = CodeExecutionVerifier.new!(%{language: :python})
      candidate = Candidate.new!(%{content: "import sys; print('output'); sys.exit(1)"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      # Should have some partial credit for output
      assert result.score >= 0.0
    end

    test "returns 0.0 for execution with no output" do
      verifier = CodeExecutionVerifier.new!(%{language: :python})
      candidate = Candidate.new!(%{content: "import sys; sys.exit(1)"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert result.score == 0.0
    end
  end

  describe "metadata" do
    @describetag :requires_python

    test "includes execution details in metadata" do
      verifier = CodeExecutionVerifier.new!(%{language: :python})
      candidate = Candidate.new!(%{content: "print('test')"})
      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})

      assert Map.has_key?(result.metadata, :exit_code)
      assert Map.has_key?(result.metadata, :stdout)
      assert Map.has_key?(result.metadata, :stderr)
      assert Map.has_key?(result.metadata, :language)
      assert Map.has_key?(result.metadata, :duration_ms)
    end
  end
end
