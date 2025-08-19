defmodule JidoWorkbenchWeb.Plug.Heartbeat do
  @moduledoc """
  provides an endpoint for testing application health and validating deployments
  """
  import Plug.Conn

  def init(options) do
    options
  end

  def call(%Plug.Conn{method: "GET", request_path: "/status"} = conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
    |> halt()
  end

  # sobelow_skip ["Traversal.FileModule"]
  def call(%Plug.Conn{method: "GET", request_path: "/status/" <> hash_to_check} = conn, _opts) do
    # the hash file is expected to be populated as a part of the build process

    priv_dir = :code.priv_dir(:jido_workbench)
    hash_file = "#{priv_dir}/hash"

    build_hash =
      hash_file
      |> File.read!()
      |> String.replace("\n", "")

    if hash_to_check == build_hash do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "ok")
      |> halt()
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(500, "hash does not match")
      |> halt()
    end
  end

  def call(conn, _opts) do
    conn
  end
end
