defmodule Reed.StreamTest do
  use ExUnit.Case
  # doctest

  import Reed.Transformers

  alias Reed.Basic.{Transformer, Item}

  describe "stream handler parses" do
    test "rss 2.0 feed" do
      # feed_url = "https://blog.jim-nielsen.com/feed.xml"
      stream = stream_feed("blog-jim-nielsen-com-feed.xml")
      assert {:ok, rss} = Reed.stream(stream, transform: collect() |> limit(2) |> pipeline())
      assert "rss" == rss.flavor
      feed = Transformer.to_feed(rss)
      assert feed.title == "Jim Nielsen’s Blog"
      assert length(feed.items) == 2
    end

    test "rss 2.0 feed with source" do
      # feed_url = "https://rss.chat/users/rss.xml"
      stream = stream_feed("rss-chat-users-rss.xml")
      assert {:ok, rss} = Reed.stream(stream, transform: collect() |> limit(2) |> pipeline())
      assert "rss" == rss.flavor
      feed = Transformer.to_feed(rss)
      assert feed.title == "rss.chat: all posts"
      item = List.first(feed.items)
      assert item.data["source"]
      assert item.data["source"]["url"] == "https://rss.chat/users/mistersugar/rss.xml"
      assert item.data["source"]["_text_"] == "Anton Zuiker"
    end

    test "rss 2.0 feed with metadata after items" do
      stream = stream_feed("disordered-example.xml")
      assert {:ok, rss} = Reed.stream(stream, transform: collect() |> limit(2) |> pipeline())
      assert "rss" == rss.flavor
      feed = Transformer.to_feed(rss)
      assert feed.title == "Scripting News"
      assert length(feed.items) == 2
    end

    test "atom feed" do
      # feed_url = "https://daringfireball.net/feeds/main"
      stream = stream_feed("daringfireball-net-feeds-main.xml")
      assert {:ok, rss} = Reed.stream(stream, transform: collect() |> limit(2) |> pipeline())
      assert "atom" == rss.flavor
      feed = Transformer.to_feed(rss)
      assert feed.title == "Daring Fireball"
      assert length(feed.items) == 2
      item = List.first(feed.items)
      assert Item.content_base_url(item) == "https://daringfireball.net/linked/"

      assert Item.url(item) ==
               "https://daringfireball.net/linked/2026/06/07/alberto-romero-on-apples-ai-spending"
    end

    test "json feed" do
      # feed_url = "https://daringfireball.net/feeds/json"
      stream = stream_feed("daringfireball-net-feeds.json")
      assert {:ok, rss} = Reed.stream(stream, transform: collect() |> limit(2) |> pipeline())
      assert "json" == rss.flavor
      feed = Transformer.to_feed(rss)
      assert feed.title == "Daring Fireball"
      assert length(feed.items) == 2
    end

    test "html microformats feed" do
      # feed_url is required for microformats
      feed_url = "https://blog.jim-nielsen.com/feed.html"
      stream = stream_feed("blog-jim-nielsen-com-feed.html")

      assert {:ok, rss} =
               Reed.stream(stream,
                 feed_url: feed_url,
                 transform: collect() |> limit(2) |> pipeline()
               )

      assert "html+mf2" == rss.flavor
      feed = Transformer.to_feed(rss)
      assert feed.title == "Jim Nielsen’s Blog"
      assert length(feed.items) == 2
    end

    test "youtube channel feed" do
      # feed_url = "http://www.youtube.com/feeds/videos.xml?channel_id=UCNffNDI2yhY8kMQXeTop2OA"
      stream = stream_feed("paul-foxton-youtube-com.xml")
      assert {:ok, rss} = Reed.stream(stream, transform: collect() |> limit(2) |> pipeline())
      assert "atom+media+youtube" == rss.flavor
      feed = Transformer.to_feed(rss)
      assert feed.title == "Paul Foxton"
      assert length(feed.items) == 2
    end

    test "itunes podcast feed" do
      # feed_url = "https://feeds.transistor.fm/appleinsider"
      stream = stream_feed("appleinsider.xml")
      assert {:ok, rss} = Reed.stream(stream, transform: collect() |> limit(2) |> pipeline())
      assert "itunes+podcast+rss" == rss.flavor
      feed = Transformer.to_feed(rss)
      assert feed.title == "AppleInsider Podcast"
      assert length(feed.items) == 2
    end

    test "wordpress feed" do
      # feed_url = "https://bipedsmonitor.com/feed/"
      stream = stream_feed("bipedsmonitor-com-feed.xml")
      assert {:ok, rss} = Reed.stream(stream, transform: collect() |> limit(3) |> pipeline())
      assert "media+rss" == rss.flavor
      feed = Transformer.to_feed(rss)
      assert feed.title == "The Bipeds' Monitor"
      assert length(feed.items) == 3
      assert feed.image.url == "https://s0.wp.com/i/buttonw-com.png"
      assert feed.image.type == "image/png"
      assert feed.image.title == "The Bipeds' Monitor"
      assert feed.image.link == "https://bipedsmonitor.com"
      item = Enum.at(feed.items, 2)
      assert item.id == "http://bipedsmonitor.com/?p=819"
      attachment = List.first(item.attachments)
      assert attachment.url == "https://bipedsmonitor.com/wp-content/uploads/2021/02/img_9503.jpg"
      assert attachment.type == "image/jpeg"
    end
  end

  describe "stream handler normalizes" do
    test "rss 2.0 feed" do
      # feed_url = "https://blog.jim-nielsen.com/feed.xml"
      stream = stream_feed("blog-jim-nielsen-com-feed.xml")

      assert {:ok, rss} =
               Reed.stream(stream,
                 transform: collect() |> limit(2) |> pipeline(),
                 normalize_rss: true
               )

      assert "rss" == rss.flavor
      assert Transformer.normalized?(rss)
      links = Map.get(rss.feed_info, "links")
      assert [link_0, link_1] = links
      assert link_0["rel"] == "alternate"
      assert link_1["rel"] == "self"
    end
  end

  defp stream_feed(name) do
    Path.join(__DIR__, "../../feeden/priv/examples/#{name}")
    |> Path.expand()
    |> File.stream!()
  end
end
