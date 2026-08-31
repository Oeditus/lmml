defmodule Mix.Tasks.Lmml.PackTest do
  use ExUnit.Case

  alias Mix.Tasks.Lmml.Pack

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    dir =
      Path.join(System.tmp_dir!(), "lmml_pack_task_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "packs a .lmml file into a .lmmlz archive by default", %{dir: dir} do
    source = Path.join(dir, "convo.lmml")
    File.write!(source, "@@@settings.yaml\nkey: value\n@@@")

    Pack.run([source])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "Packed"

    dest = Path.join(dir, "convo.lmmlz")
    assert File.exists?(dest)
    {:ok, bundle} = Lmml.Bundle.open(dest)
    assert Lmml.Bundle.zip?(bundle)
    assert {:ok, "key: value\n"} = Lmml.Bundle.embed(bundle, "settings.yaml")
  end

  test "writes to an explicit destination when given", %{dir: dir} do
    source = Path.join(dir, "convo.lmml")
    File.write!(source, "plain text")
    dest = Path.join(dir, "custom.lmmlz")

    Pack.run([source, dest])

    assert File.exists?(dest)
  end

  test "requires one or two arguments" do
    assert_raise Mix.Error, ~r/Usage: mix lmml.pack/, fn -> Pack.run([]) end
    assert_raise Mix.Error, ~r/Usage: mix lmml.pack/, fn -> Pack.run(["a", "b", "c"]) end
  end
end
