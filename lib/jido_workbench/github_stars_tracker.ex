defmodule JidoWorkbench.GithubStarsTracker do
  use GenServer
  require Logger

  @default_repo "agentjido/jido"
  @default_refresh_interval :timer.hours(1)

  # Client API

  def start_link(opts \\ []) do
    repo = Keyword.get(opts, :repo, @default_repo)
    refresh_interval = Keyword.get(opts, :refresh_interval, @default_refresh_interval)
    GenServer.start_link(__MODULE__, {repo, refresh_interval}, name: __MODULE__)
  end

  def get_stars do
    GenServer.call(__MODULE__, :get_stars)
  end

  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  # Server Callbacks

  @impl true
  def init({repo, refresh_interval}) do
    state = %{
      repo: repo,
      stars: nil,
      last_updated: nil,
      refresh_interval: refresh_interval
    }

    # Schedule initial fetch
    send(self(), :refresh)
    # Schedule periodic updates
    schedule_refresh(refresh_interval)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_stars, _from, state) do
    {:reply, {state.stars, state.last_updated}, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, fetch_stars(state)}
  end

  @impl true
  def handle_info(:refresh, state) do
    # Schedule next refresh
    schedule_refresh(state.refresh_interval)
    # Fetch stars
    {:noreply, fetch_stars(state)}
  end

  # Private Functions

  defp schedule_refresh(interval) do
    Process.send_after(self(), :refresh, interval)
  end

  defp fetch_stars(state) do
    case get_repo_stars(state.repo) do
      {:ok, stars} ->
        %{state | stars: stars, last_updated: DateTime.utc_now()}

      {:error, reason} ->
        Logger.error("Failed to fetch GitHub stars: #{inspect(reason)}")
        state
    end
  end

  defp get_repo_stars(repo) do
    url = "https://api.github.com/repos/#{repo}"

    headers = [
      {"Accept", "application/vnd.github.v3+json"},
      {"User-Agent", "JidoWorkbench"}
    ]

    case Finch.build(:get, url, headers) |> Finch.request(JidoWorkbench.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"stargazers_count" => stars}} -> {:ok, stars}
          _ -> {:error, :invalid_response}
        end

      {:ok, %Finch.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
