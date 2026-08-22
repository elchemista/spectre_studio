defmodule SpectreStudio.Pulse.Manifest do
  @moduledoc """
  The connection manifest, normalised into Studio's own shape.

  Everything here arrives from a remote peer, so normalisation is defensive by
  construction: missing keys collapse to safe defaults, and no atom is ever
  created from remote input. What the manifest says is what the UI is allowed to
  offer — Studio never assumes a capability the host did not advertise.
  """

  alias SpectreStudio.Pulse.Agent

  @enforce_keys [:connection_id]
  defstruct [
    :connection_id,
    :spec_id,
    :peer_id,
    :transport,
    :status,
    :connected_at,
    :principal_id,
    :principal_identity,
    :principal_kind,
    agents: [],
    granted_scopes: [],
    granted_profiles: [],
    spec_scopes: [],
    spec_profiles: [],
    spec_mode: nil
  ]

  @type t :: %__MODULE__{}

  @doc "Normalises a decoded `manifest` frame."
  @spec normalize(map()) :: {:ok, t()} | {:error, :invalid_manifest}
  def normalize(%{"connection" => connection} = frame) when is_map(connection) do
    spec = map_at(frame, "spec")
    principal = map_at(connection, "principal")

    {:ok,
     %__MODULE__{
       connection_id: string_at(connection, "id"),
       spec_id: string_at(connection, "spec_id"),
       peer_id: string_at(connection, "peer_id"),
       transport: string_at(connection, "transport"),
       status: string_at(connection, "status"),
       connected_at: string_at(connection, "connected_at"),
       principal_id: string_at(principal, "id"),
       principal_identity: string_at(principal, "identity"),
       principal_kind: string_at(principal, "kind"),
       granted_scopes: string_list(connection, "granted_scopes"),
       granted_profiles: string_list(connection, "granted_profiles"),
       spec_scopes: string_list(spec, "scopes"),
       spec_profiles: string_list(spec, "profiles"),
       spec_mode: string_at(spec, "mode"),
       agents:
         frame |> list_at("agents") |> Enum.map(&Agent.normalize/1) |> Enum.reject(&is_nil/1)
     }}
  end

  def normalize(_other), do: {:error, :invalid_manifest}

  @doc "Finds one exposed Agent by canonical address."
  @spec fetch_agent(t(), String.t()) :: {:ok, Agent.t()} | :error
  def fetch_agent(%__MODULE__{agents: agents}, address) do
    case Enum.find(agents, &(&1.address == address)) do
      nil -> :error
      agent -> {:ok, agent}
    end
  end

  defp map_at(map, key) do
    case Map.get(map, key) do
      value when is_map(value) -> value
      _absent -> %{}
    end
  end

  defp list_at(map, key) do
    case Map.get(map, key) do
      value when is_list(value) -> value
      _absent -> []
    end
  end

  defp string_at(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) -> value
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      _absent -> nil
    end
  end

  defp string_list(map, key) do
    map
    |> Map.get(key, [])
    |> case do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _absent -> []
    end
  end
end
