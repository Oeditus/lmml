defmodule Lmml.Narrative.SegmentTest do
  use ExUnit.Case, async: true

  alias Lmml.Bundle
  alias Lmml.Narrative.Resolver
  alias Lmml.Narrative.Segment

  describe "roles/0 and message_roles/0" do
    test "roles list includes :context and message roles" do
      assert Segment.roles() == [:context, :user, :assistant, :system, :tool]
      assert Segment.message_roles() == [:user, :assistant, :system, :tool]
    end
  end

  describe "segment/2" do
    test "returns a single :context turn when no delimiters are present" do
      {:ok, bundle} = Bundle.new_text("foo", "Just a plain conversation with no turn markers.")
      {:ok, resolved} = Resolver.resolve(bundle)

      assert [turn] = Segment.segment(resolved)
      assert turn.role == :context
      assert turn.narrative == "Just a plain conversation with no turn markers."
      assert turn.embeds == []
    end

    test "splits a narrative by Markdown headings" do
      doc = """
      Preamble context before turn 1.

      ## Turn 1 -- user
      Hello assistant!

      ### assistant
      Hello user, how can I help?
      """

      {:ok, bundle} = Bundle.new_text("convo", doc)
      {:ok, resolved} = Resolver.resolve(bundle)

      turns = Segment.segment(resolved)
      assert length(turns) == 3

      assert Enum.map(turns, & &1.role) == [:context, :user, :assistant]
      assert Enum.at(turns, 0).narrative =~ "Preamble context before turn 1."
      assert Enum.at(turns, 1).narrative =~ "Hello assistant!"
      assert Enum.at(turns, 2).narrative =~ "Hello user, how can I help?"
    end

    test "splits a narrative by HTML comments" do
      doc = """
      <!-- user -->
      What is the weather?

      <!-- assistant -->
      It is sunny.
      """

      {:ok, bundle} = Bundle.new_text("convo", doc)
      {:ok, resolved} = Resolver.resolve(bundle)

      turns = Segment.segment(resolved)
      assert Enum.map(turns, & &1.role) == [:user, :assistant]
      assert Enum.at(turns, 0).narrative =~ "What is the weather?"
      assert Enum.at(turns, 1).narrative =~ "It is sunny."
    end

    test "assigns embeds to the turn in which they appear" do
      doc = """
      ## Turn 1 -- user
      Here is an inline doc:
      @@@doc.txt
      hello from user
      @@@

      ## Turn 2 -- assistant
      And here is a response @img.png.
      """

      {:ok, bundle} =
        Bundle.new_zip("convo", doc, %{"img.png" => "image_bytes"})

      {:ok, resolved} = Resolver.resolve(bundle)
      turns = Segment.segment(resolved)

      assert [user_turn, assistant_turn] = turns
      assert user_turn.role == :user
      assert [user_embed] = user_turn.embeds
      assert user_embed.embed.name == "doc.txt"

      assert assistant_turn.role == :assistant
      assert [asst_embed] = assistant_turn.embeds
      assert asst_embed.embed.name == "img.png"
    end
  end

  describe "render_turns/2" do
    test "renders each turn into a API-compatible message object" do
      doc = """
      ## Turn 1 -- user
      Look at @photo.png.

      ## Turn 2 -- assistant
      I see the photo.
      """

      {:ok, bundle} = Bundle.new_zip("convo", doc, %{"photo.png" => "png_bytes"})
      {:ok, resolved} = Resolver.resolve(bundle)

      rendered = Segment.render_turns(resolved)

      assert [
               %{role: :user, content: [%{"type" => "text"}, %{"type" => "image_url"}]},
               %{role: :assistant, content: [%{"type" => "text"}]}
             ] = rendered
    end

    test "forwards options such as :max_embed_bytes to per-turn rendering" do
      doc = """
      ## Turn 1 -- user
      @@@big.txt
      #{String.duplicate("x", 100)}
      @@@
      """

      {:ok, bundle} = Bundle.new_text("convo", doc)
      {:ok, resolved} = Resolver.resolve(bundle)

      rendered = Segment.render_turns(resolved, max_embed_bytes: 10)

      assert [%{role: :user, content: [%{"type" => "text"}]}] = rendered
    end
  end
end
