defmodule Jido.AI.Skill.Resources do
  @moduledoc """
  Progressive disclosure of skill resources without eager loading.

  Provides APIs to enumerate and lazily load resources bundled with skills:
  - `scripts/` - Executable scripts and automation
  - `references/` - Documentation and reference materials
  - `assets/` - Binary assets (images, binaries, etc.)

  All paths are resolved relative to the skill root directory,
  preventing path traversal attacks.

  ## Usage

      # List all resources in a skill
      resources = Jido.AI.Skill.Resources.list_resources(skill_root)
      # => %{scripts: [...], references: [...], assets: [...]}

      # Load a specific resource
      {:ok, content} = Jido.AI.Skill.Resources.load_resource(skill_root, "references/guide.md")

      # Check resource exists without loading
      true = Jido.AI.Skill.Resources.exists?(skill_root, "scripts/setup.sh")
  """

  @type resource_listing :: %{
          scripts: [resource_info()],
          references: [resource_info()],
          assets: [resource_info()]
        }

  @type resource_info :: %{
          name: String.t(),
          relative_path: String.t(),
          absolute_path: String.t(),
          size: non_neg_integer() | nil,
          modified: DateTime.t() | nil
        }

  @type resource_type :: :scripts | :references | :assets

  @doc """
  Lists all resources in a skill directory.

  Returns a map with resources grouped by type, without loading content.

  ## Examples

      resources = Jido.AI.Skill.Resources.list_resources("/path/to/skill")
      IO.inspect(resources.scripts)     # [%{name: "deploy.sh", ...}]
      IO.inspect(resources.references)    # [%{name: "api.md", ...}]
      IO.inspect(resources.assets)        # [%{name: "logo.png", ...}]
  """
  @spec list_resources(String.t()) :: resource_listing()
  def list_resources(skill_root) when is_binary(skill_root) do
    if File.dir?(skill_root) do
      %{
        scripts: list_resource_type(skill_root, :scripts),
        references: list_resource_type(skill_root, :references),
        assets: list_resource_type(skill_root, :assets)
      }
    else
      %{scripts: [], references: [], assets: []}
    end
  end

  @doc """
  Lists resources of a specific type.

  ## Examples

      scripts = Jido.AI.Skill.Resources.list_by_type(skill_root, :scripts)
  """
  @spec list_by_type(String.t(), resource_type()) :: [resource_info()]
  def list_by_type(skill_root, type) when type in [:scripts, :references, :assets] do
    list_resource_type(skill_root, type)
  end

  @doc """
  Loads a resource file lazily.

  Returns the file content only when requested. Validates the path
  is within the skill root to prevent directory traversal.

  ## Returns

  - `{:ok, binary}` - Resource loaded successfully
  - `{:error, :not_found}` - Resource doesn't exist
  - `{:error, :path_traversal}` - Attempted path traversal attack

  ## Examples

      {:ok, content} = Jido.AI.Skill.Resources.load_resource(skill_root, "references/api.md")
      {:error, :not_found} = Jido.AI.Skill.Resources.load_resource(skill_root, "missing.txt")

      # Path traversal is blocked:
      {:error, :path_traversal} = Jido.AI.Skill.Resources.load_resource(skill_root, "../../../etc/passwd")
  """
  @spec load_resource(String.t(), String.t()) :: {:ok, binary()} | {:error, atom()}
  def load_resource(skill_root, relative_path) when is_binary(skill_root) and is_binary(relative_path) do
    case resolve_path(skill_root, relative_path) do
      {:ok, absolute_path} ->
        if File.regular?(absolute_path) do
          File.read(absolute_path)
        else
          {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Loads a resource as UTF-8 text.

  Same as `load_resource/2` but validates the content is valid UTF-8.

  ## Returns

  - `{:ok, String.t()}` - Resource loaded and valid UTF-8
  - `{:error, :invalid_utf8}` - Content is not valid UTF-8
  - `{:error, reason}` - Other errors from `load_resource/2`
  """
  @spec load_resource_text(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def load_resource_text(skill_root, relative_path) when is_binary(skill_root) and is_binary(relative_path) do
    case load_resource(skill_root, relative_path) do
      {:ok, binary} ->
        case String.valid?(binary) do
          true -> {:ok, binary}
          false -> {:error, :invalid_utf8}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resolves a relative path to an absolute path within the skill root.

  Validates the resolved path is within the skill root directory
  to prevent path traversal attacks.

  ## Returns

  - `{:ok, absolute_path}` - Path resolved successfully
  - `{:error, :path_traversal}` - Path escapes skill root

  ## Examples

      {:ok, "/skill/references/guide.md"} = Jido.AI.Skill.Resources.resolve_path("/skill", "references/guide.md")
      {:error, :path_traversal} = Jido.AI.Skill.Resources.resolve_path("/skill", "../../../etc/passwd")
  """
  @spec resolve_path(String.t(), String.t()) :: {:ok, String.t()} | {:error, :path_traversal}
  def resolve_path(skill_root, relative_path) when is_binary(skill_root) and is_binary(relative_path) do
    # Reject absolute inputs outright — `Path.join/2` would silently re-root
    # them under the skill root, masking an attempted absolute-path injection.
    if Path.type(relative_path) == :absolute do
      {:error, :path_traversal}
    else
      do_resolve_path(skill_root, relative_path)
    end
  end

  defp do_resolve_path(skill_root, relative_path) do
    expanded_root = Path.expand(skill_root)
    absolute_path = Path.join(expanded_root, relative_path) |> Path.expand()

    if within_path?(absolute_path, expanded_root) and resolved_within_root?(absolute_path, expanded_root) do
      {:ok, absolute_path}
    else
      {:error, :path_traversal}
    end
  end

  @doc """
  Checks if a resource exists without loading it.

  ## Examples

      true = Jido.AI.Skill.Resources.exists?(skill_root, "scripts/setup.sh")
      false = Jido.AI.Skill.Resources.exists?(skill_root, "missing.txt")
  """
  @spec exists?(String.t(), String.t()) :: boolean()
  def exists?(skill_root, relative_path) when is_binary(skill_root) and is_binary(relative_path) do
    case resolve_path(skill_root, relative_path) do
      {:ok, absolute_path} -> File.regular?(absolute_path)
      {:error, _} -> false
    end
  end

  @doc """
  Gets information about a specific resource without loading it.

  ## Returns

  - `{:ok, resource_info}` - Resource exists, info returned
  - `{:error, :not_found}` - Resource doesn't exist

  ## Examples

      {:ok, info} = Jido.AI.Skill.Resources.resource_info(skill_root, "references/api.md")
      IO.puts("Size: \#{info.size}")
  """
  @spec resource_info(String.t(), String.t()) :: {:ok, resource_info()} | {:error, :not_found}
  def resource_info(skill_root, relative_path) when is_binary(skill_root) and is_binary(relative_path) do
    case resolve_path(skill_root, relative_path) do
      {:ok, absolute_path} ->
        if File.regular?(absolute_path) do
          {:ok, resource_info_for(absolute_path, relative_path)}
        else
          {:error, :not_found}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  @doc """
  Searches for resources matching a pattern.

  ## Examples

      # Find all markdown files in references
      matches = Jido.AI.Skill.Resources.search(skill_root, "references/**/*.md")
  """
  @spec search(String.t(), String.t()) :: [resource_info()]
  def search(skill_root, pattern) when is_binary(skill_root) and is_binary(pattern) do
    if File.dir?(skill_root) do
      expanded_root = Path.expand(skill_root)
      real_root = real_path(expanded_root)
      full_pattern = Path.join(expanded_root, pattern)

      full_pattern
      |> Path.wildcard()
      |> Enum.filter(&(File.regular?(&1) and within_root?(&1, expanded_root, real_root)))
      |> Enum.map(fn absolute_path ->
        relative_path = Path.relative_to(absolute_path, expanded_root)
        resource_info_for(absolute_path, relative_path)
      end)
      |> Enum.sort_by(& &1.relative_path)
    else
      []
    end
  end

  # Guards `search/2` results against patterns that traverse outside the
  # skill root (e.g. "../**/*.md"), matching the protection in `resolve_path/2`.
  defp within_root?(absolute_path, expanded_root, real_root) do
    expanded = Path.expand(absolute_path)
    within_path?(expanded, expanded_root) and resolved_within_root?(expanded, real_root)
  end

  # Private functions

  defp list_resource_type(skill_root, type) when type in [:scripts, :references, :assets] do
    expanded_root = Path.expand(skill_root)
    real_root = real_path(expanded_root)
    dir_path = Path.join(expanded_root, to_string(type))

    if File.dir?(dir_path) do
      dir_path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&(File.regular?(&1) and within_root?(&1, expanded_root, real_root)))
      |> Enum.map(fn absolute_path ->
        relative_path = Path.relative_to(absolute_path, expanded_root)
        resource_info_for(absolute_path, relative_path)
      end)
      |> Enum.sort_by(& &1.relative_path)
    else
      []
    end
  end

  defp within_path?(path, "/"), do: Path.type(path) == :absolute

  defp within_path?(path, root) do
    path == root or String.starts_with?(path, root <> "/")
  end

  defp resolved_within_root?(path, root) do
    real_root = real_path(root)

    case resolve_existing_path(path) do
      {:ok, real_path} -> within_path?(real_path, real_root)
      {:missing, resolved_path} -> within_path?(resolved_path, real_root)
      {:error, _reason} -> false
    end
  end

  defp real_path(path) do
    case resolve_existing_path(path) do
      {:ok, real_path} -> real_path
      {:missing, resolved_path} -> resolved_path
      {:error, _reason} -> Path.expand(path)
    end
  end

  defp resolve_existing_path(path) do
    path
    |> Path.expand()
    |> resolve_symlinks([])
  end

  defp resolve_symlinks(path, seen) do
    case Path.split(path) do
      ["/" | parts] -> do_resolve_symlinks("/", parts, seen)
      [first | parts] -> do_resolve_symlinks(first, parts, seen)
      [] -> {:ok, path}
    end
  end

  defp do_resolve_symlinks(current, [], _seen), do: {:ok, current}

  defp do_resolve_symlinks(current, [part | rest], seen) do
    candidate = Path.join(current, part)

    case File.lstat(candidate) do
      {:ok, %File.Stat{type: :symlink}} ->
        resolve_link(candidate, current, rest, seen)

      {:ok, _stat} ->
        do_resolve_symlinks(candidate, rest, seen)

      {:error, :enoent} ->
        {:missing, append_path(candidate, rest)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_link(candidate, current, rest, seen) do
    if candidate in seen do
      {:error, :symlink_loop}
    else
      with {:ok, target} <- File.read_link(candidate) do
        target_path =
          case Path.type(target) do
            :absolute -> Path.expand(target)
            _relative -> Path.expand(target, current)
          end

        target_path
        |> append_path(rest)
        |> resolve_symlinks([candidate | seen])
      end
    end
  end

  defp append_path(base, []), do: base
  defp append_path(base, parts), do: Path.join(base, Path.join(parts))

  defp resource_info_for(absolute_path, relative_path) do
    stat = File.stat!(absolute_path)

    %{
      name: Path.basename(relative_path),
      relative_path: relative_path,
      absolute_path: absolute_path,
      size: stat.size,
      modified: stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
    }
  end
end
