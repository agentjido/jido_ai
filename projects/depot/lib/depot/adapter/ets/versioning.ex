defmodule Depot.Adapter.ETS.Versioning do
  @moduledoc """
  Versioning wrapper for ETS adapter.

  This module provides a unified versioning interface for the ETS adapter,
  translating the new Depot.Adapter.Versioning behaviour calls to the 
  existing ETS adapter versioning functions.
  """

  @behaviour Depot.Adapter.Versioning

  alias Depot.Adapter.ETS

  @impl Depot.Adapter.Versioning
  def commit(_config, _message \\ nil, _opts \\ []) do
    # ETS doesn't have a traditional "commit" concept like Git
    # Since ETS writes are immediate, "commit" is effectively a no-op
    # This allows the polymorphic API to work consistently
    :ok
  end

  @impl Depot.Adapter.Versioning
  def revisions(config, path \\ ".", opts \\ []) do
    case ETS.list_versions(config, path) do
      {:ok, versions} ->
        limit = Keyword.get(opts, :limit)
        since = Keyword.get(opts, :since)
        until = Keyword.get(opts, :until)

        filtered_versions =
          versions
          |> filter_by_time_range(since, until)
          |> apply_limit(limit)
          |> Enum.map(&ets_version_to_versioning_format/1)

        {:ok, filtered_versions}

      error ->
        error
    end
  end

  @impl Depot.Adapter.Versioning
  def read_revision(config, path, revision, _opts \\ []) do
    ETS.read_version(config, path, revision)
  end

  @impl Depot.Adapter.Versioning
  def rollback(config, revision, opts \\ []) do
    path = Keyword.get(opts, :path)

    if path do
      # Rollback single file by restoring it from the specified version
      case ETS.read_version(config, path, revision) do
        {:ok, content} ->
          ETS.write(config, path, content, [])

        error ->
          error
      end
    else
      # Full rollback not supported for ETS
      {:error, :unsupported}
    end
  end

  # Helper functions

  defp filter_by_time_range(versions, since, until) do
    versions
    |> filter_since(since)
    |> filter_until(until)
  end

  defp filter_since(versions, nil), do: versions

  defp filter_since(versions, since) do
    since_timestamp = DateTime.to_unix(since)
    Enum.filter(versions, fn version -> version.timestamp >= since_timestamp end)
  end

  defp filter_until(versions, nil), do: versions

  defp filter_until(versions, until) do
    until_timestamp = DateTime.to_unix(until)
    Enum.filter(versions, fn version -> version.timestamp <= until_timestamp end)
  end

  defp apply_limit(versions, nil), do: versions
  defp apply_limit(versions, limit), do: Enum.take(versions, limit)

  # Convert ETS version format to Versioning behaviour format
  defp ets_version_to_versioning_format(%{version_id: version_id, timestamp: timestamp}) do
    %{
      revision: version_id,
      author_name: "ETS Adapter",
      author_email: "ets@depot.local",
      message:
        "ETS version created at #{DateTime.from_unix!(timestamp) |> DateTime.to_iso8601()}",
      timestamp: DateTime.from_unix!(timestamp)
    }
  end
end
