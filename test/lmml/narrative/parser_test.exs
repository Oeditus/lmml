defmodule Lmml.Narrative.ParserTest do
  use ExUnit.Case, async: true

  alias Lmml.Narrative.Parser
  alias Md.Parser.Default

  describe "@name.ext references" do
    test "parses to a clean :lmml_ref leaf node with no spurious attributes" do
      {"", state} = Parser.parse("Hello @image.png in the middle.")

      assert state.ast == [
               {:p, nil, ["Hello ", {:lmml_ref, %{name: "image.png"}, []}, " in the middle."]}
             ]
    end

    test "a bare '@' surrounded by punctuation still round-trips sensibly" do
      {"", state} = Parser.parse("cc @bob, thanks!")

      assert [{:p, nil, ["cc ", {:lmml_ref, %{name: name}, []}, _rest]}] = state.ast
      assert name == "bob"
    end
  end

  describe "@@@name.ext ... @@@ inline embeds" do
    test "a bare embed (the settings-only example) parses to a single :lmml_embed node" do
      {"", state} = Parser.parse("@@@settings.yaml\nkey: value\nother: 1\n@@@")

      assert state.ast == [{:lmml_embed, %{name: "settings.yaml"}, ["key: value\nother: 1\n"]}]
    end

    test "an embed used as its own block, surrounded by prose, does not disturb the prose" do
      doc = """
      Here is the config:

      @@@settings.yaml
      key: value
      other: 1
      @@@

      More text follows with @another.png too.
      """

      {"", state} = Parser.parse(doc)

      assert [
               {:p, nil, ["Here is the config:"]},
               {:lmml_embed, %{name: "settings.yaml"}, ["key: value\nother: 1\n"]},
               {:p, nil,
                ["More text follows with ", {:lmml_ref, %{name: "another.png"}, []}, " too."]}
             ] = state.ast
    end
  end

  describe "plain triple-backtick fences remain ordinary markdown" do
    test "a language-tagged fence is untouched by the @@@ embed syntax" do
      {"", state} = Parser.parse("```elixir\ndef foo, do: :ok\n```")

      assert state.ast == [
               {:pre, nil, [{:code, %{class: "elixir lang-elixir"}, ["def foo, do: :ok\n"]}]}
             ]
    end
  end

  describe "lmml is a superset of vanilla Markdown" do
    test "headings, emphasis, and links parse exactly as in standard Md" do
      doc =
        "# Just a bare markdown heading\n\nWith *bold* and _italic_ and a [link](https://example.com)."

      assert Parser.parse(doc) == Default.parse(doc)
    end

    test "a document with zero lmml-specific syntax parses cleanly" do
      doc = "Just a plain paragraph with no special syntax at all."
      {"", state} = Parser.parse(doc)

      assert state.ast == [{:p, nil, [doc]}]
    end

    test "Default's youtube/soundcloud/https magnets are untouched, since they use disjoint prefixes" do
      doc = "See https://example.com for details."
      {"", state} = Parser.parse(doc)

      assert [{:p, nil, ["See ", {:a, %{href: "https://example.com"}, _}, " for details."]}] =
               state.ast
    end
  end

  describe "edge cases: references adjacent to punctuation" do
    test "a reference immediately followed by a closing parenthesis stops before it" do
      {"", state} = Parser.parse("(see @image.png)")

      assert [{:p, nil, ["(see ", {:lmml_ref, %{name: "image.png"}, []}, ")"]}] = state.ast
    end

    test "a reference immediately followed by a bold marker stops before it" do
      {"", state} = Parser.parse("@image.png*")

      # The trailing, unterminated `*` opens (and never closes) a `:b`
      # brace, which contributes no node of its own -- what matters here
      # is that the reference's own name stops cleanly at `image.png`,
      # not swallowing the `*`.
      assert [{:p, nil, [{:lmml_ref, %{name: "image.png"}, []}]}] = state.ast
    end

    test "a reference immediately followed by a period at end of sentence stops before it" do
      {"", state} = Parser.parse("Attached: @report.pdf.")

      assert [{:p, nil, ["Attached: ", {:lmml_ref, %{name: "report.pdf"}, []}, "."]}] = state.ast
    end
  end

  describe "edge cases: nested emphasis around a reference" do
    test "a reference inside emphasized text is captured as a normal child node" do
      {"", state} = Parser.parse("*see @image.png inside*")

      assert [
               {:p, nil, [{:b, nil, ["see ", {:lmml_ref, %{name: "image.png"}, []}, " inside"]}]}
             ] = state.ast
    end
  end

  describe "edge cases: embeds containing blank lines" do
    test "a blank line inside an embed's content is preserved verbatim, not treated as a paragraph break" do
      {"", state} = Parser.parse("@@@notes.txt\nfirst\n\nsecond\n@@@")

      assert state.ast == [{:lmml_embed, %{name: "notes.txt"}, ["first\n\nsecond\n"]}]
    end
  end

  describe "edge cases: multiple embeds in one document" do
    test "two separate embeds each parse to their own :lmml_embed node" do
      doc = "@@@a.yaml\nfirst: 1\n@@@\n\n@@@b.yaml\nsecond: 2\n@@@"
      {"", state} = Parser.parse(doc)

      assert state.ast == [
               {:lmml_embed, %{name: "a.yaml"}, ["first: 1\n"]},
               {:lmml_embed, %{name: "b.yaml"}, ["second: 2\n"]}
             ]
    end
  end
end
