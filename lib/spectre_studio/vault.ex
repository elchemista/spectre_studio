defmodule SpectreStudio.Vault do
  @moduledoc """
  Persistent storage for connection specs.

  Studio has no relational domain — a handful of endpoints and their
  credentials — so this is a DETS table rather than a database. What matters is
  the credential handling: tokens are sealed with AES-256-GCM before they touch
  the disk, and a Studio started without a vault key refuses to persist a token
  at all rather than writing it in the clear.
  """

  use GenServer

  alias SpectreStudio.Config
  alias SpectreStudio.Pulse.ConnectionSpec

  @table :spectre_studio_vault
  @aad "spectre-studio/connection-token/v1"

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Every stored connection spec, oldest first."
  @spec list() :: [ConnectionSpec.t()]
  def list do
    @table
    |> :dets.match_object({:_, :_})
    |> Enum.map(fn {_id, stored} -> unseal(stored) end)
    |> Enum.sort_by(& &1.inserted_at, DateTime)
  end

  @doc "Fetches one spec by id."
  @spec fetch(String.t()) :: {:ok, ConnectionSpec.t()} | :error
  def fetch(id) when is_binary(id) do
    case :dets.lookup(@table, id) do
      [{^id, stored}] -> {:ok, unseal(stored)}
      _absent -> :error
    end
  end

  @doc """
  Stores a spec.

  Returns `{:error, :vault_key_missing}` when a token was supplied but no key is
  configured to seal it. Refusing is the only honest option: the alternative is
  writing someone's production credential to disk in plaintext.
  """
  @spec put(ConnectionSpec.t()) :: :ok | {:error, term()}
  def put(%ConnectionSpec{} = spec), do: GenServer.call(__MODULE__, {:put, spec})

  @doc "Deletes a spec."
  @spec delete(String.t()) :: :ok
  def delete(id) when is_binary(id), do: GenServer.call(__MODULE__, {:delete, id})

  @impl GenServer
  def init(_opts) do
    path = Config.get().vault_path
    File.mkdir_p!(Path.dirname(path))

    case :dets.open_file(@table, file: String.to_charlist(path), type: :set) do
      {:ok, @table} -> {:ok, %{path: path}}
      {:error, reason} -> {:stop, {:vault_unavailable, reason}}
    end
  end

  @impl GenServer
  def handle_call({:put, spec}, _from, state) do
    case seal(spec) do
      {:ok, stored} ->
        :ok = :dets.insert(@table, {spec.id, stored})
        :dets.sync(@table)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete, id}, _from, state) do
    :ok = :dets.delete(@table, id)
    :dets.sync(@table)
    {:reply, :ok, state}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    :dets.close(@table)
    :ok
  end

  # --- sealing ---------------------------------------------------------------

  defp seal(%ConnectionSpec{token: nil} = spec) do
    {:ok, %{spec: %{spec | token: nil}, token: nil}}
  end

  defp seal(%ConnectionSpec{token: token} = spec) do
    case Config.fetch_secret!(:vault_key) do
      key when is_binary(key) ->
        iv = :crypto.strong_rand_bytes(12)

        {ciphertext, tag} =
          :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, token, @aad, true)

        {:ok, %{spec: %{spec | token: nil}, token: {iv, tag, ciphertext}}}

      _missing ->
        {:error, :vault_key_missing}
    end
  end

  defp unseal(%{spec: spec, token: nil}), do: spec

  defp unseal(%{spec: spec, token: {iv, tag, ciphertext}}) do
    case Config.fetch_secret!(:vault_key) do
      key when is_binary(key) ->
        case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
          token when is_binary(token) -> %{spec | token: token}
          # A rotated or wrong key must not take the endpoint down with it: the
          # spec stays usable and the operator is asked for the token again.
          _error -> %{spec | token: nil}
        end

      _missing ->
        %{spec | token: nil}
    end
  end
end
