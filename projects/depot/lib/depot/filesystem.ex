defmodule Depot.Filesystem do
  @moduledoc """
  Behaviour of a `Depot` filesystem.
  """
  @callback write(path :: Path.t(), contents :: binary, opts :: keyword()) :: :ok | {:error, term}
  @callback read(path :: Path.t(), opts :: keyword()) :: {:ok, binary} | {:error, term}
  @callback read_stream(path :: Path.t(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term}
  @callback delete(path :: Path.t(), opts :: keyword()) :: :ok | {:error, term}
  @callback move(source :: Path.t(), destination :: Path.t(), opts :: keyword()) ::
              :ok | {:error, term}
  @callback copy(source :: Path.t(), destination :: Path.t(), opts :: keyword()) ::
              :ok | {:error, term}
  @callback file_exists(path :: Path.t(), opts :: keyword()) ::
              {:ok, :exists | :missing} | {:error, term}
  @callback list_contents(path :: Path.t(), opts :: keyword()) ::
              {:ok, [%Depot.Stat.Dir{} | %Depot.Stat.File{}]} | {:error, term}

  @doc false
  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Depot.Filesystem
      {adapter, opts} = Depot.Filesystem.parse_opts(__MODULE__, opts)
      @adapter adapter
      @opts opts
      @key {Depot.Filesystem, __MODULE__}

      def init do
        filesystem =
          @opts
          |> Depot.Filesystem.merge_app_env(__MODULE__)
          |> @adapter.configure()

        :persistent_term.put(@key, filesystem)

        filesystem
      end

      def __filesystem__ do
        :persistent_term.get(@key, init())
      end

      if adapter.starts_processes() do
        def child_spec(_) do
          Supervisor.child_spec(__filesystem__(), %{})
        end
      end

      @impl true
      def write(path, contents, opts \\ []),
        do: Depot.write(__filesystem__(), path, contents, opts)

      @impl true
      def read(path, opts \\ []),
        do: Depot.read(__filesystem__(), path, opts)

      @impl true
      def read_stream(path, opts \\ []),
        do: Depot.read_stream(__filesystem__(), path, opts)

      @impl true
      def delete(path, opts \\ []),
        do: Depot.delete(__filesystem__(), path, opts)

      @impl true
      def move(source, destination, opts \\ []),
        do: Depot.move(__filesystem__(), source, destination, opts)

      @impl true
      def copy(source, destination, opts \\ []),
        do: Depot.copy(__filesystem__(), source, destination, opts)

      @impl true
      def file_exists(path, opts \\ []),
        do: Depot.file_exists(__filesystem__(), path, opts)

      @impl true
      def list_contents(path, opts \\ []),
        do: Depot.list_contents(__filesystem__(), path, opts)
    end
  end

  def parse_opts(module, opts) do
    opts
    |> merge_app_env(module)
    |> Keyword.put_new(:name, module)
    |> Keyword.pop!(:adapter)
  end

  def merge_app_env(opts, module) do
    case Keyword.fetch(opts, :otp_app) do
      {:ok, otp_app} ->
        config = Application.get_env(otp_app, module, [])
        Keyword.merge(opts, config)

      :error ->
        opts
    end
  end
end
