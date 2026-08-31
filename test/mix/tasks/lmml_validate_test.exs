defmodule Mix.Tasks.Lmml.ValidateTest do
  use ExUnit.Case

  alias Mix.Tasks.Lmml.Validate

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    dir =
      Path.join(
        System.tmp_dir!(),
        "lmml_validate_task_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "reports OK for a well-formed bundle", %{dir: dir} do
    path = Path.join(dir, "convo.lmml")
    File.write!(path, "@@@a.txt\nhello\n@@@")

    Validate.run([path])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "OK"
  end

  test "raises and reports every issue for an invalid bundle", %{dir: dir} do
    path = Path.join(dir, "convo.lmmlz")
    {:ok, bundle} = Lmml.Bundle.new_zip("convo", "@missing.png", %{"orphan.txt" => "x"})
    Lmml.Bundle.write!(bundle, path)

    assert_raise Mix.Error, ~r/2 issue\(s\) found/, fn ->
      Validate.run([path])
    end

    assert_received {:mix_shell, :error, [msg1]}
    assert_received {:mix_shell, :error, [msg2]}
    assert Enum.any?([msg1, msg2], &(&1 =~ "missing reference"))
    assert Enum.any?([msg1, msg2], &(&1 =~ "orphaned zip entry"))
  end

  test "requires exactly one argument" do
    assert_raise Mix.Error, ~r/Usage: mix lmml.validate/, fn -> Validate.run([]) end
  end
end
