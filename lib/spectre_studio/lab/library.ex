defmodule SpectreStudio.Lab.Library do
  @moduledoc """
  The bundles an operator has loaded into this Studio.

  Held in memory and never written back to disk. A Ledger bundle is a *trusted*
  artefact: Lab documents that Spectre Foundation decoding may load an existing
  module named by a valid checkpoint, so a bundle is closer to code than to
  data. Studio therefore keeps the blast radius small — authenticated upload
  only, a hard size limit, and nothing persisted for a later boot to pick up.
  """

  use GenServer

  alias SpectreStudio.Config
  alias SpectreStudio.Pulse.Frame

  @table :spectre_studio_lab_bundles

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Every loaded bundle, newest first."
  @spec list() :: [map()]
  def list do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, bundle} -> bundle end)
    |> Enum.sort_by(& &1.loaded_at, {:desc, DateTime})
  end

  @doc "Fetches one loaded bundle."
  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(id) do
    case :ets.lookup(@table, id) do
      [{^id, bundle}] -> {:ok, bundle}
      _absent -> :error
    end
  end

  @doc """
  Verifies and loads one bundle.

  Verification is Ledger's, through `Spectre.Lab.load/2`; Studio adds only the
  size guard and the projection.
  """
  @spec load(String.t(), binary()) :: {:ok, map()} | {:error, term()}
  def load(name, contents) when is_binary(contents) do
    GenServer.call(__MODULE__, {:load, name, contents}, 30_000)
  end

  @doc "Forgets one bundle."
  @spec drop(String.t()) :: :ok
  def drop(id), do: GenServer.call(__MODULE__, {:drop, id})

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:load, name, contents}, _from, state) do
    limit = Config.get().max_bundle_bytes

    if byte_size(contents) > limit do
      {:reply, {:error, {:too_large, limit}}, state}
    else
      {:reply, do_load(name, contents), state}
    end
  end

  def handle_call({:drop, id}, _from, state) do
    :ets.delete(@table, id)
    {:reply, :ok, state}
  end

  defp do_load(name, contents) do
    case Spectre.Lab.load(contents) do
      {:ok, playback} ->
        bundle = %{
          id: Frame.uuid7(),
          name: name,
          byte_size: byte_size(contents),
          loaded_at: DateTime.utc_now(),
          stream_id: playback.stream_id,
          verification: playback.verification,
          completeness: playback.completeness,
          playback: playback
        }

        :ets.insert(@table, {bundle.id, bundle})
        {:ok, bundle}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
