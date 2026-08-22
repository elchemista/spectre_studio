defmodule SpectreStudioWeb.Router do
  use SpectreStudioWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SpectreStudioWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; " <>
          "script-src 'self'; connect-src 'self' ws: wss:; frame-ancestors 'none'; base-uri 'self'",
      "referrer-policy" => "no-referrer"
    }
  end

  scope "/", SpectreStudioWeb do
    pipe_through :browser

    # Studio has no sign-in: launching it opens the dashboard. It is an operator
    # tool bound to loopback by default, and the endpoint that reaches it is the
    # boundary — see the deployment note in README.md before exposing the port.
    #
    # One live_session for everything, so moving between panels reuses the same
    # LiveView socket instead of reloading the page.
    live_session :studio, on_mount: {SpectreStudioWeb.Nav, :default} do
      live "/", ConnectionLive.Index, :index
      # The dashboard also answers on /connections, so a bookmarked or shared
      # panel URL keeps working.
      live "/connections", ConnectionLive.Index, :index
      live "/connections/new", ConnectionLive.Form, :new
      live "/connections/:id/edit", ConnectionLive.Form, :edit
      live "/connections/:id", ConnectionLive.Show, :show

      live "/connections/:id/agents/:address", AgentLive.Overview, :show
      live "/connections/:id/agents/:address/monitor", AgentLive.Monitor, :show
      live "/connections/:id/agents/:address/operations", AgentLive.Operations, :show
      live "/connections/:id/agents/:address/cache", AgentLive.Cache, :show
      live "/connections/:id/agents/:address/evolve", AgentLive.Evolve, :show
      live "/connections/:id/agents/:address/messages", AgentLive.Messages, :show
      live "/connections/:id/agents/:address/events", AgentLive.Events, :show

      live "/lab", LabLive.Index, :index
      live "/lab/:id", LabLive.Show, :show
      live "/lab/:id/diff/:other", LabLive.Diff, :show
    end
  end
end
