defmodule ReqLLM.CapabilityTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ReqLLM.Capability
  alias ReqLLM.Capability.Result

  copy(ReqLLM.Model)
  copy(ReqLLM.Capability.Reporter)
  copy(ReqLLM.Capability.GenerateText)
  copy(ReqLLM.Capability.StreamText)
  copy(ReqLLM.Capability.ToolCalling)
  copy(ReqLLM.Capability.Reasoning)

  setup :verify_on_exit!
  setup :set_mimic_global

  describe "verify/2" do
    test "returns :ok when all capabilities pass" do
      ReqLLM.Capability
      |> expect(:verify, fn "openai:gpt-4", [] -> :ok end)

      assert Capability.verify("openai:gpt-4") == :ok
    end

    test "returns :error when model loading fails" do
      ReqLLM.Model
      |> expect(:with_metadata, fn "invalid:model" -> {:error, "Model not found"} end)

      assert Capability.verify("invalid:model") == :error
    end

    test "returns :error when checks fail" do
      model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        capabilities: %{tool_call?: true}
      }

      failed_results = [
        %Result{
          status: :failed,
          model: "openai:gpt-4",
          capability: :generate_text,
          latency_ms: 50,
          details: "test failure"
        }
      ]

      ReqLLM.Model
      |> expect(:with_metadata, fn "openai:gpt-4" -> {:ok, model} end)

      ReqLLM.Capability
      |> expect(:discover_capabilities, fn ^model, [] ->
        {:ok, [ReqLLM.Capability.GenerateText]}
      end)
      |> expect(:run_checks, fn [ReqLLM.Capability.GenerateText], ^model, [] -> failed_results end)

      ReqLLM.Capability.Reporter
      |> expect(:dispatch, fn results, _opts ->
        assert Enum.any?(results, &match?(%Result{status: :failed}, &1))
        :ok
      end)

      assert Capability.verify("openai:gpt-4") == :error
    end

    test "passes options to run_checks" do
      model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        capabilities: %{tool_call?: true}
      }

      passed_results = [
        %Result{
          status: :passed,
          model: "openai:gpt-4",
          capability: :generate_text,
          latency_ms: 100,
          details: "success"
        }
      ]

      timeout_opts = [timeout: 30_000]

      ReqLLM.Model
      |> expect(:with_metadata, fn "openai:gpt-4" -> {:ok, model} end)

      ReqLLM.Capability
      |> expect(:discover_capabilities, fn ^model, ^timeout_opts ->
        {:ok, [ReqLLM.Capability.GenerateText]}
      end)
      |> expect(:run_checks, fn [ReqLLM.Capability.GenerateText], ^model, ^timeout_opts ->
        passed_results
      end)

      ReqLLM.Capability.Reporter
      |> expect(:dispatch, fn _results, opts ->
        assert opts[:timeout] == 30_000
        :ok
      end)

      assert Capability.verify("openai:gpt-4", timeout: 30_000) == :ok
    end
  end

  describe "discover_capabilities/2" do
    test "returns all advertised capabilities when no filter" do
      model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        capabilities: %{tool_call?: true}
      }

      {:ok, capabilities} = Capability.discover_capabilities(model, [])

      assert length(capabilities) >= 2
      capability_ids = Enum.map(capabilities, & &1.id())
      assert :generate_text in capability_ids
    end

    test "filters capabilities by --only option" do
      model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        capabilities: %{tool_call?: true}
      }

      {:ok, capabilities} = Capability.discover_capabilities(model, only: [:generate_text])

      assert length(capabilities) == 1
      assert hd(capabilities).id() == :generate_text
    end

    test "handles string --only option" do
      model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        capabilities: %{tool_call?: true}
      }

      {:ok, capabilities} = Capability.discover_capabilities(model, only: "generate_text")

      assert length(capabilities) == 1
      assert hd(capabilities).id() == :generate_text
    end

    test "returns error when no capabilities match filter" do
      model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        capabilities: %{tool_call?: true}
      }

      {:error, message} = Capability.discover_capabilities(model, only: [:nonexistent])

      assert message =~ "No capabilities to verify"
    end

    test "handles non-existent atoms in filter gracefully" do
      model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        capabilities: %{tool_call?: true}
      }

      {:error, message} =
        Capability.discover_capabilities(model, only: ["nonexistent_capability"])

      assert message =~ "No capabilities to verify"
    end
  end

  describe "run_checks/3" do
    test "returns results for all capabilities" do
      model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}
      capabilities = [ReqLLM.Capability.GenerateText]

      ReqLLM.Capability.GenerateText
      |> expect(:verify, fn _model, _opts -> {:ok, "success"} end)
      |> expect(:id, fn -> :generate_text end)

      results = Capability.run_checks(capabilities, model, [])

      assert length(results) == 1
      result = hd(results)

      assert %Result{
               status: :passed,
               model: "openai:gpt-4",
               capability: :generate_text,
               details: "success"
             } = result

      assert result.latency_ms >= 0
    end

    test "handles capability failures" do
      model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}
      capabilities = [ReqLLM.Capability.GenerateText]

      ReqLLM.Capability.GenerateText
      |> expect(:verify, fn _model, _opts -> {:error, "test failure"} end)
      |> expect(:id, fn -> :generate_text end)

      results = Capability.run_checks(capabilities, model, [])

      assert length(results) == 1
      result = hd(results)

      assert %Result{
               status: :failed,
               details: "test failure"
             } = result
    end

    test "supports fail_fast option" do
      model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}
      capabilities = [ReqLLM.Capability.GenerateText, ReqLLM.Capability.StreamText]

      # First capability fails
      ReqLLM.Capability.GenerateText
      |> expect(:verify, fn _model, _opts -> {:error, "first failure"} end)
      |> expect(:id, fn -> :generate_text end)

      # Second capability should not be called due to fail_fast
      ReqLLM.Capability.StreamText
      |> reject(:verify, 2)
      |> reject(:id, 0)

      results = Capability.run_checks(capabilities, model, fail_fast: true)

      # Only first result should be present
      assert length(results) == 1
      assert %Result{status: :failed} = hd(results)
    end

    test "measures latency for each capability" do
      model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}
      capabilities = [ReqLLM.Capability.GenerateText]

      ReqLLM.Capability.GenerateText
      |> expect(:verify, fn _model, _opts ->
        # Add small delay
        Process.sleep(10)
        {:ok, "success"}
      end)
      |> expect(:id, fn -> :generate_text end)

      results = Capability.run_checks(capabilities, model, [])

      assert hd(results).latency_ms >= 10
    end
  end
end
