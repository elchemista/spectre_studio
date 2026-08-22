defmodule SpectreStudio.Config do
  @moduledoc """
  Typed runtime configuration.

  The vault key is read once at boot and kept out of the public projection.
  Studio holds credentials for other people's production systems, so `get/0` —
  the value that reaches LiveViews, logs and templates — must never carry one.
  It is requested explicitly through `fetch_secret!/1` instead.
  """

  @storage_key {__MODULE__, :runtime}

  defstruct [:vault_path, :max_bundle_bytes]

  @type t :: %__MODULE__{}

  @secret_keys [:vault_key]

  @doc "Loads configuration into process-independent storage. Called at boot."
  @spec load!() :: :ok
  def load! do
    env = Application.get_all_env(:spectre_studio)

    public = %__MODULE__{
      vault_path: Keyword.get(env, :vault_path, default_vault_path()),
      max_bundle_bytes: Keyword.get(env, :max_bundle_bytes, 16_000_000)
    }

    secrets = %{vault_key: normalize_key(Keyword.get(env, :vault_key))}

    :persistent_term.put(@storage_key, {public, secrets})
    :ok
  end

  @doc "The public configuration. Safe to pass anywhere."
  @spec get() :: t()
  def get do
    case :persistent_term.get(@storage_key, nil) do
      {public, _secrets} -> public
      nil -> raise "SpectreStudio.Config not loaded"
    end
  end

  @doc "Reads one secret explicitly. Never include the result in a projection."
  @spec fetch_secret!(atom()) :: term()
  def fetch_secret!(key) when key in @secret_keys do
    case :persistent_term.get(@storage_key, nil) do
      {_public, secrets} -> Map.fetch!(secrets, key)
      nil -> raise "SpectreStudio.Config not loaded"
    end
  end

  defp default_vault_path do
    Path.join([File.cwd!(), "priv", "studio", "vault.dets"])
  end

  # A 32-byte key for AES-256-GCM. Without one, the vault refuses to store a
  # token rather than persisting it in the clear.
  defp normalize_key(nil), do: nil

  defp normalize_key(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, <<key::binary-32>>} -> key
      _other -> if byte_size(value) >= 32, do: binary_part(value, 0, 32), else: nil
    end
  end

  defp normalize_key(_other), do: nil
end
