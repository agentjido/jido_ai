defmodule Jido.AI.Accuracy.PipelineStageTest do
  @moduledoc """
  Tests for the PipelineStage behavior.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.PipelineStage

  describe "pipeline_stage?/1" do
    test "returns true for modules implementing the behavior" do
      # A test stage that implements the behavior
      defmodule TestStage do
        @behaviour PipelineStage

        @impl PipelineStage
        def name, do: :test_stage

        @impl PipelineStage
        def execute(_input, _config), do: {:ok, %{}, %{}}

        @impl PipelineStage
        def required?, do: true
      end

      assert PipelineStage.pipeline_stage?(TestStage)
    end

    test "returns false for modules not implementing the behavior" do
      refute PipelineStage.pipeline_stage?(String)
      refute PipelineStage.pipeline_stage?(List)
    end

    test "returns false for non-atom input" do
      refute PipelineStage.pipeline_stage?(nil)
      refute PipelineStage.pipeline_stage?("string")
    end
  end

  describe "execute_with_timeout/4" do
    defmodule FastStage do
      @behaviour PipelineStage

      @impl PipelineStage
      def name, do: :fast_stage

      @impl PipelineStage
      def execute(input, _config) do
        {:ok, Map.put(input, :fast_stage_ran, true), %{duration_ms: 1}}
      end
    end

    defmodule SlowStage do
      @behaviour PipelineStage

      @impl PipelineStage
      def name, do: :slow_stage

      @impl PipelineStage
      def execute(_input, _config) do
        Process.sleep(200)
        {:ok, %{}, %{duration_ms: 200}}
      end
    end

    defmodule ErrorStage do
      @behaviour PipelineStage

      @impl PipelineStage
      def name, do: :error_stage

      @impl PipelineStage
      def execute(_input, _config) do
        {:error, :stage_error}
      end
    end

    test "executes stage and returns result with duration" do
      input = %{query: "test"}
      config = %{}

      assert {:ok, state, metadata} = PipelineStage.execute_with_timeout(FastStage, input, config, 1000)
      assert Map.get(state, :fast_stage_ran) == true
      assert metadata.duration_ms >= 0
    end

    test "returns timeout error when stage exceeds timeout" do
      input = %{query: "test"}
      config = %{}

      assert {:error, :timeout} = PipelineStage.execute_with_timeout(SlowStage, input, config, 50)
    end

    test "returns stage error when stage fails" do
      input = %{query: "test"}
      config = %{}

      assert {:error, :stage_error} = PipelineStage.execute_with_timeout(ErrorStage, input, config)
    end

    test "includes duration_ms in metadata" do
      input = %{query: "test"}
      config = %{}

      assert {:ok, _state, metadata} = PipelineStage.execute_with_timeout(FastStage, input, config, 1000)
      assert is_integer(Map.get(metadata, :duration_ms))
      assert Map.get(metadata, :duration_ms) >= 0
    end
  end
end
