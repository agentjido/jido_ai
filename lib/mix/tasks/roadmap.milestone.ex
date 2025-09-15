defmodule Mix.Tasks.Roadmap.Milestone do
  @moduledoc """
  Manage roadmap milestones.

  ## Examples

      mix roadmap.milestone new
      mix roadmap.milestone new --project jido --edit
      mix roadmap.milestone close --milestone 2 --project jido

  """

  use Mix.Task

  alias JidoWorkspace.Roadmap.{Writer, Scanner}

  @shortdoc "Manage roadmap milestones"

  @switches [
    project: :string,
    milestone: :integer,
    from: :string,
    edit: :boolean
  ]

  def run(args) do
    {opts, args} = OptionParser.parse!(args, switches: @switches)

    case args do
      ["new"] ->
        create_milestone(opts)
      
      ["close"] ->
        close_milestone(opts)
      
      [] ->
        Mix.raise("Please specify an action: new or close")
      
      _ ->
        Mix.raise("Unknown milestone action. Use: new or close")
    end
  end

  defp create_milestone(opts) do
    project = opts[:project] || "workspace"
    milestone_num = Scanner.next_milestone_number(project)
    
    milestone_file = get_milestone_file(project, milestone_num)
    template_file = "roadmap/templates/PLAN_TEMPLATE.md"
    
    # Ensure project directory exists
    Path.dirname(milestone_file) |> File.mkdir_p!()
    
    # Prepare template replacements
    replacements = %{
      "project" => project,
      "milestone_number" => milestone_num,
      "owner" => get_git_author(),
      "review_date" => get_review_date(30),
      "target_date" => get_review_date(14),
      "phase_name" => "Phase Name"
    }
    
    case Writer.create_from_template(template_file, milestone_file, replacements) do
      :ok ->
        Mix.shell().info("📋 Created milestone #{milestone_num} for #{project}: #{milestone_file}")
        
        # Optionally import from backlog
        if opts[:from] == "backlog" do
          import_from_backlog(project, milestone_file)
        end
        
        # Open in editor if requested
        if opts[:edit] do
          open_file(milestone_file)
        else
          Mix.shell().info("Use --edit to open in editor, or edit manually: #{milestone_file}")
        end
      
      {:error, reason} ->
        Mix.raise("Failed to create milestone: #{reason}")
    end
  end

  defp close_milestone(opts) do
    project = opts[:project] || "workspace"
    milestone_num = opts[:milestone] || raise_missing_milestone()
    
    milestone_file = get_milestone_file(project, milestone_num)
    
    unless File.exists?(milestone_file) do
      Mix.raise("Milestone file not found: #{milestone_file}")
    end
    
    # Update status to done
    case Writer.update_frontmatter(milestone_file, %{"status" => "done"}) do
      :ok ->
        Mix.shell().info("✅ Closed milestone #{milestone_num} for #{project}")
        
        # Move remaining tasks to backlog
        move_remaining_tasks_to_backlog(milestone_file, project)
        
        # Commit the changes
        commit_milestone_close(milestone_num, project)
      
      {:error, reason} ->
        Mix.raise("Failed to close milestone: #{reason}")
    end
  end

  defp get_milestone_file("workspace", num) do
    "roadmap/workspace/milestone-#{num}.md"
  end

  defp get_milestone_file(project, num) do
    "roadmap/projects/#{project}/milestone-#{num}.md"
  end

  defp import_from_backlog(project, _milestone_file) do
    backlog_file = 
      case project do
        "workspace" -> "roadmap/workspace/backlog.md"
        _ -> "roadmap/projects/#{project}/backlog.md"
      end
    
    if File.exists?(backlog_file) do
      # This is a simplified implementation
      # In a full implementation, you'd parse the backlog tasks and add them to the milestone
      Mix.shell().info("📥 Consider importing tasks from #{backlog_file}")
    end
  end

  defp move_remaining_tasks_to_backlog(_milestone_file, _project) do
    # This is a simplified implementation
    # In a full implementation, you'd parse unchecked tasks and move them
    Mix.shell().info("📤 Any remaining tasks should be moved to backlog manually")
  end

  defp commit_milestone_close(milestone_num, project) do
    commit_msg = "roadmap:milestone-#{milestone_num} closed for #{project}"
    
    case System.cmd("git", ["add", "roadmap/"]) do
      {_, 0} ->
        case System.cmd("git", ["commit", "-m", commit_msg]) do
          {_, 0} -> Mix.shell().info("📝 Changes committed: #{commit_msg}")
          {_, _} -> Mix.shell().info("Note: Could not commit changes automatically")
        end
      {_, _} -> 
        Mix.shell().info("Note: Could not stage changes automatically")
    end
  end

  defp open_file(path) do
    editor = System.get_env("EDITOR") || "nano"
    
    case System.cmd(editor, [path], into: IO.stream(:stdio, :line)) do
      {_, 0} -> :ok
      {_, _} -> Mix.shell().info("Note: Could not open editor. File saved at #{path}")
    end
  end

  defp get_git_author do
    case System.cmd("git", ["config", "--get", "user.name"]) do
      {name, 0} -> "@#{String.trim(name)}"
      _ -> "@user"
    end
  end

  defp get_review_date(days_from_now) do
    Date.utc_today() 
    |> Date.add(days_from_now) 
    |> Date.to_string()
  end

  defp raise_missing_milestone do
    Mix.raise("Please specify milestone number: --milestone N")
  end
end
