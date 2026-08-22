defmodule SpectreStudio.Pulse do
  @moduledoc """
  The Pulse boundary of Studio.

  Everything the web layer needs to configure endpoints and reach live
  connections goes through here. It keeps two things in agreement: the stored
  specs in `SpectreStudio.Vault` and the running processes under the connection
  supervisor.
  """

  alias SpectreStudio.Pulse.Connection
  alias SpectreStudio.Pulse.ConnectionSpec
  alias SpectreStudio.Pulse.Events
  alias SpectreStudio.Vault

  @supervisor SpectreStudio.Pulse.ConnectionSupervisor

  @doc "Starts a connection process for every stored spec."
  @spec start_stored() :: :ok
  def start_stored do
    Enum.each(Vault.list(), &ensure_started/1)
  end

  @doc "Every configured connection, with its live status folded in."
  @spec list() :: [map()]
  def list do
    Enum.map(Vault.list(), &describe/1)
  end

  @doc "One configured connection with its live status."
  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(id) do
    case Vault.fetch(id) do
      {:ok, spec} -> {:ok, describe(spec)}
      :error -> :error
    end
  end

  @doc "The spec itself, credentials included. Never render this."
  @spec fetch_spec(String.t()) :: {:ok, ConnectionSpec.t()} | :error
  def fetch_spec(id), do: Vault.fetch(id)

  @doc "Creates or replaces a connection spec and its process."
  @spec save(map()) :: {:ok, ConnectionSpec.t()} | {:error, term()}
  def save(params) do
    with {:ok, spec} <- ConnectionSpec.new(params),
         :ok <- Vault.put(spec) do
      restart(spec)
      Events.directory_changed()
      {:ok, spec}
    end
  end

  @doc "Removes a connection entirely."
  @spec delete(String.t()) :: :ok
  def delete(id) do
    stop(id)
    :ok = Vault.delete(id)
    Events.directory_changed()
    :ok
  end

  @doc "Opens the socket for one connection."
  @spec connect(String.t()) :: :ok | {:error, term()}
  def connect(id) do
    with {:ok, spec} <- Vault.fetch(id),
         {:ok, _pid} <- ensure_started(spec) do
      Connection.connect(id)
    else
      :error -> {:error, :unknown_connection}
      error -> error
    end
  end

  @doc "Closes the socket for one connection and stops retrying."
  @spec disconnect(String.t()) :: :ok | {:error, term()}
  def disconnect(id), do: Connection.disconnect(id)

  @doc "Current state of one connection."
  @spec snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def snapshot(id), do: Connection.snapshot(id)

  @doc "Starts the process for a spec if it is not already running."
  @spec ensure_started(ConnectionSpec.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(%ConnectionSpec{} = spec) do
    case DynamicSupervisor.start_child(@supervisor, {Connection, spec: spec}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  defp restart(spec) do
    stop(spec.id)
    ensure_started(spec)
  end

  defp stop(id) do
    case Registry.lookup(SpectreStudio.Pulse.Registry, id) do
      [{pid, _value}] -> DynamicSupervisor.terminate_child(@supervisor, pid)
      [] -> :ok
    end
  end

  defp describe(spec) do
    base = %{
      id: spec.id,
      label: spec.label,
      spec: ConnectionSpec.to_public(spec),
      display_url: ConnectionSpec.display_url(spec),
      status: :idle,
      manifest: nil,
      last_error: nil,
      attempt: 0,
      events: [],
      subscriptions: %{},
      sent: []
    }

    case Connection.snapshot(spec.id) do
      {:ok, snapshot} -> Map.merge(base, snapshot)
      {:error, _reason} -> base
    end
  end

  @doc """
  Maps a connection status onto the LED vocabulary.

  Four states, not more: what an operator needs to know at a glance is whether
  the connection is usable, working on it, deliberately closed, or broken.
  """
  @spec led_state(atom()) :: :ok | :wait | :fail | :idle
  def led_state(:ready), do: :ok
  def led_state(status) when status in [:connecting, :authenticating, :degraded], do: :wait
  def led_state(:error), do: :fail
  def led_state(_status), do: :idle
end
