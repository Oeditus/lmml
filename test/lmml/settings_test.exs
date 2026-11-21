defmodule Lmml.SettingsTest do
  use ExUnit.Case, async: true

  alias Lmml.Bundle
  alias Lmml.Settings

  describe "load/2 when no settings embed is mentioned" do
    test "returns {:ok, nil}, not an error" do
      {:ok, bundle} = Bundle.new_text("foo", "Just a plain narrative, no settings at all.")
      assert {:ok, nil} = Settings.load(bundle)
    end
  end

  describe "load/2 with a default settings.yaml inline embed" do
    test "decodes a flat key: value mapping with typed scalars" do
      {:ok, bundle} =
        Bundle.new_text(
          "foo",
          "@@@settings.yaml\nmodel: gpt-5\ntemperature: 0.2\nenabled: true\nnote: hello world\n@@@"
        )

      assert {:ok, %Settings{} = settings} = Settings.load(bundle)
      assert Settings.get(settings, "model") == "gpt-5"
      assert Settings.get(settings, "temperature") == 0.2
      assert Settings.get(settings, "enabled") == true
      assert Settings.get(settings, "note") == "hello world"
    end

    test "decodes an indented-nested child map" do
      {:ok, bundle} =
        Bundle.new_text(
          "foo",
          "@@@settings.yaml\nserver:\n  host: localhost\n  port: 8080\nname: x\n@@@"
        )

      assert {:ok, %Settings{} = settings} = Settings.load(bundle)
      assert Settings.get(settings, "server") == %{"host" => "localhost", "port" => 8080}
      assert Settings.get(settings, "name") == "x"
    end

    test "ignores blank lines and full-line comments" do
      {:ok, bundle} =
        Bundle.new_text(
          "foo",
          "@@@settings.yaml\n# header comment\n\nmodel: gpt-5 # trailing comment\n@@@"
        )

      assert {:ok, %Settings{} = settings} = Settings.load(bundle)
      assert Settings.get(settings, "model") == "gpt-5"
    end
  end

  describe "load/2 with a settings.json embed" do
    test "decodes it via the JSON path when the name is passed explicitly" do
      {:ok, bundle} =
        Bundle.new_text("foo", "@@@settings.json\n{\"model\": \"gpt-5\", \"temp\": 0.2}\n@@@")

      assert {:ok, %Settings{} = settings} = Settings.load(bundle, "settings.json")
      assert Settings.get(settings, "model") == "gpt-5"
      assert Settings.get(settings, "temp") == 0.2
    end
  end

  describe "load/2 with an external settings reference" do
    test "resolves it against the zip's own entries" do
      {:ok, bundle} =
        Bundle.new_zip("convo", "See @settings.yaml for config.", %{
          "settings.yaml" => "model: gpt-5\n"
        })

      assert {:ok, %Settings{} = settings} = Settings.load(bundle)
      assert Settings.get(settings, "model") == "gpt-5"
    end

    test "errors cleanly when the reference is unresolvable in a bare text bundle" do
      {:ok, bundle} = Bundle.new_text("foo", "See @settings.yaml please.", validate: false)
      assert {:error, [{:missing_reference, "settings.yaml"}]} = Settings.load(bundle)
    end
  end

  describe "load/2 with malformed or unsupported settings content" do
    test "errors when a settings.yaml has an unsupported construct (a list item)" do
      {:ok, bundle} =
        Bundle.new_text("foo", "@@@settings.yaml\ntools:\n  - read_files\n@@@", validate: false)

      assert {:error, [{:invalid_settings, {"settings.yaml", {:unsupported_yaml, _, _}}}]} =
               Settings.load(bundle)
    end

    test "errors when a settings.yaml has duplicate keys, empty key, tab indent, or scalar+child" do
      {:ok, dup} =
        Bundle.new_text("foo", "@@@settings.yaml\na: 1\na: 2\n@@@", validate: false)

      assert {:error, [{:invalid_settings, {"settings.yaml", {:unsupported_yaml, _, _}}}]} =
               Settings.load(dup)

      {:ok, empty_key} =
        Bundle.new_text("foo", "@@@settings.yaml\n: value\n@@@", validate: false)

      assert {:error, [{:invalid_settings, {"settings.yaml", {:unsupported_yaml, _, _}}}]} =
               Settings.load(empty_key)

      {:ok, tab} =
        Bundle.new_text("foo", "@@@settings.yaml\nserver:\n\thost: a\n@@@", validate: false)

      assert {:error, [{:invalid_settings, {"settings.yaml", {:unsupported_yaml, _, _}}}]} =
               Settings.load(tab)

      {:ok, both} =
        Bundle.new_text("foo", "@@@settings.yaml\nserver: foo\n  host: a\n@@@", validate: false)

      assert {:error, [{:invalid_settings, {"settings.yaml", {:unsupported_yaml, _, _}}}]} =
               Settings.load(both)
    end

    test "handles single-character quote values without crashing" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@settings.yaml\nquote: \"\n@@@")
      assert {:ok, settings} = Settings.load(bundle)
      assert Settings.get(settings, "quote") == "\""
    end

    test "errors when a settings.json is not valid JSON" do
      {:ok, bundle} =
        Bundle.new_text("foo", "@@@settings.json\nnot json {{{\n@@@", validate: false)

      assert {:error, [{:invalid_settings, {"settings.json", _reason}}]} =
               Settings.load(bundle, "settings.json")
    end

    test "errors on an unrecognized settings extension" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@settings.toml\nkey = 1\n@@@")

      assert {:error, {:invalid_settings, {:unsupported_extension, "settings.toml"}}} =
               Settings.load(bundle, "settings.toml")
    end
  end

  describe "get/2 and fetch/2" do
    test "get returns nil for a missing key; fetch distinguishes missing from explicit null" do
      {:ok, bundle} =
        Bundle.new_text("foo", "@@@settings.yaml\nmodel: gpt-5\nnote: null\n@@@")

      {:ok, settings} = Settings.load(bundle)

      assert Settings.get(settings, "model") == "gpt-5"
      assert Settings.get(settings, "missing") == nil
      assert Settings.fetch(settings, "model") == {:ok, "gpt-5"}
      assert Settings.fetch(settings, "note") == {:ok, nil}
      assert Settings.fetch(settings, "missing") == :error
    end
  end

  describe "load!/2" do
    test "returns the settings struct directly on success" do
      {:ok, bundle} = Bundle.new_text("foo", "@@@settings.yaml\nmodel: gpt-5\n@@@")
      assert %Settings{} = Settings.load!(bundle)
    end

    test "returns nil directly when there is no settings embed" do
      {:ok, bundle} = Bundle.new_text("foo", "no settings here")
      assert Settings.load!(bundle) == nil
    end

    test "raises when the settings embed is mentioned but unresolvable" do
      {:ok, bundle} = Bundle.new_text("foo", "@settings.yaml", validate: false)

      assert_raise RuntimeError, ~r/Failed to load lmml settings/, fn ->
        Settings.load!(bundle)
      end
    end
  end
end
