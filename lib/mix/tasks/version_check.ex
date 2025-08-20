defmodule Mix.Tasks.Version.Check do
  use Mix.Task

  @shortdoc "Checks version consistency across Jido packages"

  @moduledoc """
  Checks version consistency across all Hex packages as specified in workspace configuration.
  
  Reads @version from each package's mix.exs and displays them in a formatted table.

  ## Examples

      mix version.check
  """

  def run(_args) do
    Application.ensure_all_started(:jido_workspace)

    hex_packages = Application.get_env(:jido_workspace, :hex_packages, [])

    if Enum.empty?(hex_packages) do
      Mix.shell().error("No hex packages configured in workspace")
    else
      versions = 
        for package <- hex_packages do
          mix_file = Path.join(package.path, "mix.exs")
          
          if File.exists?(mix_file) do
            content = File.read!(mix_file)
            
            case Regex.run(~r/@version\s+"([^"]+)"/, content) do
              [_, version] -> {package.name, version}
              nil -> {package.name, "NOT_FOUND"}
            end
          else
            {package.name, "MISSING_FILE"}
          end
        end

      Mix.shell().info("Package versions:")
      
      for {name, version} <- versions do
        status_icon = case version do
          "NOT_FOUND" -> "✗"
          "MISSING_FILE" -> "✗"
          _ -> "✓"
        end
        
        Mix.shell().info("  #{status_icon} #{String.pad_trailing(name, 20)} #{version}")
      end

      # Check for consistency
      actual_versions = 
        versions
        |> Enum.filter(fn {_name, version} -> version not in ["NOT_FOUND", "MISSING_FILE"] end)
        |> Enum.map(fn {_name, version} -> version end)
        |> Enum.uniq()

      case actual_versions do
        [] -> Mix.shell().error("\nNo valid versions found!")
        [single_version] -> Mix.shell().info("\n✓ All packages have consistent version: #{single_version}")
        multiple_versions -> 
          Mix.shell().error("\n✗ Version inconsistency detected!")
          Mix.shell().error("Found versions: #{Enum.join(multiple_versions, ", ")}")
      end
    end
  end
end
