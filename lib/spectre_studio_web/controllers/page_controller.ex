defmodule SpectreStudioWeb.PageController do
  use SpectreStudioWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
