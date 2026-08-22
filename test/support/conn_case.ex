defmodule SpectreStudioWeb.ConnCase do
  @moduledoc """
  Test case for anything that talks to the endpoint.

  Studio has no database and no sign-in, so there is no sandbox and no session
  setup here — only the conveniences for building connections.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint SpectreStudioWeb.Endpoint

      use SpectreStudioWeb, :verified_routes

      # Import conveniences for testing with connections
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import SpectreStudioWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Asserts that a LiveView eventually renders `text`.

  A PubSub broadcast reaches the test process and the LiveView independently, so
  a plain `render/1` right after `assert_receive` can run before the view has
  handled its own copy. This polls instead of guessing at a sleep.
  """
  def assert_eventually(live, text, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_assert_eventually(live, text, deadline)
  end

  defp do_assert_eventually(live, text, deadline) do
    html = Phoenix.LiveViewTest.render(live)

    cond do
      html =~ text ->
        html

      System.monotonic_time(:millisecond) < deadline ->
        Process.sleep(25)
        do_assert_eventually(live, text, deadline)

      true ->
        raise ExUnit.AssertionError,
          message: "the LiveView never rendered #{inspect(text)}"
    end
  end
end
