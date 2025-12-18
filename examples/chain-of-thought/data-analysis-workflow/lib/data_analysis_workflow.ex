defmodule Examples.ChainOfThought.DataAnalysisWorkflow do
  @moduledoc """
  Complete workflow using Chain-of-Thought for multi-step data analysis with agent-based API.

  This example demonstrates how to use the Jido AI ChainOfThought runner to orchestrate
  a complex data pipeline with multiple sequential operations using real agents and actions.

  ## Usage

      # Run the complete workflow
      Examples.ChainOfThought.DataAnalysisWorkflow.run()

      # Run with custom data
      Examples.ChainOfThought.DataAnalysisWorkflow.run_analysis([
        %{value: 10, category: "A"},
        %{value: 20, category: "B"},
        %{value: 30, category: "A"}
      ])

  ## Workflow Steps

  1. **Load Data** - Import data from source (LoadDataAction)
  2. **Filter Data** - Apply filtering conditions (FilterDataAction)
  3. **Aggregate Data** - Calculate metrics (AggregateDataAction)
  4. **Generate Report** - Create summary (GenerateReportAction)

  Each step uses CoT reasoning via the ChainOfThought runner to understand
  its role in the pipeline and validate its output before proceeding.
  """

  require Logger

  alias Jido.AI.Runner.ChainOfThought

  # Sample data for the example
  @sample_data [
    %{id: 1, value: 10, category: "electronics", date: ~D[2024-01-15]},
    %{id: 2, value: 25, category: "clothing", date: ~D[2024-01-16]},
    %{id: 3, value: 15, category: "electronics", date: ~D[2024-01-17]},
    %{id: 4, value: 30, category: "food", date: ~D[2024-01-18]},
    %{id: 5, value: 20, category: "electronics", date: ~D[2024-01-19]},
    %{id: 6, value: 35, category: "clothing", date: ~D[2024-01-20]},
    %{id: 7, value: 12, category: "food", date: ~D[2024-01-21]},
    %{id: 8, value: 28, category: "electronics", date: ~D[2024-01-22]}
  ]

  @doc """
  Run the complete data analysis workflow with Chain-of-Thought reasoning.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Chain-of-Thought Data Analysis Workflow (Agent-Based)")
    IO.puts(String.duplicate("=", 70) <> "\n")

    run_analysis(@sample_data)
  end

  @doc """
  Run analysis on custom data using agent-based ChainOfThought runner.
  """
  def run_analysis(data, opts \\ []) do
    min_value = Keyword.get(opts, :min_value, 15)

    IO.puts("📋 **Initializing Agent-Based Workflow**\n")

    # Build agent with all workflow actions as pending instructions
    agent = build_workflow_agent(data, min_value)

    IO.puts("🧠 **Executing with ChainOfThought Runner**\n")

    # Run with ChainOfThought runner for reasoning-guided execution
    case ChainOfThought.run(agent,
           mode: :structured,
           temperature: 0.3,
           enable_validation: true,
           fallback_on_error: true
         ) do
      {:ok, _updated_agent, _directives} ->
        IO.puts("\n✅ **Workflow Completed Successfully**\n")
        IO.puts("All steps executed with CoT reasoning guidance")

        {:ok, %{status: "completed", mode: "agent-based", runner: "ChainOfThought"}}

      {:error, reason} ->
        IO.puts("\n❌ **Workflow Failed:** #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private Functions

  defp build_workflow_agent(data, min_value) do
    # Create instructions for each step of the workflow
    instructions = [
      %{
        action: LoadDataAction,
        params: %{source_data: data},
        id: "step-1-load"
      },
      %{
        action: FilterDataAction,
        params: %{min_value: min_value},
        id: "step-2-filter"
      },
      %{
        action: AggregateDataAction,
        params: %{},
        id: "step-3-aggregate"
      },
      %{
        action: GenerateReportAction,
        params: %{},
        id: "step-4-report"
      }
    ]

    # Build instruction queue
    queue =
      Enum.reduce(instructions, :queue.new(), fn instruction, q ->
        :queue.in(instruction, q)
      end)

    # Create agent structure
    %{
      id: "workflow-agent-#{:rand.uniform(10000)}",
      name: "Data Analysis Workflow Agent",
      state: %{
        workflow_data: data,
        min_value: min_value
      },
      pending_instructions: queue,
      actions: [LoadDataAction, FilterDataAction, AggregateDataAction, GenerateReportAction],
      runner: ChainOfThought,
      result: nil
    }
  end

  # Workflow Action Modules

  defmodule LoadDataAction do
    @moduledoc """
    Action to load data from source.
    """

    use Jido.Action,
      name: "load_data",
      description: "Load raw data from source",
      schema: [
        source_data: [
          type: {:list, :map},
          required: true,
          doc: "The source data to load"
        ]
      ]

    def run(params, _context) do
      data = Map.get(params, :source_data, [])

      IO.puts("   📌 **LoadData**: Loading #{length(data)} records")

      # Validate data
      if Enum.all?(data, &Map.has_key?(&1, :value)) do
        IO.puts("      ✓ All records have required fields")
        {:ok, %{loaded_data: data, count: length(data)}}
      else
        {:error, "Some records missing required fields"}
      end
    end
  end

  defmodule FilterDataAction do
    @moduledoc """
    Action to filter data based on conditions.
    """

    use Jido.Action,
      name: "filter_data",
      description: "Filter data based on minimum value condition",
      schema: [
        min_value: [
          type: :integer,
          default: 15,
          doc: "Minimum value threshold for filtering"
        ]
      ]

    def run(params, context) do
      min_value = Map.get(params, :min_value, 15)

      # Get data from agent state (would normally come from previous action result)
      data = get_in(context, [:agent, :state, :workflow_data]) || []

      IO.puts("   📌 **FilterData**: Applying filter (value > #{min_value})")

      filtered = Enum.filter(data, fn record -> record.value > min_value end)

      IO.puts("      ✓ Filtered to #{length(filtered)} records (from #{length(data)})")

      {:ok, %{filtered_data: filtered, original_count: length(data), filtered_count: length(filtered)}}
    end
  end

  defmodule AggregateDataAction do
    @moduledoc """
    Action to calculate aggregate metrics.
    """

    use Jido.Action,
      name: "aggregate_data",
      description: "Calculate aggregate metrics on filtered data",
      schema: []

    def run(_params, context) do
      # Get data from agent state
      data = get_in(context, [:agent, :state, :workflow_data]) || []

      # For this demo, filter inline (in production would use previous action result)
      min_value = get_in(context, [:agent, :state, :min_value]) || 15
      filtered_data = Enum.filter(data, fn record -> record.value > min_value end)

      IO.puts("   📌 **AggregateData**: Calculating metrics on #{length(filtered_data)} records")

      values = Enum.map(filtered_data, & &1.value)

      metrics = %{
        count: length(values),
        sum: Enum.sum(values),
        average: if(length(values) > 0, do: Enum.sum(values) / length(values), else: 0),
        min: if(length(values) > 0, do: Enum.min(values), else: 0),
        max: if(length(values) > 0, do: Enum.max(values), else: 0)
      }

      # Group by category
      by_category =
        filtered_data
        |> Enum.group_by(& &1.category)
        |> Enum.map(fn {category, records} ->
          {category,
           %{
             count: length(records),
             total: Enum.sum(Enum.map(records, & &1.value)),
             average: Enum.sum(Enum.map(records, & &1.value)) / length(records)
           }}
        end)
        |> Enum.into(%{})

      metrics = Map.put(metrics, :by_category, by_category)

      IO.puts("      ✓ Calculated #{map_size(metrics) - 1} core metrics")

      {:ok, %{metrics: metrics}}
    end
  end

  defmodule GenerateReportAction do
    @moduledoc """
    Action to generate summary report.
    """

    use Jido.Action,
      name: "generate_report",
      description: "Generate summary report with insights",
      schema: []

    def run(_params, context) do
      # Get data from agent state
      data = get_in(context, [:agent, :state, :workflow_data]) || []
      min_value = get_in(context, [:agent, :state, :min_value]) || 15
      filtered_data = Enum.filter(data, fn record -> record.value > min_value end)

      IO.puts("   📌 **GenerateReport**: Creating summary report")

      values = Enum.map(filtered_data, & &1.value)
      avg = if length(values) > 0, do: Enum.sum(values) / length(values), else: 0

      insights = []

      insights =
        if avg > 25 do
          insights ++ ["High average transaction value (#{Float.round(avg, 2)})"]
        else
          insights ++ ["Moderate average transaction value (#{Float.round(avg, 2)})"]
        end

      report = %{
        title: "Data Analysis Summary",
        generated_at: DateTime.utc_now(),
        dataset_info: %{
          total_records: length(data),
          filtered_records: length(filtered_data),
          filter_rate: Float.round(length(filtered_data) / length(data) * 100, 1)
        },
        insights: insights
      }

      IO.puts("      ✓ Report generated with #{length(insights)} insights")

      {:ok, %{report: report}}
    end
  end
end
