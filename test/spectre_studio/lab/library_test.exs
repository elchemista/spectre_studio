defmodule SpectreStudio.Lab.LibraryTest do
  use ExUnit.Case, async: false

  alias SpectreStudio.Lab.Library
  alias SpectreStudio.Lab.Projection

  @fixture Path.expand("../../fixtures/ledger-bundle-v1.json.base64", __DIR__)

  setup do
    on_exit(fn -> Enum.each(Library.list(), &Library.drop(&1.id)) end)
    :ok
  end

  defp bundle do
    @fixture
    |> File.read!()
    |> String.replace(~r/\s+/, "")
    |> Base.decode64!()
  end

  test "loads and verifies a real Ledger bundle" do
    assert {:ok, loaded} = Library.load("account.json", bundle())

    assert loaded.name == "account.json"
    assert loaded.verification.bundle_version == 1
    assert is_binary(loaded.stream_id)
    assert [loaded.id] == Enum.map(Library.list(), & &1.id)
  end

  test "refuses anything that is not a verified bundle" do
    assert {:error, _reason} = Library.load("junk.json", "not a bundle")
  end

  test "refuses a bundle larger than the configured limit" do
    limit = SpectreStudio.Config.get().max_bundle_bytes
    assert {:error, {:too_large, ^limit}} = Library.load("big.json", :binary.copy("x", limit + 1))
  end

  test "the timeline reports persisted revisions and states its gaps" do
    {:ok, loaded} = Library.load("account.json", bundle())

    timeline = Projection.timeline(loaded.playback)
    revisions = Enum.filter(timeline, &(&1.kind == :revision))

    refute revisions == []
    assert Enum.all?(revisions, &is_binary(&1.checkpoint_digest))

    summary = Projection.completeness_summary(loaded.playback)
    assert summary =~ "persisted revisions"
  end

  test "comparing a bundle with itself finds no divergence" do
    {:ok, left} = Library.load("a.json", bundle())
    {:ok, right} = Library.load("b.json", bundle())

    assert {:ok, diff} = Projection.compare(left.playback, right.playback)
    assert diff.status == :identical
    assert diff.first_divergence == nil
    assert Enum.all?(diff.rows, &(&1.kind == :same))
  end

  test "dropping a bundle forgets it" do
    {:ok, loaded} = Library.load("account.json", bundle())
    assert :ok = Library.drop(loaded.id)
    assert Library.fetch(loaded.id) == :error
  end
end
