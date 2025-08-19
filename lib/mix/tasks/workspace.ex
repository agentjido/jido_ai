defmodule Mix.Tasks.Workspace.Add do
  @moduledoc """
  Add a new project to the workspace as a git subtree.
  
  ## Usage
  
      mix workspace.add <name> <url> [--branch <branch>] [--type <type>]
  
  ## Examples
  
      mix workspace.add jido https://github.com/agentjido/jido
      mix workspace.add myapp https://github.com/user/myapp --branch develop --type application
  """
  
  use Mix.Task
  
  @shortdoc "Add a project to the workspace"
  
  def run(args) do
    {opts, args, _} = OptionParser.parse(args, 
      switches: [branch: :string, type: :string],
      aliases: [b: :branch, t: :type]
    )
    
    case args do
      [name, url] ->
        branch = Keyword.get(opts, :branch, "main")
        type = Keyword.get(opts, :type, "library") |> String.to_atom()
        path = "projects/#{name}"
        
        project = %{
          name: name,
          upstream_url: url,
          branch: branch,
          type: type,
          path: path
        }
        
        add_project_to_config(project)
        JidoWorkspace.pull_project(name)
        
      _ ->
        Mix.shell().error("Usage: mix workspace.add <name> <url> [--branch <branch>] [--type <type>]")
    end
  end
  
  defp add_project_to_config(project) do
    config_path = "config/workspace.exs"
    current_config = File.read!(config_path)
    
    # Simple string replacement - in production you'd want proper AST manipulation
    new_project = """
        %{
          name: "#{project.name}",
          upstream_url: "#{project.upstream_url}",
          branch: "#{project.branch}",
          type: :#{project.type},
          path: "#{project.path}"
        }"""
    
    updated_config = String.replace(current_config, ~r/(\s+)(\]\s*$)/m, "\\1,\n    #{new_project}\n\\1\\2")
    File.write!(config_path, updated_config)
    
    Mix.shell().info("Added #{project.name} to workspace config")
  end
end

defmodule Mix.Tasks.Workspace.Pull do
  @moduledoc """
  Pull updates for a specific project or all projects.
  
  ## Usage
  
      mix workspace.pull [project_name]
  
  ## Examples
  
      mix workspace.pull          # Pull all projects
      mix workspace.pull jido     # Pull just the jido project
  """
  
  use Mix.Task
  
  @shortdoc "Pull project updates from upstream"
  
  def run([]) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.sync_all()
  end
  
  def run([project_name]) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.pull_project(project_name)
  end
  
  def run(_) do
    Mix.shell().error("Usage: mix workspace.pull [project_name]")
  end
end

defmodule Mix.Tasks.Workspace.Push do
  @moduledoc """
  Push changes for a specific project to upstream.
  
  ## Usage
  
      mix workspace.push <project_name>
  
  ## Examples
  
      mix workspace.push jido
  """
  
  use Mix.Task
  
  @shortdoc "Push project changes to upstream"
  
  def run([project_name]) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.push_project(project_name)
  end
  
  def run(_) do
    Mix.shell().error("Usage: mix workspace.push <project_name>")
  end
end

defmodule Mix.Tasks.Workspace.Status do
  @moduledoc """
  Show the status of the workspace and all projects.
  
  ## Usage
  
      mix workspace.status
  """
  
  use Mix.Task
  
  @shortdoc "Show workspace status"
  
  def run(_) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.status()
  end
end

defmodule Mix.Tasks.Workspace.Test.All do
  @moduledoc """
  Run tests for all projects in the workspace.
  
  ## Usage
  
      mix workspace.test.all
  """
  
  use Mix.Task
  
  @shortdoc "Run tests for all projects"
  
  def run(_) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.test_all()
  end
end
