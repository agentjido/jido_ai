defmodule Jido.AI.Skill.Discovery do
  @moduledoc """
  Discovers skills from project-level and user-level skill directories.

  Implements the agentskills.io discovery spec:
  - Project-level: `.agents/skills/` directory
  - User-level: `~/.agents/skills/` directory

  ## Precedence Rules

  Project-level skills override user-level skills when both have the same name.
  This follows deterministic precedence: **project > user**

  ## Metadata Tracking

  Each discovered skill includes:
  - `name` - Skill identifier
  - `description` - Brief description from SKILL.md frontmatter
  - `skill_md_path` - Absolute path to the SKILL.md file
  - `root_dir` - Skill root directory (parent of SKILL.md location)
  - `scope` - `:project` or `:user` indicating source
  - `source_metadata` - Additional discovery metadata

  ## Usage

      # Discover all skills
      {:ok, skills} = Jido.AI.Skill.Discovery.discover()

      # Discover from specific paths only
      {:ok, skills} = Jido.AI.Skill.Discovery.discover_from([".agents/skills/"])

      # Get a single skill by name
      {:ok, spec} = Jido.AI.Skill.Discovery.find("code-review")
  """

  alias Jido.AI.Skill.{Spec, Loader}

  @project_path ".agents/skills"

  @type scope :: :project | :user | :custom
  @type discovery_metadata :: %{
          name: String.t(),
          description: String.t() | nil,
          skill_md_path: String.t(),
          root_dir: String.t(),
          scope: scope(),
          source_metadata: map()
        }

  @doc """
  Discovers skills from both project and user directories.

  Returns skills with project-level taking precedence over user-level
  when names collide.

  ## Returns

  - `{:ok, [discovery_metadata]}` - List of discovered skill metadata
  - `{:error, reason}` - Discovery failed

  ## Examples

      {:ok, skills} = Jido.AI.Skill.Discovery.discover()
      # skills will have project-level skills overriding user-level
  """
  @spec discover() :: {:ok, [discovery_metadata()]} | {:error, term()}
  def discover do
    with {:ok, project_skills} <- discover_from_project(),
         {:ok, user_skills} <- discover_from_user() do
      # Merge with precedence: project > user
      merged =
        (project_skills ++ user_skills)
        |> Enum.group_by(& &1.name)
        |> Enum.map(fn {_name, [first | _]} -> first end)

      {:ok, merged}
    end
  end

  @doc """
  Discovers skills from a list of specific paths.

  Useful for scanning custom directories or testing.

  ## Options

  - `:scope` - Assign scope metadata (`:project` or `:user`), defaults to `:custom`

  ## Examples

      {:ok, skills} = Jido.AI.Skill.Discovery.discover_from(["priv/skills/"])
      {:ok, skills} = Jido.AI.Skill.Discovery.discover_from(["priv/skills/"], scope: :project)
  """
  @spec discover_from([String.t()], keyword()) :: {:ok, [discovery_metadata()]} | {:error, term()}
  def discover_from(paths, opts \\ []) do
    scope = Keyword.get(opts, :scope, :custom)

    skills =
      paths
      |> Enum.flat_map(&scan_directory/1)
      |> Enum.map(&build_metadata(&1, scope))
      |> Enum.reject(&is_nil/1)

    {:ok, skills}
  end

  @doc """
  Discovers skills from the project-level `.agents/skills/` directory.

  ## Returns

  - `{:ok, [discovery_metadata]}` - List of project-level skills
  - `{:ok, []}` - Directory doesn't exist or is empty
  - `{:error, reason}` - Discovery failed
  """
  @spec discover_from_project(String.t()) :: {:ok, [discovery_metadata()]} | {:error, term()}
  def discover_from_project(base_path \\ @project_path) do
    if File.dir?(base_path) do
      discover_from([base_path], scope: :project)
    else
      {:ok, []}
    end
  end

  @doc """
  Discovers skills from the user-level `~/.agents/skills/` directory.

  ## Returns

  - `{:ok, [discovery_metadata]}` - List of user-level skills
  - `{:ok, []}` - Directory doesn't exist or is empty
  - `{:error, reason}` - Discovery failed
  """
  @spec discover_from_user(String.t()) :: {:ok, [discovery_metadata()]} | {:error, term()}
  def discover_from_user(base_path \\ default_user_path()) do
    if File.dir?(base_path) do
      discover_from([base_path], scope: :user)
    else
      {:ok, []}
    end
  end

  @doc """
  Finds a specific skill by name across all discovery sources.

  Returns the first matching skill with project-level taking precedence.

  When `paths` is given, searches those directories instead of the default
  project/user discovery sources — useful for scoped lookups and testing.

  ## Examples

      {:ok, metadata} = Jido.AI.Skill.Discovery.find("code-review")
      {:error, :not_found} = Jido.AI.Skill.Discovery.find("unknown-skill")
      {:ok, metadata} = Jido.AI.Skill.Discovery.find("local-skill", ["priv/skills/"])
  """
  @spec find(String.t(), [String.t()] | nil) :: {:ok, discovery_metadata()} | {:error, :not_found}
  def find(name, paths \\ nil) when is_binary(name) do
    discovery = if is_list(paths), do: discover_from(paths), else: discover()

    case discovery do
      {:ok, skills} ->
        case Enum.find(skills, &(&1.name == name)) do
          nil -> {:error, :not_found}
          skill -> {:ok, skill}
        end
    end
  end

  @doc """
  Converts discovery metadata into a full Spec by loading the SKILL.md.

  ## Examples

      {:ok, metadata} = Jido.AI.Skill.Discovery.find("code-review")
      {:ok, spec} = Jido.AI.Skill.Discovery.to_spec(metadata)
  """
  @spec to_spec(discovery_metadata() | map()) :: {:ok, Spec.t()} | {:error, term()}
  def to_spec(%{skill_md_path: path, scope: scope, root_dir: _root_dir}) do
    case Loader.load(path, lenient: true) do
      {:ok, spec} ->
        # Enhance spec with discovery metadata
        enhanced = %{spec | source: {:file, path}, metadata: Map.put(spec.metadata || %{}, :discovery_scope, scope)}
        {:ok, enhanced}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def to_spec(_invalid_metadata), do: {:error, :invalid_metadata}

  # Private functions

  defp scan_directory(path) do
    skill_pattern = Path.join([path, "**", "SKILL.md"])
    Path.wildcard(skill_pattern)
  end

  defp default_user_path do
    Path.join([System.user_home!(), ".agents", "skills"])
  end

  defp build_metadata(skill_md_path, scope) do
    # Extract skill directory name (parent of SKILL.md)
    root_dir = Path.dirname(skill_md_path)
    dir_name = Path.basename(root_dir)

    # Quick peek at frontmatter to get name/description without full parse
    case peek_frontmatter(skill_md_path) do
      {:ok, %{"name" => name} = frontmatter} ->
        %{
          name: name,
          description: frontmatter["description"],
          skill_md_path: skill_md_path,
          root_dir: root_dir,
          scope: scope,
          source_metadata: %{
            directory_name: dir_name,
            discovered_at: DateTime.utc_now()
          }
        }

      _ ->
        # Invalid or missing frontmatter - still return metadata but mark as invalid
        nil
    end
  end

  defp peek_frontmatter(path) do
    case File.read(path) do
      {:ok, content} ->
        case Regex.run(~r/\A---\r?\n(.*?)\r?\n---\r?\n/s, content) do
          [_, yaml] -> YamlElixir.read_from_string(yaml)
          _ -> {:error, :no_frontmatter}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
