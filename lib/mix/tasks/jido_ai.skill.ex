defmodule Mix.Tasks.JidoAi.Skill do
  @shortdoc "Manage and inspect Jido AI skills"

  @moduledoc """
  Manage and inspect skills from the command line.

  ## Commands

      # List all skills in a directory
      mix jido_ai.skill list priv/skills

      # Show details of a specific skill
      mix jido_ai.skill show priv/skills/code-review/SKILL.md

      # Validate a skill file
      mix jido_ai.skill validate priv/skills/code-review/SKILL.md

      # Validate all skills in a directory
      mix jido_ai.skill validate priv/skills

  ## Examples

      # List skills with their descriptions
      mix jido_ai.skill list priv/skills

      # Show full skill details including body
      mix jido_ai.skill show priv/skills/code-review/SKILL.md --body

      # Validate skills before deployment
      mix jido_ai.skill validate priv/skills --strict

  ## Options

      --body           Show full skill body (for show command)
      --json           Output as JSON
      --strict         Fail on warnings (for validate command)
  """

  use Mix.Task

  alias Jido.AI.Skill.{Loader, Spec}

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:yaml_elixir)

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [body: :boolean, json: :boolean, strict: :boolean],
        aliases: [b: :body, j: :json, s: :strict]
      )

    case args do
      ["list" | paths] -> list_skills(paths, opts)
      ["show", path] -> show_skill(path, opts)
      ["validate" | paths] -> validate_skills(paths, opts)
      [] -> Mix.shell().info(@moduledoc)
      _ -> Mix.shell().error("Unknown command. Run `mix jido_ai.skill` for help.")
    end
  end

  defp list_skills([], _opts) do
    Mix.shell().error("Usage: mix jido_ai.skill list <path> [<path>...]")
  end

  defp list_skills(paths, opts) do
    skills = paths |> Enum.flat_map(&find_skill_files/1) |> Enum.map(&load_skill/1)

    valid_skills = Enum.filter(skills, &match?({:ok, _}, &1))
    errors = Enum.filter(skills, &match?({:error, _}, &1))

    if opts[:json] do
      data =
        Enum.map(valid_skills, fn {:ok, spec} ->
          %{
            name: spec.name,
            description: spec.description,
            license: spec.license,
            allowed_tools: spec.allowed_tools
          }
        end)

      Mix.shell().info(Jason.encode!(data, pretty: true))
    else
      Mix.shell().info("\n#{IO.ANSI.bright()}Skills found: #{length(valid_skills)}#{IO.ANSI.reset()}\n")

      Enum.each(valid_skills, fn {:ok, spec} ->
        tools =
          case spec.allowed_tools do
            [] -> ""
            tools -> " [#{Enum.join(tools, ", ")}]"
          end

        Mix.shell().info("  #{IO.ANSI.cyan()}#{spec.name}#{IO.ANSI.reset()}#{tools}")
        Mix.shell().info("    #{spec.description}\n")
      end)

      if errors != [] do
        Mix.shell().info("#{IO.ANSI.red()}Errors: #{length(errors)}#{IO.ANSI.reset()}")

        Enum.each(errors, fn {:error, {path, reason}} ->
          Mix.shell().error("  #{path}: #{format_error(reason)}")
        end)
      end
    end
  end

  defp show_skill(path, opts) do
    case Loader.load(path) do
      {:ok, spec} ->
        if opts[:json] do
          data = %{
            name: spec.name,
            description: spec.description,
            license: spec.license,
            compatibility: spec.compatibility,
            metadata: spec.metadata,
            allowed_tools: spec.allowed_tools,
            vsn: spec.vsn,
            tags: spec.tags,
            body: if(opts[:body], do: get_body(spec))
          }

          Mix.shell().info(Jason.encode!(data, pretty: true))
        else
          Mix.shell().info("")
          Mix.shell().info("#{IO.ANSI.bright()}#{spec.name}#{IO.ANSI.reset()}")
          Mix.shell().info("#{IO.ANSI.faint()}#{String.duplicate("─", String.length(spec.name))}#{IO.ANSI.reset()}")
          Mix.shell().info("")
          Mix.shell().info("#{IO.ANSI.cyan()}Description:#{IO.ANSI.reset()} #{spec.description}")

          if spec.license, do: Mix.shell().info("#{IO.ANSI.cyan()}License:#{IO.ANSI.reset()} #{spec.license}")

          if spec.compatibility,
            do: Mix.shell().info("#{IO.ANSI.cyan()}Compatibility:#{IO.ANSI.reset()} #{spec.compatibility}")

          if spec.vsn, do: Mix.shell().info("#{IO.ANSI.cyan()}Version:#{IO.ANSI.reset()} #{spec.vsn}")

          if spec.tags != [],
            do: Mix.shell().info("#{IO.ANSI.cyan()}Tags:#{IO.ANSI.reset()} #{Enum.join(spec.tags, ", ")}")

          if spec.allowed_tools != [] do
            Mix.shell().info("#{IO.ANSI.cyan()}Allowed Tools:#{IO.ANSI.reset()} #{Enum.join(spec.allowed_tools, ", ")}")
          end

          if spec.metadata && map_size(spec.metadata) > 0 do
            Mix.shell().info("#{IO.ANSI.cyan()}Metadata:#{IO.ANSI.reset()}")

            Enum.each(spec.metadata, fn {k, v} ->
              Mix.shell().info("  #{k}: #{inspect(v)}")
            end)
          end

          if opts[:body] do
            Mix.shell().info("")
            Mix.shell().info("#{IO.ANSI.cyan()}Body:#{IO.ANSI.reset()}")
            Mix.shell().info("#{IO.ANSI.faint()}#{String.duplicate("─", 40)}#{IO.ANSI.reset()}")
            Mix.shell().info(get_body(spec))
          end

          Mix.shell().info("")
        end

      {:error, reason} ->
        Mix.shell().error("Failed to load skill: #{format_error(reason)}")
    end
  end

  defp validate_skills([], _opts) do
    Mix.shell().error("Usage: mix jido_ai.skill validate <path> [<path>...]")
  end

  defp validate_skills(paths, opts) do
    files = Enum.flat_map(paths, &find_skill_files/1)
    results = Enum.map(files, fn path -> {path, Loader.load(path)} end)

    valid = Enum.filter(results, fn {_, result} -> match?({:ok, _}, result) end)
    errors = Enum.filter(results, fn {_, result} -> match?({:error, _}, result) end)

    if opts[:json] do
      data = %{
        valid: length(valid),
        errors: length(errors),
        results:
          Enum.map(results, fn
            {path, {:ok, spec}} -> %{path: path, valid: true, name: spec.name}
            {path, {:error, reason}} -> %{path: path, valid: false, error: format_error(reason)}
          end)
      }

      Mix.shell().info(Jason.encode!(data, pretty: true))
    else
      Mix.shell().info("")
      Mix.shell().info("#{IO.ANSI.bright()}Validation Results#{IO.ANSI.reset()}")
      Mix.shell().info("#{IO.ANSI.faint()}#{String.duplicate("─", 18)}#{IO.ANSI.reset()}")
      Mix.shell().info("")

      Enum.each(results, fn
        {path, {:ok, spec}} ->
          Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} #{path} (#{spec.name})")

        {path, {:error, reason}} ->
          Mix.shell().info("  #{IO.ANSI.red()}✗#{IO.ANSI.reset()} #{path}")
          Mix.shell().info("    #{IO.ANSI.red()}#{format_error(reason)}#{IO.ANSI.reset()}")
      end)

      Mix.shell().info("")

      Mix.shell().info(
        "#{IO.ANSI.green()}Valid: #{length(valid)}#{IO.ANSI.reset()}, #{IO.ANSI.red()}Errors: #{length(errors)}#{IO.ANSI.reset()}"
      )

      Mix.shell().info("")
    end

    if opts[:strict] && errors != [] do
      Mix.raise("Validation failed with #{length(errors)} error(s)")
    end
  end

  defp find_skill_files(path) do
    cond do
      File.regular?(path) && String.ends_with?(path, "SKILL.md") -> [path]
      File.dir?(path) -> Path.wildcard(Path.join([path, "**", "SKILL.md"]))
      true -> []
    end
  end

  defp load_skill(path) do
    case Loader.load(path) do
      {:ok, spec} -> {:ok, spec}
      {:error, reason} -> {:error, {path, reason}}
    end
  end

  defp get_body(%Spec{body_ref: {:inline, content}}), do: content

  defp format_error(%{__struct__: struct} = error) do
    case struct do
      Jido.AI.Skill.Error.Parse.NoFrontmatter -> "No YAML frontmatter found"
      Jido.AI.Skill.Error.Parse.InvalidYaml -> "Invalid YAML: #{inspect(error.reason)}"
      Jido.AI.Skill.Error.Validation.InvalidName -> "Invalid name '#{error.name}'"
      Jido.AI.Skill.Error.Validation.MissingField -> "Missing required field: #{error.field}"
      _ -> inspect(error)
    end
  end

  defp format_error(error), do: inspect(error)
end
