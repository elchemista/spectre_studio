defmodule SpectreStudio.VaultTest do
  use ExUnit.Case, async: false

  alias SpectreStudio.Pulse.ConnectionSpec
  alias SpectreStudio.Vault

  setup do
    on_exit(fn -> Enum.each(Vault.list(), &Vault.delete(&1.id)) end)
    :ok
  end

  defp spec(overrides \\ %{}) do
    {:ok, spec} =
      %{"label" => "prod", "url" => "wss://host/pulse", "token" => "super-secret"}
      |> Map.merge(overrides)
      |> ConnectionSpec.new()

    spec
  end

  test "round-trips a spec and its sealed token" do
    spec = spec()
    assert :ok = Vault.put(spec)

    assert {:ok, loaded} = Vault.fetch(spec.id)
    assert loaded.label == "prod"
    assert loaded.token == "super-secret"
  end

  test "the token is not stored in the clear" do
    spec = spec()
    :ok = Vault.put(spec)

    contents = File.read!(SpectreStudio.Config.get().vault_path)
    refute contents =~ "super-secret"
  end

  test "a spec without a token needs no key" do
    spec = spec(%{"token" => ""})
    assert :ok = Vault.put(spec)
    assert {:ok, loaded} = Vault.fetch(spec.id)
    assert loaded.token == nil
  end

  test "listing and deleting" do
    first = spec(%{"label" => "one"})
    second = spec(%{"label" => "two"})
    :ok = Vault.put(first)
    :ok = Vault.put(second)

    labels = Vault.list() |> Enum.map(& &1.label) |> Enum.sort()
    assert labels == ["one", "two"]

    :ok = Vault.delete(first.id)
    assert :error = Vault.fetch(first.id)
  end
end
