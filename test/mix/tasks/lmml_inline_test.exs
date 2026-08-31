defmodule Mix.Tasks.Lmml.InlineTest do
  use ExUnit.Case

  alias Mix.Tasks.Lmml.Inline

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    dir =
      Path.join(System.tmp_dir!(), "lmml_inline_task_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "inlines a .lmmlz archive into a bare .lmml file by default", %{dir: dir} do
    source = Path.join(dir, "convo.lmmlz")
    {:ok, bundle} = Lmml.Bundle.new_zip("convo", "See @notes.txt here.", %{"notes.txt" => "hi"})
    Lmml.Bundle.write!(bundle, source)

    Inline.run([source])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "Inlined"

    dest = Path.join(dir, "convo.lmml")
    assert File.exists?(dest)
    {:ok, inlined} = Lmml.Bundle.open(dest)
    assert Lmml.Bundle.text?(inlined)
    assert {:ok, "hi"} = Lmml.Bundle.embed(inlined, "notes.txt")
  end

  test "fails when an external reference cannot be resolved", %{dir: dir} do
    source = Path.join(dir, "broken.lmmlz")
    {:ok, bundle} = Lmml.Bundle.new_zip("broken", "@missing.png", %{})
    Lmml.Bundle.write!(bundle, source)

    assert_raise Mix.Error, ~r/Failed to inline/, fn ->
      Inline.run([source])
    end
  end

  test "requires one or two arguments" do
    assert_raise Mix.Error, ~r/Usage: mix lmml.inline/, fn -> Inline.run([]) end
  end
end
