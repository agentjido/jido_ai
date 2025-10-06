defmodule Jido.AI.Features.CodeExecutionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Features.CodeExecution
  alias Jido.AI.Model

  describe "supports?/1" do
    test "returns true for OpenAI GPT-4 models" do
      model = %Model{provider: :openai, model: "gpt-4-0613"}
      assert CodeExecution.supports?(model)
    end

    test "returns true for OpenAI GPT-4 Turbo models" do
      model = %Model{provider: :openai, model: "gpt-4-turbo-preview"}
      assert CodeExecution.supports?(model)
    end

    test "returns true for OpenAI GPT-3.5 models" do
      model = %Model{provider: :openai, model: "gpt-3.5-turbo"}
      assert CodeExecution.supports?(model)
    end

    test "returns false for Anthropic models" do
      model = %Model{provider: :anthropic, model: "claude-3-sonnet"}
      refute CodeExecution.supports?(model)
    end

    test "returns false for Google models" do
      model = %Model{provider: :google, model: "gemini-pro"}
      refute CodeExecution.supports?(model)
    end

    test "returns false for Cohere models" do
      model = %Model{provider: :cohere, model: "command-r"}
      refute CodeExecution.supports?(model)
    end

    test "returns false for local models" do
      model = %Model{provider: :ollama, model: "llama2"}
      refute CodeExecution.supports?(model)
    end
  end

  describe "build_code_exec_options/3" do
    setup do
      base_opts = %{temperature: 0.7, max_tokens: 500}
      {:ok, base_opts: base_opts}
    end

    test "returns error when not explicitly enabled", %{base_opts: base_opts} do
      assert {:error, :not_enabled} = CodeExecution.build_code_exec_options(base_opts, :openai)
    end

    test "returns error when enable is false", %{base_opts: base_opts} do
      assert {:error, :not_enabled} =
               CodeExecution.build_code_exec_options(base_opts, :openai, enable: false)
    end

    test "adds code interpreter tool for OpenAI when enabled", %{base_opts: base_opts} do
      {:ok, opts} = CodeExecution.build_code_exec_options(base_opts, :openai, enable: true)

      assert opts.temperature == 0.7
      assert opts.max_tokens == 500
      assert opts.tools == [%{type: "code_interpreter"}]
    end

    test "preserves base options when enabled", %{base_opts: base_opts} do
      {:ok, opts} = CodeExecution.build_code_exec_options(base_opts, :openai, enable: true)

      assert Map.has_key?(opts, :temperature)
      assert Map.has_key?(opts, :max_tokens)
    end

    test "adds timeout when specified", %{base_opts: base_opts} do
      {:ok, opts} =
        CodeExecution.build_code_exec_options(base_opts, :openai, enable: true, timeout: 60)

      assert opts.timeout == 60
    end

    test "does not add timeout when not specified", %{base_opts: base_opts} do
      {:ok, opts} = CodeExecution.build_code_exec_options(base_opts, :openai, enable: true)

      refute Map.has_key?(opts, :timeout)
    end

    test "returns error for unsupported provider", %{base_opts: base_opts} do
      assert {:error, :unsupported} =
               CodeExecution.build_code_exec_options(base_opts, :anthropic, enable: true)
    end

    test "returns error for Cohere even when enabled", %{base_opts: base_opts} do
      assert {:error, :unsupported} =
               CodeExecution.build_code_exec_options(base_opts, :cohere, enable: true)
    end
  end

  describe "extract_results/2" do
    test "extracts code execution results from OpenAI response" do
      response = %{
        "tool_calls" => [
          %{
            "type" => "code_interpreter",
            "code_interpreter" => %{
              "input" => "print('Hello, World!')",
              "output" => "Hello, World!\n",
              "logs" => ["Executing code..."],
              "files" => ["output.txt"]
            }
          }
        ]
      }

      {:ok, results} = CodeExecution.extract_results(response, :openai)

      assert length(results) == 1
      result = Enum.at(results, 0)
      assert result.input == "print('Hello, World!')"
      assert result.output == "Hello, World!\n"
      assert result.logs == ["Executing code..."]
      assert result.files == ["output.txt"]
    end

    test "extracts multiple code execution results" do
      response = %{
        "tool_calls" => [
          %{
            "type" => "code_interpreter",
            "code_interpreter" => %{
              "input" => "x = 1 + 1",
              "output" => "2",
              "logs" => [],
              "files" => []
            }
          },
          %{
            "type" => "code_interpreter",
            "code_interpreter" => %{
              "input" => "print(x)",
              "output" => "2\n",
              "logs" => [],
              "files" => []
            }
          }
        ]
      }

      {:ok, results} = CodeExecution.extract_results(response, :openai)

      assert length(results) == 2
    end

    test "filters out non-code-interpreter tool calls" do
      response = %{
        "tool_calls" => [
          %{
            "type" => "function",
            "function" => %{"name" => "get_weather"}
          },
          %{
            "type" => "code_interpreter",
            "code_interpreter" => %{
              "input" => "print('test')",
              "output" => "test\n",
              "logs" => [],
              "files" => []
            }
          }
        ]
      }

      {:ok, results} = CodeExecution.extract_results(response, :openai)

      assert length(results) == 1
      assert Enum.at(results, 0).input == "print('test')"
    end

    test "returns empty list for response without tool_calls" do
      response = %{"content" => "Regular response"}

      {:ok, results} = CodeExecution.extract_results(response, :openai)

      assert results == []
    end

    test "handles missing optional fields in code_interpreter" do
      response = %{
        "tool_calls" => [
          %{
            "type" => "code_interpreter",
            "code_interpreter" => %{
              "input" => "print('minimal')"
            }
          }
        ]
      }

      {:ok, results} = CodeExecution.extract_results(response, :openai)

      assert length(results) == 1
      result = Enum.at(results, 0)
      assert result.input == "print('minimal')"
      assert result.output == ""
      assert result.logs == []
      assert result.files == []
    end

    test "returns empty list for unsupported provider" do
      response = %{"content" => "Response from Anthropic"}

      {:ok, results} = CodeExecution.extract_results(response, :anthropic)

      assert results == []
    end
  end

  describe "safety_check/0" do
    test "returns safe in development environment" do
      if Mix.env() != :prod do
        assert {:ok, :safe} = CodeExecution.safety_check()
      end
    end

    test "returns error in production environment" do
      if Mix.env() == :prod do
        assert {:error, concerns} = CodeExecution.safety_check()
        assert "Running in production environment" in concerns
      end
    end
  end
end
