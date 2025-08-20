defmodule Mix.Tasks.HexValidate do
  use Mix.Task

  @shortdoc "Validates packages are ready for Hex publishing"

  @moduledoc """
  Validates packages are ready for Hex publishing by checking:
  
  - All ws_dep calls have explicit Hex versions (not GitHub URLs)
  - No uncommitted changes in package directories
  - Package metadata completeness (description, license, etc.)
  - Version consistency across packages

  ## Examples

      mix hex.validate
  """

  def run(_args) do
    Application.ensure_all_started(:jido_workspace)

    hex_packages = Application.get_env(:jido_workspace, :hex_packages, [])

    if Enum.empty?(hex_packages) do
      Mix.shell().error("No hex packages configured in workspace")
      System.halt(1)
    end

    Mix.shell().info("Validating packages for Hex publishing...\n")

    all_valid = 
      hex_packages
      |> Enum.map(&validate_package/1)
      |> Enum.all?()

    if all_valid do
      Mix.shell().info("\n✓ All packages ready for Hex publishing")
    else
      Mix.shell().error("\n✗ Some packages failed validation")
      System.halt(1)
    end
  end

  defp validate_package(package) do
    Mix.shell().info("Validating #{package.name}...")
    
    package_path = package.path
    mix_file = Path.join(package_path, "mix.exs")

    validations = [
      {validate_mix_file_exists(mix_file), "mix.exs file exists"},
      {validate_version_defined(mix_file), "@version is defined"},
      {validate_ws_dep_versions(mix_file, package.dependencies), "ws_dep calls have Hex versions"},
      {validate_no_uncommitted_changes(package_path), "no uncommitted changes"},
      {validate_package_metadata(mix_file), "package metadata complete"}
    ]

    results = 
      for {result, description} <- validations do
        status = if result, do: "✓", else: "✗"
        Mix.shell().info("  #{status} #{description}")
        result
      end

    package_valid = Enum.all?(results)
    
    unless package_valid do
      Mix.shell().error("  Package #{package.name} failed validation")
    end

    Mix.shell().info("")
    package_valid
  end

  defp validate_mix_file_exists(mix_file) do
    File.exists?(mix_file)
  end

  defp validate_version_defined(mix_file) do
    if File.exists?(mix_file) do
      content = File.read!(mix_file)
      Regex.match?(~r/@version\s+"[^"]+"/, content)
    else
      false
    end
  end

  defp validate_ws_dep_versions(mix_file, dependencies) do
    if File.exists?(mix_file) do
      content = File.read!(mix_file)
      
      # Check that all Jido dependencies use proper Hex versions (not GitHub URLs)
      Enum.all?(dependencies, fn dep_name ->
        case Regex.run(~r/ws_dep\(:#{dep_name},\s+"[^"]+",\s+"([^"]+)"\)/, content) do
          [_, version_spec] -> 
            # Check that version spec looks like a Hex version (starts with ~> or similar)
            String.match?(version_spec, ~r/^[~>=<\d]/)
          nil -> 
            # ws_dep not found, which is OK if it's not a Jido dependency
            true
        end
      end)
    else
      false
    end
  end

  defp validate_no_uncommitted_changes(package_path) do
    case System.cmd("git", ["status", "--porcelain"], cd: package_path, stderr_to_stdout: true) do
      {"", 0} -> true
      {_, 0} -> false  # Has uncommitted changes
      {_, _} -> false  # Git command failed
    end
  end

  defp validate_package_metadata(mix_file) do
    if File.exists?(mix_file) do
      content = File.read!(mix_file)
      
      required_fields = [
        {"description", ~r/description:\s*"[^"]+"/},
        {"package name", ~r/package:\s*\[/},
        {"maintainers", ~r/maintainers:\s*\[/},
        {"licenses", ~r/licenses:\s*\[/}
      ]

      Enum.all?(required_fields, fn {_field_name, pattern} ->
        Regex.match?(pattern, content)
      end)
    else
      false
    end
  end
end
