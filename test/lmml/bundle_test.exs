defmodule Lmml.BundleTest do
  use ExUnit.Case, async: true

  alias Lmml.Bundle

  setup do
    dir = Path.join(System.tmp_dir!(), "lmml_bundle_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  describe "opening a bare .lmml text file" do
    test "open/1 parses the narrative and exposes no entries", %{dir: dir} do
      path = Path.join(dir, "foo.lmml")
      File.write!(path, "Hello @image.png here.")

      assert {:ok, bundle} = Bundle.open(path)
      assert Bundle.text?(bundle)
      refute Bundle.zip?(bundle)
      assert Bundle.narrative(bundle) == "Hello @image.png here."
      assert Bundle.entries(bundle) == []
      assert [%Lmml.Embed{name: "image.png"}] = Bundle.embeds(bundle)
    end

    test "an external reference is unresolvable in a text-only bundle", %{dir: dir} do
      path = Path.join(dir, "foo.lmml")
      File.write!(path, "Hello @image.png here.")

      {:ok, bundle} = Bundle.open(path)
      assert {:error, {:unresolvable_reference, "image.png"}} = Bundle.embed(bundle, "image.png")
    end

    test "an inline embed resolves regardless of bundle kind", %{dir: dir} do
      path = Path.join(dir, "foo.lmml")
      File.write!(path, "@@@settings.yaml\nkey: value\n@@@")

      {:ok, bundle} = Bundle.open(path)
      assert {:ok, "key: value\n"} = Bundle.embed(bundle, "settings.yaml")
    end
  end

  describe "opening a .lmmlz zip archive" do
    test "the internal narrative entry is named after the archive's own basename minus the trailing z",
         %{dir: dir} do
      path = Path.join(dir, "convo.lmmlz")
      build_zip!(path, "convo.lmml", "See @image.png.", %{"image.png" => "binarydata"})

      assert {:ok, bundle} = Bundle.open(path)
      assert Bundle.zip?(bundle)
      assert Bundle.narrative(bundle) == "See @image.png."
      assert Bundle.entries(bundle) == ["image.png"]
      assert {:ok, "binarydata"} = Bundle.embed(bundle, "image.png")
    end

    test "detection is by content, not extension -- a zip named .lmml still opens as zip", %{
      dir: dir
    } do
      path = Path.join(dir, "weird.lmml")
      build_zip!(path, "weird.lmml", "See @a.png.", %{"a.png" => "data"})

      assert {:ok, bundle} = Bundle.open(path)
      assert Bundle.zip?(bundle)
    end

    test "a missing narrative entry is a clean error, not a crash", %{dir: dir} do
      path = Path.join(dir, "broken.lmmlz")
      build_zip!(path, "not_the_expected_name.lmml", "text", %{})

      assert {:error, {:missing_narrative_entry, "broken.lmml"}} = Bundle.open(path)
    end

    test "a path-traversal entry never actually escapes the bundle, even though open/1 does not error",
         %{dir: dir} do
      path = Path.join(dir, "evil.lmmlz")
      build_zip!(path, "evil.lmml", "text", %{"../../etc/passwd" => "nope"})

      # Empirically, Erlang's own `:zip.unzip/2` does not reject a
      # traversal entry outright -- it logs a warning and silently
      # collapses it to its basename ("../../etc/passwd" -> "passwd")
      # before `Lmml.Bundle` ever sees the entries map. So `open/1`
      # succeeds here, but the dangerous path component is already gone:
      # there is no entry literally named with a `..` segment or an
      # absolute path to reject in the first place. `validate_entry_names/1`
      # remains valuable as defense-in-depth for the in-memory `new_zip/3`
      # construction path (see the test below), which never goes through
      # `:zip` and so never gets this OTP-level sanitization for free.
      assert {:ok, bundle} = Bundle.open(path)
      assert Bundle.entries(bundle) == ["passwd"]
      assert :ok = Bundle.validate_entry_names(Bundle.entries(bundle))
    end
  end

  describe "new_text/2 and new_zip/3 in-memory constructors" do
    test "new_text/2 normalizes the name to end in .lmml" do
      {:ok, bundle} = Bundle.new_text("foo", "hello")
      assert bundle.name == "foo.lmml"
      assert Bundle.text?(bundle)
    end

    test "new_zip/3 builds a resolvable zip-backed bundle with no disk I/O" do
      {:ok, bundle} = Bundle.new_zip("convo", "See @a.png.", %{"a.png" => "bytes"})
      assert bundle.name == "convo.lmml"
      assert {:ok, "bytes"} = Bundle.embed(bundle, "a.png")
    end

    test "new_zip/3 rejects unsafe entry names up front" do
      assert {:error, {:unsafe_entry, "/etc/passwd"}} =
               Bundle.new_zip("convo", "text", %{"/etc/passwd" => "nope"})
    end
  end

  describe "write!/2 round-trips" do
    test "a text bundle writes its narrative back out verbatim", %{dir: dir} do
      {:ok, bundle} = Bundle.new_text("foo", "Hello @a.png.")
      path = Path.join(dir, "foo.lmml")

      assert :ok = Bundle.write!(bundle, path)
      assert File.read!(path) == "Hello @a.png."
    end

    test "a zip bundle round-trips through write! and open, re-deriving the entry name from the target path",
         %{dir: dir} do
      {:ok, bundle} = Bundle.new_zip("original-name", "See @a.png.", %{"a.png" => "bytes"})
      path = Path.join(dir, "renamed.lmmlz")

      :ok = Bundle.write!(bundle, path)
      {:ok, reopened} = Bundle.open(path)

      assert reopened.name == "renamed.lmml"
      assert {:ok, "bytes"} = Bundle.embed(reopened, "a.png")
    end
  end

  describe "validate/1" do
    test "a well-formed zip bundle with matching references and entries has no issues" do
      {:ok, bundle} = Bundle.new_zip("convo", "See @a.png.", %{"a.png" => "bytes"})
      assert :ok = Bundle.validate(bundle)
    end

    test "a well-formed text bundle with only inline embeds has no issues" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@a.txt\nhello\n@@@")
      assert :ok = Bundle.validate(bundle)
    end

    test "flags an external reference with no matching zip entry" do
      {:ok, bundle} = Bundle.new_zip("convo", "See @missing.png.", %{})
      assert {:error, issues} = Bundle.validate(bundle)
      assert {:missing_reference, "missing.png"} in issues
    end

    test "flags every external reference as missing in a bare text bundle, since it has no entries at all" do
      {:ok, bundle} = Bundle.new_text("foo", "See @image.png.")

      assert {:error, issues} = Bundle.validate(bundle)
      assert {:missing_reference, "image.png"} in issues
    end

    test "flags a zip entry that nothing in the narrative references" do
      {:ok, bundle} = Bundle.new_zip("convo", "No references here.", %{"orphan.png" => "bytes"})

      assert {:error, issues} = Bundle.validate(bundle)
      assert {:orphaned_entry, "orphan.png"} in issues
    end

    test "flags an embed name that could not safely become a zip entry name" do
      {:ok, bundle} = Bundle.new_text("foo", "See @../secret.txt please.")

      assert {:error, issues} = Bundle.validate(bundle)
      assert {:malformed_embed_name, "../secret.txt"} in issues
    end

    test "flags two inline embeds that share a name but disagree on content" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@a.txt\nhello\n@@@\n\n@@@a.txt\nworld\n@@@")

      assert {:error, issues} = Bundle.validate(bundle)
      assert {:conflicting_embed, "a.txt"} in issues
    end

    test "does not flag the same inline embed name repeated with identical content" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@a.txt\nhello\n@@@\n\n@@@a.txt\nhello\n@@@")

      assert :ok = Bundle.validate(bundle)
    end

    test "reports every issue at once, not just the first" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "See @missing.png.", %{"orphan.png" => "bytes"})

      assert {:error, issues} = Bundle.validate(bundle)
      assert {:missing_reference, "missing.png"} in issues
      assert {:orphaned_entry, "orphan.png"} in issues
    end
  end

  defp build_zip!(path, narrative_entry_name, narrative_content, other_entries) do
    files =
      [{String.to_charlist(narrative_entry_name), narrative_content}] ++
        Enum.map(other_entries, fn {name, data} -> {String.to_charlist(name), data} end)

    {:ok, _} = :zip.create(String.to_charlist(path), files)
    :ok
  end
end
