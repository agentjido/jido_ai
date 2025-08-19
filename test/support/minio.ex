defmodule DepotTest.Minio do
  require Logger

  def start_link do
    cur = Process.flag(:trap_exit, true)

    try do
      {:ok, _pid} = MinioServer.start_link(config())
    rescue
      exception in [MatchError] ->
        case exception.term do
          {:error, {:shutdown, {:failed_to_start_child, MuonTrap.Daemon, {:enoent, _}}}} ->
            reraise """
                    Minio binaries not available.

                    Make sure to to run:
                    $ MIX_ENV=test mix minio_server.download --arch … --version latest
                    """,
                    __STACKTRACE__

          _ ->
            reraise exception, __STACKTRACE__
        end
    after
      Process.flag(:trap_exit, cur)
    end
  end

  def config do
    [
      access_key_id: "minio_key",
      secret_access_key: "minio_secret",
      scheme: "http://",
      region: "local",
      host: "127.0.0.1",
      port: 9000,
      console_address: ":9001"
    ]
  end

  def initialize_bucket(name) do
    ExAws.S3.put_bucket(name, Keyword.fetch!(config(), :region))
    |> ExAws.request(config())
  end

  def recreate_bucket(name) do
    ExAws.S3.delete_bucket(name)
    |> ExAws.request(config())

    {:ok, _} =
      ExAws.S3.put_bucket(name, Keyword.fetch!(config(), :region))
      |> ExAws.request(config())
  end

  def clean_bucket(name) do
    with {:ok, %{body: %{contents: list}}} <-
           ExAws.S3.list_objects(name)
           |> ExAws.request(config()) do
      for item <- list do
        ExAws.S3.delete_object(name, item.key) |> ExAws.request(config())
      end
    end
  end
end
