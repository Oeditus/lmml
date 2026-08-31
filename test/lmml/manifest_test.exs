defmodule Lmml.ManifestTest do
  use ExUnit.Case, async: true

  alias Lmml.Bundle
  alias Lmml.Manifest

  describe "load/1 when no manifest.json embed is mentioned" do
    test "returns {:ok, nil}, not an error" do
      {:ok, bundle} = Bundle.new_text("foo", "Just a plain narrative, no manifest at all.")
      assert {:ok, nil} = Manifest.load(bundle)
    end
  end

  describe "load/1 with an inline manifest.json embed" do
    test "decodes it regardless of bundle kind" do
      {:ok, bundle} =
        Bundle.new_text("foo", "@@@manifest.json\n{\"schema\": 1, \"assets\": [\"a.png\"]}\n@@@")

      assert {:ok, %Manifest{} = manifest} = Manifest.load(bundle)
      assert Manifest.get(manifest, "schema") == 1
      assert Manifest.get(manifest, "assets") == ["a.png"]
      assert Manifest.get(manifest, "missing") == nil
    end
  end

  describe "load/1 with an external manifest.json reference" do
    test "resolves it against the zip's own entries" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "See @manifest.json for details.", %{
          "manifest.json" => ~s({"schema": 2})
        })

      assert {:ok, %Manifest{} = manifest} = Manifest.load(bundle)
      assert Manifest.get(manifest, "schema") == 2
    end

    test "errors cleanly when the reference is unresolvable in a bare text bundle" do
      {:ok, bundle} = Bundle.new_text("foo", "See @manifest.json please.")

      assert {:error, {:unresolvable_reference, "manifest.json"}} = Manifest.load(bundle)
    end

    test "errors cleanly when the zip entry it points to is missing" do
      {:ok, bundle} = Bundle.new_zip("convo", "See @manifest.json please.", %{})

      assert {:error, {:missing_entry, "manifest.json"}} = Manifest.load(bundle)
    end
  end

  describe "load/1 with malformed manifest content" do
    test "errors when the content is not valid JSON" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@manifest.json\nnot json at all {{{\n@@@")

      assert {:error, {:invalid_manifest, _reason}} = Manifest.load(bundle)
    end

    test "errors when the content decodes to something other than a JSON object" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@manifest.json\n[1, 2, 3]\n@@@")

      assert {:error, {:invalid_manifest, {:not_an_object, [1, 2, 3]}}} = Manifest.load(bundle)
    end
  end

  describe "load!/1" do
    test "returns the manifest struct directly on success" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@manifest.json\n{\"schema\": 1}\n@@@")
      assert %Manifest{} = Manifest.load!(bundle)
    end

    test "returns nil directly when there is no manifest, without raising" do
      {:ok, bundle} = Bundle.new_text("foo", "no manifest here")
      assert Manifest.load!(bundle) == nil
    end

    test "raises when the manifest is mentioned but unresolvable" do
      {:ok, bundle} = Bundle.new_text("foo", "@manifest.json")

      assert_raise RuntimeError, ~r/Failed to load lmml manifest/, fn ->
        Manifest.load!(bundle)
      end
    end
  end
end
