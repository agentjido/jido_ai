defmodule Jido.AI.Skill.Discovery do
  @moduledoc """
  Discovers skills from project-level and user-level skill directories.

  Implements the agentskills.io discovery spec:
  - Project-level: `.agents/skills/` directory
  - User-level: `~/.agents/skills/` directory

  ## Precedence Rules

  Project-level skills override user-level skills when both have the same name.
  For custom roots, an earlier root overrides a later root. Discovery records a
  warning with both locations when names collide.

  Discovery reads only bounded YAML frontmatter. It does not read skill bodies.
  Use `to_catalog_spec/1` for a metadata-only catalog and strict load at
  activation time. Use `to_spec/2` when a caller needs a complete spec now.

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

  alias Jido.AI.Skill.{Diagnostics, Error, Loader, Spec}

  @project_path ".agents/skills"
  @default_max_depth 6
  @default_max_directories 2_000
  @default_excluded_directories [".git", "node_modules"]
  @max_frontmatter_bytes 65_536
  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_name_length 64

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
    case discover_with_diagnostics(opts) do
      {:ok, skills, _diagnostics} -> {:ok, skills}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Discovers standard project and user skills and returns collision diagnostics.

  Project skills have precedence over user skills. A selected skill records its
  shadowed locations in `source_metadata.shadowed_locations`.
  """
  @spec discover_with_diagnostics(keyword()) ::
          {:ok, [discovery_metadata()], Diagnostics.t()} | {:error, term()}
  def discover_with_diagnostics(opts \\ []) do
    with {:ok, project_skills, project_diagnostics} <-
           discover_scope(@project_path, :project, opts),
         {:ok, user_skills, user_diagnostics} <-
           discover_scope(default_user_path(), :user, opts) do
      diagnostics = merge_diagnostics(project_diagnostics, user_diagnostics)
      {skills, diagnostics} = select_by_precedence(project_skills ++ user_skills, diagnostics)
      {:ok, skills, diagnostics}
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
    case discover_from_with_diagnostics(paths, opts) do
      {:ok, skills, _diagnostics} -> {:ok, skills}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Discovers skills from trusted roots and returns duplicate-name diagnostics.

  Earlier roots have precedence over later roots.
  """
  @spec discover_from_with_diagnostics([String.t()], keyword()) ::
          {:ok, [discovery_metadata()], Diagnostics.t()} | {:error, term()}
  def discover_from_with_diagnostics(paths, opts \\ []) do
    with {:ok, files} <- discover_files(paths, opts) do
      scope = Keyword.get(opts, :scope, :custom)

      skills =
        files
        |> Enum.map(&build_metadata(&1, scope))
        |> Enum.reject(&is_nil/1)

      {skills, diagnostics} = select_by_precedence(skills, Diagnostics.new())
      {:ok, skills, diagnostics}
    end
  end

  @doc """
  Returns bounded, symlink-safe `SKILL.md` paths without parsing them.

  This is the shared scanner used by discovery and registry loading. It accepts
  the same bounds, exclusions, and trust options as `discover_from/2`.
  """
  @spec discover_files([String.t()], keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def discover_files(paths, opts \\ []) do
    with :ok <- validate_arguments(paths, opts),
         :ok <- validate_options(opts),
         :ok <- validate_trusted_paths(paths, opts) do
      scan_paths(paths, opts)
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
    case discover_scope(base_path, :project, opts) do
      {:ok, skills, _diagnostics} -> {:ok, skills}
      {:error, reason} -> {:error, reason}
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
    case discover_scope(base_path, :user, opts) do
      {:ok, skills, _diagnostics} -> {:ok, skills}
      {:error, reason} -> {:error, reason}
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
  @spec to_spec(discovery_metadata() | map(), keyword()) :: {:ok, Spec.t()} | {:error, term()}
  def to_spec(metadata, opts \\ [])

  def to_spec(%{skill_md_path: path, scope: scope, root_dir: _root_dir}, opts)
      when scope in [:project, :user, :custom] and is_list(opts) do
    case Loader.load(path, Keyword.put_new(opts, :lenient, false)) do
      {:ok, spec} ->
        # Enhance spec with discovery metadata
        enhanced =
          %{
            spec
            | source: {:file, path},
              metadata: Map.put(spec.metadata, "jido_ai.discovery_scope", Atom.to_string(scope))
          }

        {:ok, enhanced}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def to_spec(_invalid_metadata, _opts), do: {:error, :invalid_metadata}

  @doc """
  Converts discovery metadata to a metadata-only catalog spec.

  This function does not read the skill body. The returned file body reference
  is resolved with strict loading during activation.
  """
  @spec to_catalog_spec(discovery_metadata() | map()) :: {:ok, Spec.t()} | {:error, term()}
  def to_catalog_spec(%{
        name: name,
        description: description,
        skill_md_path: path,
        root_dir: root_dir,
        scope: scope
      })
      when is_binary(name) and is_binary(description) and is_binary(path) and is_binary(root_dir) and
             scope in [:project, :user, :custom] do
    cond do
      String.length(name) > @max_name_length or not Regex.match?(@name_regex, name) ->
        {:error, %Error.Validation.InvalidName{name: name}}

      String.trim(description) == "" ->
        {:error, %Error.Validation.MissingField{field: :description}}

      Path.basename(root_dir) != name ->
        {:error,
         %Error.Validation.InvalidField{
           field: :name,
           reason: :directory_name_mismatch,
           value: name
         }}

      true ->
        {:ok,
         %Spec{
           name: name,
           description: description,
           source: {:file, path},
           body_ref: {:file, path},
           metadata: %{"jido_ai.discovery_scope" => Atom.to_string(scope)}
         }}
    end
  end

  def to_catalog_spec(%{description: nil}),
    do: {:error, %Error.Validation.MissingField{field: :description}}

  def to_catalog_spec(_invalid_metadata), do: {:error, :invalid_metadata}

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
    scope = Keyword.get(opts, :scope, :custom)

    cond do
      not (is_integer(max_depth) and max_depth >= 0) ->
        {:error, {:invalid_discovery_option, :max_depth}}

      not (is_integer(max_directories) and max_directories > 0) ->
        {:error, {:invalid_discovery_option, :max_directories}}

      not (is_list(excluded) and Enum.all?(excluded, &is_binary/1)) ->
        {:error, {:invalid_discovery_option, :exclude_directories}}

      trust not in [true, false] and not is_function(trust, 1) ->
        {:error, {:invalid_discovery_option, :trust}}

      scope not in [:project, :user, :custom] ->
        {:error, {:invalid_discovery_option, :scope}}

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
        regular_file?(expanded) and Path.basename(expanded) == "SKILL.md" ->
          {:cont, {:ok, files ++ [expanded], directory_count}}

        directory?(expanded) ->
          case walk_directories([{expanded, 0}], [], directory_count, opts) do
            {:ok, root_files, next_count} ->
              {:cont, {:ok, files ++ Enum.sort(root_files), next_count}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        true ->
          {:cont, {:ok, files, directory_count}}
      end
    end)
    |> case do
      {:ok, files, _directory_count} -> {:ok, Enum.uniq(files)}
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
    files = if regular_file?(skill_file), do: [skill_file | files], else: files
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
            |> Enum.filter(&directory?/1)
            |> Enum.map(&{&1, depth + 1})

          {:error, _reason} ->
            []
        end
      else
        []
      end

    {files, children}
  end

  defp regular_file?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> true
      _ -> false
    end
  end

  defp directory?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> true
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

    # Read only the frontmatter. The body is loaded during activation.
    case peek_frontmatter(skill_md_path) do
      {:ok, %{"name" => name} = frontmatter} when is_binary(name) ->
        %{
          name: name,
          description: binary_or_nil(frontmatter["description"]),
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
    with {:ok, io} <- File.open(path, [:read, :utf8]) do
      try do
        case IO.read(io, :line) do
          line when is_binary(line) ->
            if strip_bom(line) in ["---\n", "---\r\n"] do
              read_frontmatter(io, [], 0)
            else
              {:error, :no_frontmatter}
            end

          _ ->
            {:error, :no_frontmatter}
        end
      after
        File.close(io)
      end
    end
  end

  defp read_frontmatter(io, lines, byte_count) do
    case IO.read(io, :line) do
      line when line in ["---", "---\n", "---\r\n"] ->
        lines
        |> Enum.reverse()
        |> IO.iodata_to_binary()
        |> decode_frontmatter()
        |> require_mapping()

      line when is_binary(line) and byte_count + byte_size(line) <= @max_frontmatter_bytes ->
        read_frontmatter(io, [line | lines], byte_count + byte_size(line))

      line when is_binary(line) ->
        {:error, :frontmatter_too_large}

      :eof ->
        {:error, :unclosed_frontmatter}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_mapping({:ok, frontmatter}) when is_map(frontmatter), do: {:ok, frontmatter}
  defp require_mapping({:ok, _frontmatter}), do: {:error, :frontmatter_must_be_mapping}
  defp require_mapping({:error, reason}), do: {:error, reason}

  defp decode_frontmatter(yaml) do
    try do
      YamlElixir.read_from_string(yaml)
    rescue
      exception -> {:error, Exception.message(exception)}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(line), do: line

  defp discover_scope(base_path, scope, opts) do
    if File.dir?(base_path) do
      discover_from_with_diagnostics([base_path], Keyword.put(opts, :scope, scope))
    else
      {:ok, [], Diagnostics.new()}
    end
  end

  defp select_by_precedence(skills, diagnostics) do
    Enum.reduce(skills, {[], %{}, diagnostics}, fn skill, {selected, winners, diagnostics} ->
      case Map.fetch(winners, skill.name) do
        :error ->
          {selected ++ [skill], Map.put(winners, skill.name, skill), diagnostics}

        {:ok, winner} ->
          warning =
            Diagnostics.Warning.new(
              :shadowed_skill,
              "Skill '#{skill.name}' at '#{skill.skill_md_path}' is shadowed by '#{winner.skill_md_path}'",
              severity: :medium
            )

          selected = Enum.map(selected, &record_shadowed_location(&1, winner, skill.skill_md_path))
          {selected, winners, Diagnostics.add_warning(diagnostics, warning)}
      end
    end)
    |> then(fn {selected, _winners, diagnostics} -> {selected, diagnostics} end)
  end

  defp record_shadowed_location(skill, winner, shadowed_path) do
    if skill.skill_md_path == winner.skill_md_path do
      source_metadata =
        Map.update(skill.source_metadata, :shadowed_locations, [shadowed_path], &(&1 ++ [shadowed_path]))

      %{skill | source_metadata: source_metadata}
    else
      skill
    end
  end

  defp merge_diagnostics(%Diagnostics{} = left, %Diagnostics{} = right) do
    %Diagnostics{
      left
      | warnings: left.warnings ++ right.warnings,
        errors: left.errors ++ right.errors
    }
  end

  defp binary_or_nil(value) when is_binary(value), do: value
  defp binary_or_nil(_value), do: nil
end
