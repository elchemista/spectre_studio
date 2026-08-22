defmodule SpectreStudio.Pulse.Agent do
  @moduledoc """
  One Agent exposed by a connection, as advertised in the manifest.

  This is the descriptor, not the Agent: Studio knows an address, a name and the
  capabilities the host chose to publish. It holds no reasoning, no state and no
  process.
  """

  @enforce_keys [:address]
  defstruct [:address, :display_name, capabilities: [], protocol_versions: [], metadata: %{}]

  @type t :: %__MODULE__{}

  @doc "Normalises one `AgentDescriptor` wire map. Returns `nil` if unusable."
  @spec normalize(term()) :: t() | nil
  def normalize(%{"address" => address} = wire) when is_binary(address) do
    %__MODULE__{
      address: address,
      display_name: display_name(wire, address),
      capabilities: strings(wire, "capabilities"),
      protocol_versions: integers(wire, "protocol_versions"),
      metadata: metadata(wire)
    }
  end

  def normalize(_other), do: nil

  @doc """
  Encodes a canonical address for use as a single path segment.

  `spectre://acme/researcher` cannot travel as path segments: Plug drops the
  empty segment produced by `//`, and the address would come back as
  `spectre:/acme/researcher`. Base64url keeps it exact and keeps the route
  unambiguous.
  """
  @spec encode_address(String.t()) :: String.t()
  def encode_address(address), do: Base.url_encode64(address, padding: false)

  @doc "Decodes an address from a path segment."
  @spec decode_address(String.t()) :: {:ok, String.t()} | :error
  def decode_address(encoded) when is_binary(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, address} -> {:ok, address}
      :error -> :error
    end
  end

  def decode_address(_other), do: :error

  @doc "The last segment of the canonical address, used as a compact label."
  @spec short_name(t()) :: String.t()
  def short_name(%__MODULE__{address: address}) do
    address |> String.split("/") |> List.last()
  end

  defp display_name(wire, address) do
    case Map.get(wire, "display_name") do
      name when is_binary(name) and name != "" -> name
      _absent -> address |> String.split("/") |> List.last()
    end
  end

  defp strings(wire, key) do
    case Map.get(wire, key) do
      values when is_list(values) -> Enum.filter(values, &is_binary/1)
      _absent -> []
    end
  end

  defp integers(wire, key) do
    case Map.get(wire, key) do
      values when is_list(values) -> Enum.filter(values, &is_integer/1)
      _absent -> []
    end
  end

  defp metadata(wire) do
    case Map.get(wire, "metadata") do
      value when is_map(value) -> value
      _absent -> %{}
    end
  end
end
