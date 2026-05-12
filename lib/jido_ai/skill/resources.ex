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
    # Normalize and resolve the path
    expanded_root = Path.expand(skill_root)
    absolute_path = Path.join(expanded_root, relative_path) |> Path.expand()

    # Validate path is within skill root (prevent path traversal)
    if String.starts_with?(absolute_path, expanded_root <> "/") or
         absolute_path == expanded_root do
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
          stat = File.stat!(absolute_path)

          info = %{
            name: Path.basename(relative_path),
            relative_path: relative_path,
            absolute_path: absolute_path,
            size: stat.size,
            modified: stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
          }

          {:ok, info}
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
      full_pattern = Path.join(skill_root, pattern)

      full_pattern
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn absolute_path ->
        relative_path = Path.relative_to(absolute_path, skill_root)
        stat = File.stat!(absolute_path)

        %{
          name: Path.basename(relative_path),
          relative_path: relative_path,
          absolute_path: absolute_path,
          size: stat.size,
          modified: stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
        }
      end)
    else
      []
    end
  end

  # Private functions

  defp list_resource_type(skill_root, type) when type in [:scripts, :references, :assets] do
    dir_path = Path.join(skill_root, to_string(type))

    if File.dir?(dir_path) do
      dir_path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn absolute_path ->
        relative_path = Path.relative_to(absolute_path, skill_root)
        stat = File.stat!(absolute_path)

        %{
          name: Path.basename(relative_path),
          relative_path: relative_path,
          absolute_path: absolute_path,
          size: stat.size,
          modified: stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
        }
      end)
      |> Enum.sort_by(& &1.relative_path)
    else
      []
    end
  end
end
