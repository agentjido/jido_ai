defmodule Mix.Tasks.Workspace.Add do
  use Mix.Task

  @shortdoc "Add a project to the workspace"

  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
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

        Application.ensure_all_started(:jido_workspace)
        JidoWorkspace.ensure_workspace_env()
        add_project_to_config(project)
        JidoWorkspace.pull_project(name)

      _ ->
        Mix.shell().error(
          "Usage: mix workspace.add <name> <url> [--branch <branch>] [--type <type>]"
        )
    end
  end

  defp add_project_to_config(project) do
    config_path = "config/workspace.exs"
    current_config = File.read!(config_path)

    new_project =
      "    %{\n      name: \"#{project.name}\",\n      upstream_url: \"#{project.upstream_url}\",\n      branch: \"#{project.branch}\",\n      type: :#{project.type},\n      path: \"#{project.path}\"\n    }"

    updated_config =
      String.replace(current_config, ~r/(\s+)(\]\s*$)/m, ",\n#{new_project}\n\\1\\2")

    File.write!(config_path, updated_config)

    Mix.shell().info("Added #{project.name} to workspace config")
  end
end
