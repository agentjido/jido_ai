defmodule Jido.Eval.Reporter do
  @moduledoc """
  Behavior for reporting evaluation results.

  Reporters handle the output of evaluation results, either for individual samples
  or complete evaluation summaries. They can format and display results to various
  destinations like console, files, or external services.

  ## Callbacks

  - `c:handle_summary/2` - Process complete evaluation summary (required)
  - `c:handle_sample/2` - Process individual sample result (optional)

  ## Examples

      defmodule MyReporter do
        @behaviour Jido.Eval.Reporter
        
        def handle_summary(summary, _opts) do
          IO.puts("Evaluation completed with \#{summary.total_samples} samples")
          :ok
        end
        
        def handle_sample(sample, _opts) do
          IO.puts("Sample \#{sample.id}: \#{sample.score}")
          :ok
        end
      end
  """

  @doc """
  Handle evaluation summary.

  Called when an evaluation run completes with the final summary.

  ## Parameters

  - `summary` - The evaluation summary data
  - `opts` - Reporter configuration options

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Error occurred
  """
  @callback handle_summary(summary :: any(), opts :: keyword()) ::
              :ok | {:error, any()}

  @doc """
  Handle individual sample result.

  Called for each evaluated sample during the run.

  ## Parameters

  - `sample` - The sample result data
  - `opts` - Reporter configuration options

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Error occurred
  """
  @callback handle_sample(sample :: any(), opts :: keyword()) ::
              :ok | {:error, any()}

  @optional_callbacks handle_sample: 2
end
