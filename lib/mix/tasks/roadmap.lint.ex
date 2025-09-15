defmodule Mix.Tasks.Roadmap.Lint do
  @moduledoc """
  Validate roadmap files for consistency and correctness.

  ## Examples

      mix roadmap.lint
      mix roadmap.lint --project jido
      mix roadmap.lint --fix

  """

  use Mix.Task

  alias JidoWorkspace.Roadmap.{Scanner, Parser}

  @shortdoc "Validate roadmap files"

  @switches [
    project: :string,
    fix: :boolean
  ]

  def run(args) do
    {opts, _args} = OptionParser.parse!(args, switches: @switches)

    files = 
      if opts[:project] do
        Scanner.scan_project(opts[:project])
      else
        Scanner.scan_all()
      end

    errors = validate_files(files)

    if Enum.empty?(errors) do
      Mix.shell().info("✅ All roadmap files are valid!")
    else
      display_errors(errors)
      
      if opts[:fix] do
        fix_errors(errors)
      else
        Mix.shell().error("\n❌ Found #{length(errors)} validation errors. Use --fix to attempt automatic fixes.")
        System.halt(1)
      end
    end
  end

  defp validate_files(file_paths) do
    file_paths
    |> Enum.flat_map(&validate_single_file/1)
  end

  defp validate_single_file(path) do
    errors = []

    # Check if file exists
    errors = 
      if not File.exists?(path) do
        [{:error, :missing_file, path, "File does not exist"}] ++ errors
      else
        errors
      end

    # Parse and validate content
    case Parser.parse_file(path) do
      {:ok, file} ->
        errors ++ validate_file_content(file)
      
      {:error, reason} ->
        [{:error, :parse_error, path, "Failed to parse: #{reason}"}] ++ errors
    end
  end

  defp validate_file_content(file) do
    errors = []
    
    # Validate front-matter
    errors = errors ++ validate_frontmatter(file)
    
    # Validate task IDs are unique
    errors = errors ++ validate_task_ids(file)
    
    # Validate completed tasks in done files
    errors = errors ++ validate_completed_status(file)
    
    errors
  end

  defp validate_frontmatter(file) do
    errors = []
    
    required_keys = [:project, :status]
    
    missing_keys = 
      required_keys
      |> Enum.filter(fn key -> not Map.has_key?(file.meta, key) end)
    
    if not Enum.empty?(missing_keys) do
      error = {:warning, :missing_metadata, file.path, "Missing required keys: #{inspect(missing_keys)}"}
      [error] ++ errors
    else
      errors
    end
  end

  defp validate_task_ids(file) do
    task_ids = 
      file.tasks
      |> Enum.filter(&(&1.id != nil))
      |> Enum.map(& &1.id)
    
    duplicates = 
      task_ids
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, _count} -> id end)
    
    if not Enum.empty?(duplicates) do
      error = {:error, :duplicate_ids, file.path, "Duplicate task IDs: #{Enum.join(duplicates, ", ")}"}
      [error]
    else
      []
    end
  end

  defp validate_completed_status(file) do
    if Map.get(file.meta, :status) == "done" do
      incomplete_tasks = 
        file.tasks
        |> Enum.filter(&(not &1.completed))
      
      if not Enum.empty?(incomplete_tasks) do
        task_titles = Enum.map(incomplete_tasks, & &1.title) |> Enum.take(3)
        error = {:warning, :incomplete_tasks, file.path, "File marked as 'done' but has incomplete tasks: #{Enum.join(task_titles, ", ")}..."}
        [error]
      else
        []
      end
    else
      []
    end
  end

  defp display_errors(errors) do
    Mix.shell().info("🔍 Roadmap Validation Report")
    Mix.shell().info("═" <> String.duplicate("═", 40))
    
    errors
    |> Enum.group_by(fn {level, _type, _path, _msg} -> level end)
    |> Enum.each(fn {level, level_errors} ->
      icon = case level do
        :error -> "❌"
        :warning -> "⚠️"
      end
      
      Mix.shell().info("\n#{icon} #{String.upcase(to_string(level))}S:")
      
      level_errors
      |> Enum.each(fn {_level, _type, path, message} ->
        file_name = Path.basename(path)
        Mix.shell().info("  #{file_name}: #{message}")
      end)
    end)
  end

  defp fix_errors(errors) do
    Mix.shell().info("\n🔧 Attempting to fix errors automatically...")
    
    fixed_count = 
      errors
      |> Enum.map(&attempt_fix/1)
      |> Enum.count(&(&1 == :fixed))
    
    Mix.shell().info("✨ Fixed #{fixed_count} issues automatically")
    
    if fixed_count > 0 do
      Mix.shell().info("Re-run linting to verify fixes")
    end
  end

  defp attempt_fix({:warning, :missing_metadata, _path, _message}) do
    # Could attempt to add missing front-matter
    :not_fixed
  end

  defp attempt_fix({:warning, :incomplete_tasks, _path, _message}) do
    # Could move tasks to backlog
    :not_fixed  
  end

  defp attempt_fix(_error) do
    :not_fixed
  end
end
