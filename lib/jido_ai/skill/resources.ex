defmodule Jido.AI.Skill.Resources do
  @moduledoc """
  Provides bounded, lazy access to files bundled with a skill.

  General listing includes each regular file below the skill root except the
  root `SKILL.md`. Root files and custom directories are valid resources.
  Conventional `scripts`, `references`, and `assets` groups remain available in
  the listing. Paths in returned listings are relative to the skill root.

  Listing does not follow symlinks. Loading rejects traversal, absolute paths,
  and symlinks. `Jido.AI.Skill.ResourcePolicy` supplies all limits.
  """

  alias Jido.AI.Skill.ResourcePolicy

  @context_policy_key :__jido_ai_skill_resource_policy__

  @type resource_info :: %{
          name: String.t(),
          relative_path: String.t(),
          size: non_neg_integer(),
          modified: DateTime.t()
        }

  @type resource_listing :: %{
          resources: [resource_info()],
          scripts: [resource_info()],
          references: [resource_info()],
          assets: [resource_info()],
          complete: boolean(),
          truncated: boolean(),
          truncation_reasons: [atom()],
          limits: map()
        }

  @type resource_type :: :scripts | :references | :assets

  @doc false
  @spec context_policy_key() :: atom()
  def context_policy_key, do: @context_policy_key

  @doc """
  Returns the default resource policy.
  """
  @spec default_policy() :: ResourcePolicy.t()
  def default_policy, do: ResourcePolicy.default()

  @doc """
  Gets a validated resource policy from action context.

  The default policy is returned when the reserved context key is absent.
  """
  @spec policy_from_context(map()) :: {:ok, ResourcePolicy.t()} | {:error, term()}
  def policy_from_context(context) when is_map(context) do
    value =
      Map.get(
        context,
        @context_policy_key,
        Map.get(context, Atom.to_string(@context_policy_key), ResourcePolicy.default())
      )

    ResourcePolicy.new(value)
  end

  @doc """
  Lists all bundled resources with explicit bounds.

  Results are sorted by relative path. If a limit prevents a complete result,
  `complete` is false and `truncation_reasons` identifies each reached limit.
  """
  @spec list_all(String.t(), ResourcePolicy.t() | keyword() | map()) ::
          {:ok, resource_listing()} | {:error, term()}
  def list_all(skill_root, policy_or_opts \\ []) when is_binary(skill_root) do
    with {:ok, policy} <- ResourcePolicy.new(policy_or_opts) do
      expanded_root = Path.expand(skill_root)

      state =
        if directory?(expanded_root) do
          walk_directory(expanded_root, expanded_root, 0, policy, initial_state())
        else
          initial_state()
        end

      {:ok, build_listing(Enum.reverse(state.resources), state.reasons, policy)}
    end
  end

  @doc """
  Returns an empty, complete listing for a selected policy.
  """
  @spec empty_listing(ResourcePolicy.t() | keyword() | map()) ::
          {:ok, resource_listing()} | {:error, term()}
  def empty_listing(policy_or_opts \\ []) do
    with {:ok, policy} <- ResourcePolicy.new(policy_or_opts) do
      {:ok, build_listing([], MapSet.new(), policy)}
    end
  end

  @doc """
  Lists all resources and keeps conventional groups for compatibility.

  This function uses the default policy. Use `list_all/2` for custom limits.
  """
  @spec list_resources(String.t()) :: resource_listing()
  def list_resources(skill_root) when is_binary(skill_root) do
    {:ok, listing} = list_all(skill_root, ResourcePolicy.default())
    listing
  end

  @doc """
  Lists one conventional resource group with the default policy.
  """
  @spec list_by_type(String.t(), resource_type()) :: [resource_info()]
  def list_by_type(skill_root, type) when type in [:scripts, :references, :assets] do
    list_resources(skill_root)[type]
  end

  @doc """
  Loads resource bytes with the default file-size limit.
  """
  @spec load_resource(String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def load_resource(skill_root, relative_path) do
    load_resource(skill_root, relative_path, ResourcePolicy.default())
  end

  @doc """
  Loads resource bytes with a selected resource policy.
  """
  @spec load_resource(String.t(), String.t(), ResourcePolicy.t() | keyword() | map()) ::
          {:ok, binary()} | {:error, term()}
  def load_resource(skill_root, relative_path, policy_or_opts)
      when is_binary(skill_root) and is_binary(relative_path) do
    with {:ok, policy} <- ResourcePolicy.new(policy_or_opts),
         {:ok, absolute_path, _normalized_path, stat} <-
           resolve_loadable_file(skill_root, relative_path),
         :ok <- within_size(stat.size, policy.max_file_bytes, :file) do
      read_bounded(absolute_path, policy.max_file_bytes, :file, stat)
    end
  end

  @doc """
  Loads a resource as bounded UTF-8 text with the default policy.
  """
  @spec load_resource_text(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def load_resource_text(skill_root, relative_path) do
    case load_text(skill_root, relative_path, ResourcePolicy.default()) do
      {:ok, %{content: content}} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Loads one resource as bounded UTF-8 text.

  The result includes the normalized relative path and byte size. Binary
  content returns `:binary_resource`.
  """
  @spec load_text(String.t(), String.t(), ResourcePolicy.t() | keyword() | map()) ::
          {:ok, %{content: String.t(), relative_path: String.t(), size: non_neg_integer()}}
          | {:error, term()}
  def load_text(skill_root, relative_path, policy_or_opts \\ [])
      when is_binary(skill_root) and is_binary(relative_path) do
    with {:ok, policy} <- ResourcePolicy.new(policy_or_opts),
         {:ok, absolute_path, normalized_path, stat} <-
           resolve_loadable_file(skill_root, relative_path),
         :ok <- within_size(stat.size, policy.max_file_bytes, :file),
         :ok <- within_size(stat.size, policy.max_text_bytes, :text),
         {:ok, content} <- read_bounded(absolute_path, policy.max_text_bytes, :text, stat),
         true <- String.valid?(content) do
      {:ok, %{content: content, relative_path: normalized_path, size: byte_size(content)}}
    else
      false -> {:error, :binary_resource}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resolves a relative path inside the skill root.

  Absolute paths, traversal, and paths that resolve through an escaping symlink
  return `:path_traversal`.
  """
  @spec resolve_path(String.t(), String.t()) :: {:ok, String.t()} | {:error, :path_traversal}
  def resolve_path(skill_root, relative_path) when is_binary(skill_root) and is_binary(relative_path) do
    if Path.type(relative_path) == :absolute do
      {:error, :path_traversal}
    else
      do_resolve_path(skill_root, relative_path)
    end
  end

  @doc """
  Checks if a safe regular resource exists.
  """
  @spec exists?(String.t(), String.t()) :: boolean()
  def exists?(skill_root, relative_path) when is_binary(skill_root) and is_binary(relative_path) do
    match?(
      {:ok, _absolute_path, _normalized_path, _stat},
      resolve_loadable_file(skill_root, relative_path)
    )
  end

  @doc """
  Gets information about a safe regular resource.
  """
  @spec resource_info(String.t(), String.t()) :: {:ok, resource_info()} | {:error, :not_found}
  def resource_info(skill_root, relative_path) when is_binary(skill_root) and is_binary(relative_path) do
    case resolve_loadable_file(skill_root, relative_path) do
      {:ok, _absolute_path, normalized_path, stat} ->
        {:ok, resource_info_for(normalized_path, stat)}

      {:error, _reason} ->
        {:error, :not_found}
    end
  end

  @doc """
  Searches the bounded general listing with a glob pattern.
  """
  @spec search(String.t(), String.t()) :: [resource_info()]
  def search(skill_root, pattern) when is_binary(skill_root) and is_binary(pattern) do
    with {:ok, regex} <- glob_regex(pattern),
         {:ok, listing} <- list_all(skill_root) do
      Enum.filter(listing.resources, &Regex.match?(regex, &1.relative_path))
    else
      _error -> []
    end
  end

  defp initial_state do
    %{resources: [], count: 0, directories: 0, reasons: MapSet.new(), halt: false}
  end

  defp walk_directory(_root, _directory, _depth, _policy, %{halt: true} = state), do: state

  defp walk_directory(root, directory, depth, policy, state) do
    if state.directories >= policy.max_directories do
      truncate(state, :max_directories, true)
    else
      state = %{state | directories: state.directories + 1}

      case File.ls(directory) do
        {:ok, entries} ->
          entries
          |> Enum.sort()
          |> Enum.reduce_while(state, fn entry, acc ->
            next = walk_entry(root, Path.join(directory, entry), depth, policy, acc)
            if next.halt, do: {:halt, next}, else: {:cont, next}
          end)

        {:error, _reason} ->
          truncate(state, :unreadable_directory, false)
      end
    end
  end

  defp walk_entry(root, path, depth, policy, state) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular} = stat} ->
        relative_path = Path.relative_to(path, root)

        if relative_path == "SKILL.md" do
          state
        else
          add_resource(resource_info_for(relative_path, stat), policy, state)
        end

      {:ok, %File.Stat{type: :directory}} when depth < policy.max_depth ->
        walk_directory(root, path, depth + 1, policy, state)

      {:ok, %File.Stat{type: :directory}} ->
        truncate(state, :max_depth, false)

      _other ->
        state
    end
  end

  defp add_resource(_resource, policy, %{count: count} = state) when count >= policy.max_resources do
    truncate(state, :max_resources, true)
  end

  defp add_resource(resource, policy, state) do
    resources = [resource | state.resources]

    if listing_payload_size(resources) > policy.max_listing_bytes do
      truncate(state, :max_listing_bytes, true)
    else
      %{state | resources: resources, count: state.count + 1}
    end
  end

  defp truncate(state, reason, halt?) do
    %{state | reasons: MapSet.put(state.reasons, reason), halt: state.halt or halt?}
  end

  defp listing_payload_size(resources) do
    resources
    |> Enum.reverse()
    |> Jason.encode!()
    |> byte_size()
  end

  defp build_listing(resources, reasons, policy) do
    reasons = reasons |> MapSet.to_list() |> Enum.sort()

    %{
      resources: resources,
      scripts: resources_in_group(resources, "scripts"),
      references: resources_in_group(resources, "references"),
      assets: resources_in_group(resources, "assets"),
      complete: reasons == [],
      truncated: reasons != [],
      truncation_reasons: reasons,
      limits: ResourcePolicy.to_map(policy)
    }
  end

  defp resources_in_group(resources, group) do
    prefix = group <> "/"
    Enum.filter(resources, &String.starts_with?(&1.relative_path, prefix))
  end

  defp resolve_loadable_file(skill_root, relative_path) do
    with false <- relative_path == "SKILL.md",
         {:ok, absolute_path} <- resolve_path(skill_root, relative_path),
         {:ok, stat} <- File.lstat(absolute_path),
         :ok <- reject_symlink_path(skill_root, absolute_path),
         :ok <- require_regular_file(stat) do
      normalized_path = Path.relative_to(absolute_path, Path.expand(skill_root))
      {:ok, absolute_path, normalized_path, stat}
    else
      true -> {:error, :invalid_resource_path}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reject_symlink_path(skill_root, absolute_path) do
    if symlink_free?(skill_root, absolute_path), do: :ok, else: {:error, :path_traversal}
  end

  defp require_regular_file(%File.Stat{type: :regular}), do: :ok
  defp require_regular_file(%File.Stat{type: :symlink}), do: {:error, :path_traversal}
  defp require_regular_file(%File.Stat{}), do: {:error, :not_found}

  defp within_size(size, limit, _kind) when size <= limit, do: :ok
  defp within_size(size, limit, kind), do: {:error, {:resource_too_large, kind, size, limit}}

  defp read_bounded(path, limit, kind, expected_stat) do
    with {:ok, io} <- File.open(path, [:read, :binary]) do
      try do
        with {:ok, opened_stat} <- opened_file_stat(io),
             :ok <- same_file(expected_stat, opened_stat) do
          case IO.binread(io, limit + 1) do
            content when is_binary(content) and byte_size(content) <= limit ->
              {:ok, content}

            content when is_binary(content) ->
              {:error, {:resource_too_large, kind, byte_size(content), limit}}

            :eof ->
              {:ok, ""}

            {:error, reason} ->
              {:error, reason}
          end
        end
      after
        File.close(io)
      end
    end
  end

  defp opened_file_stat(io) do
    case :file.read_file_info(io, time: :universal) do
      {:ok, record} -> {:ok, File.Stat.from_record(record)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp same_file(expected, opened) do
    identity = {expected.major_device, expected.minor_device, expected.inode}
    opened_identity = {opened.major_device, opened.minor_device, opened.inode}

    if identity == opened_identity and opened.type == :regular do
      :ok
    else
      {:error, :resource_path_changed}
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

  defp symlink_free?(skill_root, absolute_path) do
    root = Path.expand(skill_root)

    absolute_path
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.reduce_while(root, fn part, current ->
      next = Path.join(current, part)

      case File.lstat(next) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, false}
        {:ok, _stat} -> {:cont, next}
        {:error, _reason} -> {:halt, false}
      end
    end)
    |> is_binary()
  end

  defp directory?(path) do
    match?({:ok, %File.Stat{type: :directory}}, File.lstat(path))
  end

  defp within_path?(path, "/"), do: Path.type(path) == :absolute
  defp within_path?(path, root), do: path == root or String.starts_with?(path, root <> "/")

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
      {:ok, %File.Stat{type: :symlink}} -> resolve_link(candidate, current, rest, seen)
      {:ok, _stat} -> do_resolve_symlinks(candidate, rest, seen)
      {:error, :enoent} -> {:missing, append_path(candidate, rest)}
      {:error, reason} -> {:error, reason}
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

  defp resource_info_for(relative_path, stat) do
    %{
      name: Path.basename(relative_path),
      relative_path: relative_path,
      size: stat.size,
      modified: stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
    }
  end

  defp glob_regex(pattern) do
    source =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*/", "(?:.*/)?")
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")
      |> String.replace("\\?", "[^/]")

    Regex.compile("^" <> source <> "$")
  end
end
