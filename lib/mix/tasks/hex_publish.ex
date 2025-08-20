defmodule Mix.Tasks.HexPublish do
  use Mix.Task

  @shortdoc "Publishes Jido packages to Hex in dependency order"

  @moduledoc """
  Publishes Jido ecosystem packages to Hex in dependency order.

  ## Examples

      mix hex_publish 1.3.0                  # Update and publish all packages
      mix hex_publish 1.3.0 --dry-run        # Preview changes without publishing
  """

  require Logger

  def run(args) do
    {opts, remaining_args} = parse_args(args)

    case remaining_args do
      [version] when is_binary(version) ->
        run_publish(version, opts)

      _ ->
        Mix.raise("Usage: mix hex_publish <version> [--dry-run]")
    end
  end

  defp parse_args(args) do
    {opts, remaining, _} = OptionParser.parse(args, switches: [dry_run: :boolean])
    {opts, remaining}
  end

  defp run_publish(version, opts) do
    Application.ensure_all_started(:jido_workspace)

    hex_packages = get_hex_packages()
    dry_run = Keyword.get(opts, :dry_run, false)

    if dry_run do
      Mix.shell().info("DRY RUN: Would update and publish packages with version #{version}")
    else
      Mix.shell().info("Publishing Jido packages with version #{version}")
    end

    # Update all packages first
    for package <- hex_packages do
      update_package_version(package, version, dry_run)
      unless dry_run, do: commit_package_changes(package, version)
    end

    # Then publish in dependency order
    sorted_packages = Enum.sort_by(hex_packages, & &1.publish_order)

    for package <- sorted_packages do
      publish_package(package, version, dry_run)
    end

    unless dry_run do
      Mix.shell().info("✓ All packages published successfully!")
      Mix.shell().info("Next steps:")
      Mix.shell().info("  1. Push subtree changes: mix ws.git.push")
      Mix.shell().info("  2. Create release tag: git tag v#{version} && git push --tags")
    end
  end

  defp get_hex_packages do
    # Read config using Config.Reader for proper evaluation
    config_path = Path.join(File.cwd!(), "config/workspace.exs")

    case Config.Reader.read!(config_path) do
      [{:jido_workspace, workspace_config}] ->
        Keyword.get(workspace_config, :hex_packages, [])

      _ ->
        Mix.raise("No hex_packages configuration found in config/workspace.exs")
    end
  end

  defp update_package_version(package, version, dry_run) do
    mix_file = Path.join(package.path, "mix.exs")

    unless File.exists?(mix_file) do
      Mix.raise("mix.exs not found at #{mix_file}")
    end

    content = File.read!(mix_file)

    # Update @version
    content = Regex.replace(~r/@version\s+"[^"]+"/, content, "@version \"#{version}\"")

    # Update ws_dep calls for Jido dependencies
    content =
      Enum.reduce(package.dependencies, content, fn dep_name, acc ->
        # Match ws_dep calls with the dependency name
        pattern = ~r/ws_dep\(:#{dep_name},\s+"[^"]+",\s+"[^"]+"/
        replacement = "ws_dep(:#{dep_name}, \"../#{dep_name}\", \"~> #{version}\""
        Regex.replace(pattern, acc, replacement)
      end)

    if dry_run do
      Mix.shell().info("DRY RUN: Would update #{package.name} at #{mix_file}")
      show_version_changes(package, version)
    else
      File.write!(mix_file, content)
      Mix.shell().info("✓ Updated #{package.name} to version #{version}")
    end
  end

  defp show_version_changes(package, version) do
    Mix.shell().info("  - @version \"#{version}\"")

    for dep <- package.dependencies do
      Mix.shell().info("  - #{dep} ~> #{version}")
    end
  end

  defp commit_package_changes(package, version) do
    case System.cmd("git", ["add", "mix.exs"], cd: package.path, stderr_to_stdout: true) do
      {_, 0} ->
        case System.cmd("git", ["commit", "-m", "Bump version to v#{version}"],
               cd: package.path,
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            Mix.shell().info("✓ Committed version changes for #{package.name}")

          {output, code} ->
            Logger.warning(
              "Failed to commit changes for #{package.name} (exit code: #{code}): #{output}"
            )
        end

      {output, code} ->
        Logger.error(
          "Failed to stage changes for #{package.name} (exit code: #{code}): #{output}"
        )
    end
  end

  defp publish_package(package, version, dry_run) do
    if dry_run do
      Mix.shell().info("DRY RUN: Would publish #{package.name} v#{version}")
    else
      Mix.shell().info("Publishing #{package.name} v#{version}...")

      # Use env -u to unset JIDO_WORKSPACE for hex publishing
      case System.cmd("env", ["-u", "JIDO_WORKSPACE", "mix", "hex.publish", "--yes"],
             cd: package.path,
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          Mix.shell().info("✓ #{package.name} published successfully")

        {error, code} ->
          Mix.shell().error("✗ Failed to publish #{package.name} (exit code: #{code}): #{error}")
          System.halt(1)
      end
    end
  end
end
