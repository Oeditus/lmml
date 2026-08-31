defmodule Mix.Tasks.Lmml.NewTest do
  use ExUnit.Case

  alias Mix.Tasks.Lmml.New

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    dir = Path.join(System.tmp_dir!(), "lmml_new_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "creates a new .lmml file, appending the extension when missing", %{dir: dir} do
    path = Path.join(dir, "notes")

    New.run([path])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "Created"
    assert File.exists?(path <> ".lmml")
    assert File.read!(path <> ".lmml") =~ "notes"
  end

  test "does not duplicate an already-present .lmml extension", %{dir: dir} do
    path = Path.join(dir, "notes.lmml")
    New.run([path])
    assert File.exists?(path)
    refute File.exists?(path <> ".lmml")
  end

  test "creates missing parent directories", %{dir: dir} do
    path = Path.join([dir, "nested", "deep", "notes"])
    New.run([path])
    assert File.exists?(path <> ".lmml")
  end

  test "refuses to overwrite an existing file", %{dir: dir} do
    path = Path.join(dir, "notes.lmml")
    File.write!(path, "original")

    assert_raise Mix.Error, ~r/Refusing to overwrite/, fn ->
      New.run([path])
    end

    assert File.read!(path) == "original"
  end

  test "requires exactly one argument" do
    assert_raise Mix.Error, ~r/Usage: mix lmml.new PATH/, fn ->
      New.run([])
    end
  end
end
