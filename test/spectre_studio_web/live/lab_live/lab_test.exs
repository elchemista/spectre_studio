defmodule SpectreStudioWeb.LabLiveTest do
  use SpectreStudioWeb.ConnCase, async: false

  alias SpectreStudio.Lab.Library

  @fixture Path.expand("../../../fixtures/ledger-bundle-v1.json.base64", __DIR__)

  setup do
    on_exit(fn -> Enum.each(Library.list(), &Library.drop(&1.id)) end)
    :ok
  end

  defp bundle do
    @fixture |> File.read!() |> String.replace(~r/\s+/, "") |> Base.decode64!()
  end

  defp upload(live, contents, name) do
    input =
      file_input(live, "#bundle-upload", :bundle, [
        %{name: name, content: contents, type: "application/json"}
      ])

    render_upload(input, name)
    render_submit(element(live, "#bundle-upload"))
  end

  describe "the library" do
    test "states the trust boundary before anything is loaded", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/lab")

      assert html =~ "trusted"
      assert html =~ "not deterministic replay"
      assert html =~ "nothing loaded yet"
    end

    test "verification runs asynchronously and lands on the bundle", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/lab")

      html = upload(live, bundle(), "account.json")

      # The chain is walked off the LiveView, so the page reports the work in
      # flight instead of blocking on it.
      assert html =~ "verifying the checkpoint chain"

      assert {path, _flash} = assert_redirect(live, 5_000)
      assert path =~ "/lab/"

      {:ok, _show, html} = live(conn, path)
      assert html =~ "account.json"
      assert html =~ "persisted revisions"
    end

    test "a file that is not a bundle fails without leaving the page", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/lab")

      upload(live, "not a bundle", "junk.json")

      html = render_async(live)
      assert html =~ "nothing loaded yet"
      refute html =~ "persisted revisions"
    end
  end

  describe "one bundle" do
    setup do
      {:ok, loaded} = Library.load("account.json", bundle())
      {:ok, bundle: loaded}
    end

    test "the timeline is streamed and states its gaps", %{conn: conn, bundle: loaded} do
      {:ok, _live, html} = live(conn, ~p"/lab/#{loaded.id}")

      assert html =~ ~s(id="timeline")
      assert html =~ ~s(phx-update="stream")
      assert html =~ "rev 0"
      assert html =~ "persisted revisions"
      # Turn-level detail is not derivable from a bundle, and the panel says so.
      assert html =~ "boundary receipts"
    end

    test "a bundle that is gone returns to the library", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/lab"}}} = live(conn, ~p"/lab/missing")
    end
  end

  describe "comparing two bundles" do
    setup do
      {:ok, left} = Library.load("left.json", bundle())
      {:ok, right} = Library.load("right.json", bundle())
      {:ok, left: left, right: right}
    end

    test "the diff is computed asynchronously", %{conn: conn, left: left, right: right} do
      {:ok, live, html} = live(conn, ~p"/lab/#{left.id}/diff/#{right.id}")

      assert html =~ "walking both checkpoint chains"

      html = render_async(live)
      assert html =~ "identical"
      assert html =~ "first divergence"
      assert html =~ "none"
    end

    test "the bundle page links to the comparison", %{conn: conn, left: left, right: right} do
      {:ok, _live, html} = live(conn, ~p"/lab/#{left.id}")

      assert html =~ "compare with"
      assert html =~ "/lab/#{left.id}/diff/#{right.id}"
    end
  end
end
