defmodule SpectreStudio.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = SpectreStudio.Config.load!()

    children = [
      SpectreStudioWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:spectre_studio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SpectreStudio.PubSub},
      {Registry, keys: :unique, name: SpectreStudio.Pulse.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: SpectreStudio.Pulse.ConnectionSupervisor},
      SpectreStudio.Vault,
      SpectreStudio.Lab.Library,
      SpectreStudio.Pulse.Boot,
      SpectreStudioWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SpectreStudio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SpectreStudioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
