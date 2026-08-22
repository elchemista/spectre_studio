defmodule SpectreStudio.Pulse.ConnectionSpec do
  @moduledoc """
  What Studio needs to know to reach one Pulse endpoint.

  The token is part of the spec but never part of its public projection. Every
  value that leaves this module for a LiveView, a log line or a template goes
  through `to_public/1`.
  """

  alias SpectreStudio.Pulse.Frame

  @enforce_keys [:id, :label, :url]
  defstruct [:id, :label, :url, :token, :inserted_at, verify_tls: true, auto_connect: false]

  @type t :: %__MODULE__{}

  @doc "Builds a spec from operator input."
  @spec new(map()) :: {:ok, t()} | {:error, [{atom(), String.t()}]}
  def new(params) when is_map(params) do
    label = params |> get("label") |> to_string() |> String.trim()
    url = params |> get("url") |> to_string() |> String.trim()
    token = params |> get("token") |> to_string() |> String.trim()

    errors =
      []
      |> validate(label != "", :label, "is required")
      |> validate(valid_url?(url), :url, "must be a ws:// or wss:// URL")

    case errors do
      [] ->
        {:ok,
         %__MODULE__{
           id: get(params, "id") || Frame.uuid7(),
           label: label,
           url: url,
           token: if(token == "", do: nil, else: token),
           verify_tls: truthy(get(params, "verify_tls"), true),
           auto_connect: truthy(get(params, "auto_connect"), false),
           inserted_at: DateTime.utc_now()
         }}

      errors ->
        {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  The projection safe to render.

  `token_set?` reports whether a credential exists without revealing anything
  about it.
  """
  @spec to_public(t()) :: map()
  def to_public(%__MODULE__{} = spec) do
    %{
      id: spec.id,
      label: spec.label,
      url: spec.url,
      verify_tls: spec.verify_tls,
      auto_connect: spec.auto_connect,
      token_set?: is_binary(spec.token),
      inserted_at: spec.inserted_at
    }
  end

  @doc "The host and path shown in the UI, with any credentials stripped."
  @spec display_url(t()) :: String.t()
  def display_url(%__MODULE__{url: url}) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port, path: path} when is_binary(host) ->
        "#{scheme}://#{host}#{port_suffix(scheme, port)}#{path || ""}"

      _invalid ->
        url
    end
  end

  defp port_suffix("wss", 443), do: ""
  defp port_suffix("ws", 80), do: ""
  defp port_suffix(_scheme, nil), do: ""
  defp port_suffix(_scheme, port), do: ":#{port}"

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["ws", "wss"] and is_binary(host) ->
        host != ""

      _invalid ->
        false
    end
  end

  defp validate(errors, true, _field, _message), do: errors
  defp validate(errors, false, field, message), do: [{field, message} | errors]

  defp get(params, key), do: Map.get(params, key) || Map.get(params, String.to_existing_atom(key))

  defp truthy(value, _default) when value in [true, "true", "on", "1"], do: true
  defp truthy(value, _default) when value in [false, "false", "off", "0"], do: false
  defp truthy(_value, default), do: default
end
