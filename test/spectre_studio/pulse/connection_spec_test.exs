defmodule SpectreStudio.Pulse.ConnectionSpecTest do
  use ExUnit.Case, async: true

  alias SpectreStudio.Pulse.ConnectionSpec

  test "accepts a well formed endpoint" do
    assert {:ok, spec} =
             ConnectionSpec.new(%{
               "label" => "prod",
               "url" => "wss://host/pulse/websocket",
               "token" => "secret"
             })

    assert spec.label == "prod"
    assert spec.verify_tls
    refute spec.auto_connect
  end

  test "requires a label and a websocket URL" do
    assert {:error, errors} = ConnectionSpec.new(%{"label" => "", "url" => "https://host"})
    assert {:label, _message} = List.keyfind(errors, :label, 0)
    assert {:url, _message} = List.keyfind(errors, :url, 0)
  end

  test "the public projection never carries the token" do
    {:ok, spec} =
      ConnectionSpec.new(%{"label" => "p", "url" => "wss://h/p", "token" => "super-secret"})

    public = ConnectionSpec.to_public(spec)

    assert public.token_set?
    refute Map.has_key?(public, :token)
    refute public |> inspect() |> String.contains?("super-secret")
  end

  test "the displayed URL drops the default port" do
    {:ok, spec} = ConnectionSpec.new(%{"label" => "p", "url" => "wss://host/pulse"})
    assert ConnectionSpec.display_url(spec) == "wss://host/pulse"

    {:ok, spec} = ConnectionSpec.new(%{"label" => "p", "url" => "ws://host:4001/pulse"})
    assert ConnectionSpec.display_url(spec) == "ws://host:4001/pulse"
  end
end
