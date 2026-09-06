defmodule Mix.Tasks.Lmml.RenderTest do
  use ExUnit.Case

  alias Mix.Tasks.Lmml.Render

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    dir =
      Path.join(System.tmp_dir!(), "lmml_render_task_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "renders content parts info by default", %{dir: dir} do
    source = Path.join(dir, "convo.lmml")
    File.write!(source, "@@@config.yaml\nkey: val\n@@@")

    Render.run([source])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "Rendered 2 content part(s)"
  end

  test "renders JSON when --json flag is passed", %{dir: dir} do
    source = Path.join(dir, "convo.lmml")
    File.write!(source, "Just text narrative")

    Render.run([source, "--json"])

    assert_received {:mix_shell, :info, [json_str]}
    assert json_str =~ ~s("type":"text")
  end

  test "requires single source argument" do
    assert_raise Mix.Error, ~r/Usage: mix lmml.render/, fn -> Render.run([]) end
  end
end
