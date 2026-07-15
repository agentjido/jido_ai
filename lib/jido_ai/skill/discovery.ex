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
  @default_max_depth 6
  @default_max_directories 2_000
  @default_excluded_directories [".git", "node_modules"]

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
  @spec discover(keyword()) :: {:ok, [discovery_metadata()]} | {:error, term()}
  def discover(opts \\ []) do
    with {:ok, project_skills} <- discover_from_project(@project_path, opts),
         {:ok, user_skills} <- discover_from_user(default_user_path(), opts) do
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
  - `:max_depth` - Maximum directory depth to scan (default: `6`)
  - `:max_directories` - Maximum directories visited across all paths (default: `2000`)
  - `:exclude_directories` - Directory basenames to skip (default: `.git` and `node_modules`)
  - `:trust` - `true`, `false`, or a one-argument function that approves each root path

  ## Examples

      {:ok, skills} = Jido.AI.Skill.Discovery.discover_from(["priv/skills/"])
      {:ok, skills} = Jido.AI.Skill.Discovery.discover_from(["priv/skills/"], scope: :project)
  """
  @spec discover_from([String.t()], keyword()) :: {:ok, [discovery_metadata()]} | {:error, term()}
  def discover_from(paths, opts \\ []) do
    with :ok <- validate_arguments(paths, opts),
         :ok <- validate_options(opts),
         :ok <- validate_trusted_paths(paths, opts),
         {:ok, files} <- scan_paths(paths, opts) do
      scope = Keyword.get(opts, :scope, :custom)

      skills =
        files
        |> Enum.map(&build_metadata(&1, scope))
        |> Enum.reject(&is_nil/1)

      {:ok, skills}
    end
  end

  @doc """
  Discovers skills from the project-level `.agents/skills/` directory.

  ## Returns

  - `{:ok, [discovery_metadata]}` - List of project-level skills
  - `{:ok, []}` - Directory doesn't exist or is empty
  - `{:error, reason}` - Discovery failed
  """
  @spec discover_from_project(String.t(), keyword()) ::
          {:ok, [discovery_metadata()]} | {:error, term()}
  def discover_from_project(base_path \\ @project_path, opts \\ []) do
    if File.dir?(base_path) do
      discover_from([base_path], Keyword.put(opts, :scope, :project))
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
  @spec discover_from_user(String.t(), keyword()) ::
          {:ok, [discovery_metadata()]} | {:error, term()}
  def discover_from_user(base_path \\ default_user_path(), opts \\ []) do
    if File.dir?(base_path) do
      discover_from([base_path], Keyword.put(opts, :scope, :user))
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
  @spec find(String.t(), [String.t()] | nil, keyword()) ::
          {:ok, discovery_metadata()} | {:error, term()}
  def find(name, paths \\ nil, opts \\ []) when is_binary(name) do
    discovery = if is_list(paths), do: discover_from(paths, opts), else: discover(opts)

    case discovery do
      {:ok, skills} ->
        case Enum.find(skills, &(&1.name == name)) do
          nil -> {:error, :not_found}
          skill -> {:ok, skill}
        end

      {:error, reason} ->
        {:error, reason}
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
        enhanced = %{spec | source: {:file, path}, metadata: Map.put(spec.metadata, :discovery_scope, scope)}
        {:ok, enhanced}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def to_spec(_invalid_metadata), do: {:error, :invalid_metadata}

  # Private functions

  defp validate_arguments(paths, opts) do
    cond do
      not (is_list(paths) and Enum.all?(paths, &is_binary/1)) ->
        {:error, {:invalid_discovery_option, :paths}}

      not (is_list(opts) and Keyword.keyword?(opts)) ->
        {:error, {:invalid_discovery_option, :options}}

      true ->
        :ok
    end
  end

  defp validate_options(opts) do
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    max_directories = Keyword.get(opts, :max_directories, @default_max_directories)
    excluded = Keyword.get(opts, :exclude_directories, @default_excluded_directories)
    trust = Keyword.get(opts, :trust, true)

    cond do
      not (is_integer(max_depth) and max_depth >= 0) ->
        {:error, {:invalid_discovery_option, :max_depth}}

      not (is_integer(max_directories) and max_directories > 0) ->
        {:error, {:invalid_discovery_option, :max_directories}}

      not (is_list(excluded) and Enum.all?(excluded, &is_binary/1)) ->
        {:error, {:invalid_discovery_option, :exclude_directories}}

      trust not in [true, false] and not is_function(trust, 1) ->
        {:error, {:invalid_discovery_option, :trust}}

      true ->
        :ok
    end
  end

  defp validate_trusted_paths(paths, opts) do
    trust = Keyword.get(opts, :trust, true)

    Enum.reduce_while(paths, :ok, fn path, :ok ->
      expanded = Path.expand(path)

      if trusted_path?(expanded, trust) do
        {:cont, :ok}
      else
        {:halt, {:error, {:untrusted_skill_path, expanded}}}
      end
    end)
  end

  defp trusted_path?(_path, true), do: true
  defp trusted_path?(_path, false), do: false
  defp trusted_path?(path, trust) when is_function(trust, 1), do: trust.(path) == true
  defp trusted_path?(_path, _trust), do: false

  defp scan_paths(paths, opts) do
    Enum.reduce_while(paths, {:ok, [], 0}, fn path, {:ok, files, directory_count} ->
      expanded = Path.expand(path)

      cond do
        File.regular?(expanded) and Path.basename(expanded) == "SKILL.md" ->
          {:cont, {:ok, [expanded | files], directory_count}}

        File.dir?(expanded) ->
          case walk_directories([{expanded, 0}], files, directory_count, opts) do
            {:ok, next_files, next_count} -> {:cont, {:ok, next_files, next_count}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        true ->
          {:cont, {:ok, files, directory_count}}
      end
    end)
    |> case do
      {:ok, files, _directory_count} -> {:ok, Enum.sort(files)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp walk_directories([], files, directory_count, _opts),
    do: {:ok, files, directory_count}

  defp walk_directories([{directory, depth} | rest], files, directory_count, opts) do
    max_directories = Keyword.get(opts, :max_directories, @default_max_directories)

    if directory_count >= max_directories do
      {:error, {:discovery_limit_exceeded, :max_directories, max_directories}}
    else
      {files, children} = scan_one_directory(directory, depth, files, opts)
      walk_directories(rest ++ children, files, directory_count + 1, opts)
    end
  end

  defp scan_one_directory(directory, depth, files, opts) do
    skill_file = Path.join(directory, "SKILL.md")
    files = if File.regular?(skill_file), do: [skill_file | files], else: files
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)

    children =
      if depth < max_depth do
        excluded = Keyword.get(opts, :exclude_directories, @default_excluded_directories)

        case File.ls(directory) do
          {:ok, entries} ->
            entries
            |> Enum.sort()
            |> Enum.reject(&(&1 in excluded))
            |> Enum.map(&Path.join(directory, &1))
            |> Enum.filter(&(File.dir?(&1) and not symlink?(&1)))
            |> Enum.map(&{&1, depth + 1})

          {:error, _reason} ->
            []
        end
      else
        []
      end

    {files, children}
  end

  defp symlink?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} -> true
      _ -> false
    end
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
      {:ok, %{"name" => name} = frontmatter} when is_binary(name) ->
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
