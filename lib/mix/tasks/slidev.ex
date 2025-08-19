defmodule Mix.Tasks.Slidev.Dev do
  @moduledoc """
  Runs the Slidev development server for presentations.

  ## Usage

      mix slidev.dev

  This command starts the Slidev hot-reload development server.
  """
  use Mix.Task

  @shortdoc "Run Slidev development server"

  def run(_args) do
    JidoWorkspace.ensure_workspace_env()

    path = "presentations"

    unless File.dir?(path) do
      Mix.shell().error("Presentations directory not found: #{path}")
      exit(1)
    end

    Mix.shell().info("Starting Slidev development server...")
    System.cmd("bun", ["run", "dev"], cd: path, into: IO.stream(:stdio, :line))
  end
end

defmodule Mix.Tasks.Slidev.Build do
  @moduledoc """
  Builds static presentation files.

  ## Usage

      mix slidev.build

  This command builds the presentations to static files.
  """
  use Mix.Task

  @shortdoc "Build presentations to static files"

  def run(_args) do
    JidoWorkspace.ensure_workspace_env()

    path = "presentations"

    unless File.dir?(path) do
      Mix.shell().error("Presentations directory not found: #{path}")
      exit(1)
    end

    Mix.shell().info("Building presentations...")

    case System.cmd("bun", ["run", "build"], cd: path) do
      {output, 0} ->
        Mix.shell().info("Build completed successfully")
        Mix.shell().info(output)

      {output, _} ->
        Mix.shell().error("Build failed:")
        Mix.shell().error(output)
        exit(1)
    end
  end
end

defmodule Mix.Tasks.Slidev.Install do
  @moduledoc """
  Installs dependencies for presentations.

  ## Usage

      mix slidev.install

  This command runs bun install in the presentations directory.
  """
  use Mix.Task

  @shortdoc "Install presentation dependencies"

  def run(_args) do
    JidoWorkspace.ensure_workspace_env()

    path = "presentations"

    unless File.dir?(path) do
      Mix.shell().error("Presentations directory not found: #{path}")
      exit(1)
    end

    Mix.shell().info("Installing presentation dependencies...")

    case System.cmd("bun", ["install"], cd: path) do
      {output, 0} ->
        Mix.shell().info("Dependencies installed successfully")
        Mix.shell().info(output)

      {output, _} ->
        Mix.shell().error("Installation failed:")
        Mix.shell().error(output)
        exit(1)
    end
  end
end

defmodule Mix.Tasks.Slidev.New do
  @moduledoc """
  Creates a new Slidev presentation.

  ## Usage

      mix slidev.new presentation-name

  This command creates a new presentation directory and sets up the basic structure.
  """
  use Mix.Task

  @shortdoc "Create a new Slidev presentation"

  def run(args) do
    JidoWorkspace.ensure_workspace_env()

    path = "presentations"

    case args do
      [name] ->
        unless File.dir?(path) do
          Mix.shell().error("Presentations directory not found: #{path}")
          exit(1)
        end

        Mix.shell().info("Creating new presentation: #{name}")

        case System.cmd("bun", ["run", "new", name], cd: path) do
          {output, 0} ->
            Mix.shell().info("Presentation '#{name}' created successfully")
            Mix.shell().info(output)

          {output, _} ->
            Mix.shell().error("Failed to create presentation:")
            Mix.shell().error(output)
            exit(1)
        end

      _ ->
        Mix.shell().error("Usage: mix slidev.new <presentation-name>")
        exit(1)
    end
  end
end
