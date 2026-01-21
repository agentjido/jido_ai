defmodule Examples.ChainOfThought.DataAnalysisWorkflow do
  @moduledoc """
  Complete workflow using Chain-of-Thought for multi-step data analysis.

  This example demonstrates how to use CoT reasoning to orchestrate a complex
  data pipeline with multiple sequential operations.

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

  1. **Load Data** - Import data from source
  2. **Filter Data** - Apply filtering conditions
  3. **Aggregate Data** - Calculate metrics
  4. **Generate Report** - Create summary

  Each step uses CoT reasoning to understand its role in the pipeline
  and validate its output before proceeding.
  """

  require Logger

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
    IO.puts("  Chain-of-Thought Data Analysis Workflow")
    IO.puts(String.duplicate("=", 70) <> "\n")

    # Step 1: Initialize workflow
    IO.puts("📋 **Step 1: Initialize Workflow**")
    IO.puts("   Setting up data pipeline with CoT reasoning...\n")

    # Step 2: Generate reasoning plan
    IO.puts("🧠 **Step 2: Generate Reasoning Plan**")

    case generate_reasoning_plan() do
      {:ok, plan} ->
        display_reasoning_plan(plan)

        # Step 3: Execute workflow with reasoning
        IO.puts("\n⚙️  **Step 3: Execute Workflow**\n")

        case execute_workflow_with_reasoning(@sample_data, plan) do
          {:ok, results} ->
            # Step 4: Display results
            IO.puts("\n✅ **Step 4: Results**\n")
            display_results(results)

            # Step 5: Validate against plan
            IO.puts("\n🔍 **Step 5: Validation**\n")
            validate_results(results, plan)

            {:ok, results}

          {:error, reason} ->
            IO.puts("\n❌ **Workflow Failed:** #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("❌ **Planning Failed:** #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Run analysis on custom data.
  """
  def run_analysis(data, opts \\ []) do
    filter_condition = Keyword.get(opts, :filter, fn _ -> true end)
    aggregation = Keyword.get(opts, :aggregate, :average)

    case generate_reasoning_plan() do
      {:ok, plan} ->
        execute_workflow_with_reasoning(data, plan, filter_condition, aggregation)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private Functions

  defp generate_reasoning_plan do
    # In production, this would call an LLM to generate the plan
    # For demonstration, we'll create a structured plan

    plan = %{
      goal: "Analyze sales data to identify trends and calculate key metrics",
      analysis: """
      This workflow processes transaction data through multiple stages:
      1. Load raw data from source
      2. Filter data based on specified conditions
      3. Aggregate filtered data to calculate metrics
      4. Generate summary report with insights

      Expected flow: Raw Data → Filtered Data → Aggregated Metrics → Report
      """,
      steps: [
        %{
          number: 1,
          name: "load_data",
          description: "Load raw data from source",
          expected_outcome: "List of transaction records with all fields populated",
          validation: "Verify all records have required fields (id, value, category)",
          potential_issues: ["Missing data", "Invalid format"]
        },
        %{
          number: 2,
          name: "filter_data",
          description: "Filter data based on conditions (value > 15)",
          expected_outcome: "Subset of data meeting filter criteria",
          validation: "Ensure all returned records satisfy filter condition",
          potential_issues: ["Empty result set", "Filter logic errors"]
        },
        %{
          number: 3,
          name: "aggregate_data",
          description: "Calculate aggregate metrics (average, sum, count)",
          expected_outcome: "Numerical metrics summarizing the filtered data",
          validation: "Verify calculations are mathematically correct",
          potential_issues: ["Division by zero", "Numerical overflow"]
        },
        %{
          number: 4,
          name: "generate_report",
          description: "Create summary report with findings",
          expected_outcome: "Formatted report with insights and recommendations",
          validation: "Report includes all required sections",
          potential_issues: ["Missing insights", "Formatting errors"]
        }
      ],
      dependencies: %{
        "load_data" => [],
        "filter_data" => ["load_data"],
        "aggregate_data" => ["filter_data"],
        "generate_report" => ["aggregate_data"]
      },
      expected_results: "Summary report showing average value of filtered transactions with insights"
    }

    {:ok, plan}
  end

  defp execute_workflow_with_reasoning(data, plan, filter_fn \\ nil, agg_type \\ :average) do
    # Track execution state
    state = %{
      data: nil,
      filtered_data: nil,
      metrics: nil,
      report: nil,
      step_results: []
    }

    # Execute each step in sequence with reasoning context
    with {:ok, state} <- execute_step(:load_data, state, plan, data),
         {:ok, state} <- execute_step(:filter_data, state, plan, filter_fn),
         {:ok, state} <- execute_step(:aggregate_data, state, plan, agg_type),
         {:ok, state} <- execute_step(:generate_report, state, plan, nil) do
      {:ok,
       %{
         final_data: state.data,
         filtered_data: state.filtered_data,
         metrics: state.metrics,
         report: state.report,
         step_results: state.step_results
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_step(step_name, state, plan, step_input) do
    step_info = Enum.find(plan.steps, &(&1.name == Atom.to_string(step_name)))

    IO.puts("   📌 **#{step_info.name}**")
    IO.puts("      Description: #{step_info.description}")
    IO.puts("      Expected: #{step_info.expected_outcome}")

    case step_name do
      :load_data ->
        load_data_step(state, step_info, step_input)

      :filter_data ->
        filter_data_step(state, step_info, step_input)

      :aggregate_data ->
        aggregate_data_step(state, step_info, step_input)

      :generate_report ->
        generate_report_step(state, step_info)
    end
  end

  defp load_data_step(state, step_info, data) do
    # Simulate data loading with reasoning
    IO.puts("      → Loading data...")

    loaded_data = data || @sample_data

    # Validate data
    validation = validate_loaded_data(loaded_data, step_info)

    if validation.valid do
      IO.puts("      ✓ Loaded #{length(loaded_data)} records")

      step_result = %{
        step: step_info.number,
        name: step_info.name,
        input: "Data source",
        output: "#{length(loaded_data)} records",
        validation: validation,
        success: true
      }

      {:ok,
       %{
         state
         | data: loaded_data,
           step_results: state.step_results ++ [step_result]
       }}
    else
      IO.puts("      ✗ Validation failed: #{validation.reason}")
      {:error, {:validation_failed, validation}}
    end
  end

  defp filter_data_step(state, step_info, filter_fn) do
    IO.puts("      → Filtering data...")

    # Apply filter (default: value > 15)
    filter_function = filter_fn || fn record -> record.value > 15 end

    filtered = Enum.filter(state.data, filter_function)

    # Validate filtering
    validation = validate_filtered_data(filtered, state.data, step_info)

    if validation.valid do
      IO.puts("      ✓ Filtered to #{length(filtered)} records (from #{length(state.data)})")

      step_result = %{
        step: step_info.number,
        name: step_info.name,
        input: "#{length(state.data)} records",
        output: "#{length(filtered)} records",
        validation: validation,
        success: true
      }

      {:ok,
       %{
         state
         | filtered_data: filtered,
           step_results: state.step_results ++ [step_result]
       }}
    else
      IO.puts("      ✗ Validation failed: #{validation.reason}")
      {:error, {:validation_failed, validation}}
    end
  end

  defp aggregate_data_step(state, step_info, agg_type) do
    IO.puts("      → Calculating metrics...")

    # Calculate aggregations
    values = Enum.map(state.filtered_data, & &1.value)

    metrics = %{
      count: length(values),
      sum: Enum.sum(values),
      average: if(length(values) > 0, do: Enum.sum(values) / length(values), else: 0),
      min: if(length(values) > 0, do: Enum.min(values), else: 0),
      max: if(length(values) > 0, do: Enum.max(values), else: 0)
    }

    # Group by category
    by_category =
      state.filtered_data
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

    # Validate calculations
    validation = validate_metrics(metrics, state.filtered_data, step_info)

    if validation.valid do
      IO.puts("      ✓ Calculated #{map_size(metrics) - 1} core metrics")

      step_result = %{
        step: step_info.number,
        name: step_info.name,
        input: "#{length(state.filtered_data)} records",
        output: "Metrics: #{inspect(Map.keys(metrics))}",
        validation: validation,
        success: true
      }

      {:ok,
       %{
         state
         | metrics: metrics,
           step_results: state.step_results ++ [step_result]
       }}
    else
      IO.puts("      ✗ Validation failed: #{validation.reason}")
      {:error, {:validation_failed, validation}}
    end
  end

  defp generate_report_step(state, step_info) do
    IO.puts("      → Generating report...")

    # Generate insights based on metrics
    insights = generate_insights(state.metrics, state.filtered_data)

    # Create formatted report
    report = %{
      title: "Data Analysis Summary",
      generated_at: DateTime.utc_now(),
      dataset_info: %{
        total_records: length(state.data),
        filtered_records: length(state.filtered_data),
        filter_rate: Float.round(length(state.filtered_data) / length(state.data) * 100, 1)
      },
      metrics: state.metrics,
      insights: insights,
      recommendations: generate_recommendations(insights)
    }

    validation = %{valid: true, reason: "Report generated successfully"}

    IO.puts("      ✓ Report generated with #{length(insights)} insights")

    step_result = %{
      step: step_info.number,
      name: step_info.name,
      input: "Metrics",
      output: "Complete report",
      validation: validation,
      success: true
    }

    {:ok,
     %{
       state
       | report: report,
         step_results: state.step_results ++ [step_result]
     }}
  end

  # Validation Functions

  defp validate_loaded_data(data, _step_info) do
    cond do
      is_nil(data) or not is_list(data) ->
        %{valid: false, reason: "Data is not a valid list"}

      Enum.empty?(data) ->
        %{valid: false, reason: "Data is empty"}

      not Enum.all?(data, &Map.has_key?(&1, :value)) ->
        %{valid: false, reason: "Some records missing required 'value' field"}

      true ->
        %{valid: true, reason: "All validation checks passed"}
    end
  end

  defp validate_filtered_data(filtered, original, _step_info) do
    cond do
      not is_list(filtered) ->
        %{valid: false, reason: "Filtered result is not a list"}

      length(filtered) > length(original) ->
        %{valid: false, reason: "Filtered data larger than input (impossible)"}

      true ->
        %{valid: true, reason: "Filter operation successful"}
    end
  end

  defp validate_metrics(metrics, data, _step_info) do
    cond do
      not is_map(metrics) ->
        %{valid: false, reason: "Metrics is not a map"}

      metrics.count != length(data) ->
        %{valid: false, reason: "Count mismatch: expected #{length(data)}, got #{metrics.count}"}

      metrics.sum < 0 ->
        %{valid: false, reason: "Sum cannot be negative"}

      true ->
        %{valid: true, reason: "All metrics validated"}
    end
  end

  # Helper Functions

  defp generate_insights(metrics, _data) do
    insights = []

    # Average analysis
    insights =
      if metrics.average > 25 do
        insights ++ ["High average transaction value (#{Float.round(metrics.average, 2)})"]
      else
        insights ++
          ["Moderate average transaction value (#{Float.round(metrics.average, 2)})"]
      end

    # Range analysis
    range = metrics.max - metrics.min

    insights =
      if range > 20 do
        insights ++ ["Wide value range (#{range}) indicates diverse transaction sizes"]
      else
        insights ++ ["Narrow value range (#{range}) indicates consistent transaction sizes"]
      end

    # Category analysis
    top_category =
      metrics.by_category
      |> Enum.max_by(fn {_cat, stats} -> stats.total end)
      |> elem(0)

    insights = insights ++ ["'#{top_category}' is the highest-value category"]

    insights
  end

  defp generate_recommendations(insights) do
    recommendations = []

    # Based on insights, generate actionable recommendations
    if Enum.any?(insights, &String.contains?(&1, "High average")) do
      recommendations = recommendations ++ ["Focus on maintaining high-value transactions"]
    end

    if Enum.any?(insights, &String.contains?(&1, "Wide value range")) do
      recommendations =
        recommendations ++ ["Consider segmenting analysis by value tiers"]
    end

    if Enum.empty?(recommendations) do
      ["Continue monitoring metrics for trends"]
    else
      recommendations
    end
  end

  # Display Functions

  defp display_reasoning_plan(plan) do
    IO.puts("   Goal: #{plan.goal}")
    IO.puts("\n   Analysis:")

    plan.analysis
    |> String.split("\n")
    |> Enum.each(fn line -> IO.puts("   #{line}") end)

    IO.puts("\n   Pipeline Steps:")

    Enum.each(plan.steps, fn step ->
      IO.puts("   #{step.number}. #{step.description}")
      IO.puts("      Expected: #{step.expected_outcome}")
    end)

    IO.puts("")
  end

  defp display_results(results) do
    IO.puts("   **Final Metrics:**")
    metrics = results.metrics
    IO.puts("      • Count: #{metrics.count}")
    IO.puts("      • Sum: #{metrics.sum}")
    IO.puts("      • Average: #{Float.round(metrics.average, 2)}")
    IO.puts("      • Min: #{metrics.min}")
    IO.puts("      • Max: #{metrics.max}")

    IO.puts("\n   **By Category:**")

    Enum.each(metrics.by_category, fn {category, stats} ->
      IO.puts(
        "      • #{category}: #{stats.count} records, avg = #{Float.round(stats.average, 2)}"
      )
    end)

    IO.puts("\n   **Insights:**")

    Enum.each(results.report.insights, fn insight ->
      IO.puts("      • #{insight}")
    end)

    IO.puts("\n   **Recommendations:**")

    Enum.each(results.report.recommendations, fn rec ->
      IO.puts("      • #{rec}")
    end)
  end

  defp validate_results(results, plan) do
    IO.puts("   Validating workflow execution against plan...")

    # Check all steps completed
    expected_steps = length(plan.steps)
    actual_steps = length(results.step_results)

    if expected_steps == actual_steps do
      IO.puts("   ✓ All #{expected_steps} steps completed")
    else
      IO.puts(
        "   ✗ Step count mismatch: expected #{expected_steps}, got #{actual_steps}"
      )
    end

    # Check all validations passed
    failed_validations =
      Enum.filter(results.step_results, fn step -> not step.validation.valid end)

    if Enum.empty?(failed_validations) do
      IO.puts("   ✓ All step validations passed")
    else
      IO.puts("   ✗ #{length(failed_validations)} step(s) failed validation")
    end

    # Check final report exists
    if results.report do
      IO.puts("   ✓ Final report generated")
    else
      IO.puts("   ✗ No final report")
    end

    IO.puts("\n   📊 **Workflow Summary:**")
    IO.puts("      • Total steps: #{actual_steps}")
    IO.puts("      • Successful: #{actual_steps - length(failed_validations)}")
    IO.puts("      • Failed: #{length(failed_validations)}")

    success = expected_steps == actual_steps and Enum.empty?(failed_validations)
    IO.puts("      • Overall: #{if success, do: "✅ SUCCESS", else: "❌ FAILURE"}")
  end

  @doc """
  Show step-by-step comparison with and without CoT reasoning.
  """
  def compare_with_without_cot do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Comparison: With vs Without Chain-of-Thought")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("**WITHOUT Chain-of-Thought:**")
    IO.puts("• Execute steps directly")
    IO.puts("• No reasoning plan")
    IO.puts("• No validation between steps")
    IO.puts("• Errors only caught at the end")
    IO.puts("• No insight into why steps were taken")

    IO.puts("\n**WITH Chain-of-Thought:**")
    IO.puts("• Generate reasoning plan first")
    IO.puts("• Each step knows its purpose")
    IO.puts("• Validation after each step")
    IO.puts("• Early error detection")
    IO.puts("• Clear reasoning trace")
    IO.puts("• Easier debugging")
    IO.puts("• Better explainability")

    IO.puts("\n**Benefits of CoT in Workflows:**")
    IO.puts("✓ Improved reliability through validation")
    IO.puts("✓ Better error messages")
    IO.puts("✓ Easier to understand execution flow")
    IO.puts("✓ Facilitates debugging and optimization")
    IO.puts("✓ Increases confidence in results")
  end
end
