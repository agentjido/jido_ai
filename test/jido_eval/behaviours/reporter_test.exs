defmodule Jido.Eval.ReporterTest do
  use ExUnit.Case, async: true

  alias Jido.Eval.Reporter

  defmodule TestReporter do
    @behaviour Reporter

    def handle_summary(summary, opts) do
      send(self(), {:summary, summary, opts})
      :ok
    end

    def handle_sample(sample, opts) do
      send(self(), {:sample, sample, opts})
      :ok
    end
  end

  defmodule MinimalReporter do
    @behaviour Reporter

    def handle_summary(summary, _opts) do
      send(self(), {:summary_only, summary})
      :ok
    end
  end

  defmodule ErrorReporter do
    @behaviour Reporter

    def handle_summary(_summary, _opts) do
      {:error, :summary_failed}
    end

    def handle_sample(_sample, _opts) do
      {:error, :sample_failed}
    end
  end

  describe "behaviour implementation" do
    test "TestReporter implements required callback" do
      assert TestReporter.handle_summary(%{total: 10}, []) == :ok
      assert_received {:summary, %{total: 10}, []}
    end

    test "TestReporter implements optional callback" do
      assert TestReporter.handle_sample(%{id: 1, score: 0.8}, []) == :ok
      assert_received {:sample, %{id: 1, score: 0.8}, []}
    end

    test "MinimalReporter works without optional callback" do
      assert MinimalReporter.handle_summary(%{total: 5}, []) == :ok
      assert_received {:summary_only, %{total: 5}}
    end

    test "ErrorReporter returns errors properly" do
      assert ErrorReporter.handle_summary(%{}, []) == {:error, :summary_failed}
      assert ErrorReporter.handle_sample(%{}, []) == {:error, :sample_failed}
    end
  end

  describe "behaviour validation" do
    test "behaviour callbacks are defined" do
      callbacks = Reporter.behaviour_info(:callbacks)

      assert {:handle_summary, 2} in callbacks
      assert {:handle_sample, 2} in callbacks
    end

    test "optional callbacks are defined" do
      optional_callbacks = Reporter.behaviour_info(:optional_callbacks)

      assert {:handle_sample, 2} in optional_callbacks
    end
  end
end
