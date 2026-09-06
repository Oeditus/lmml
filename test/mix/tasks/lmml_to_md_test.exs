defmodule Mix.Tasks.Lmml.ToMdTest do
  use ExUnit.Case

  alias Mix.Tasks.Lmml.ToMd

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    dir =
      Path.join(System.tmp_dir!(), "lmml_to_md_task_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "exports a .lmml file into a .md file", %{dir: dir} do
    source = Path.join(dir, "convo.lmml")
    File.write!(source, "@@@config.yaml\nkey: val\n@@@")

    ToMd.run([source])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "Exported"

    dest = Path.join(dir, "convo.md")
    assert File.exists?(dest)
    content = File.read!(dest)
    assert content =~ "[Attachment: config.yaml]"
  end

  test "requires one or two arguments" do
    assert_raise Mix.Error, ~r/Usage: mix lmml.to_md/, fn -> ToMd.run([]) end
  end
end
