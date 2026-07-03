defmodule Reed.MicroformatsTest do
  use ExUnit.Case

  describe "microformats" do
    test "parses rss in html" do
      content = read_feed!("blog-jim-nielsen-com-feed.html")

      assert %{"items" => items, "rel-urls" => rel_urls} =
               Microformats2.parse(content, "https://blog.jim-nielsen.com/feed.html")

      assert h_feed = Enum.find(items, fn item -> "h-feed" in item["type"] end)
      assert sorted_keys(h_feed) == ["children", "properties", "type"]
      assert feed_props = h_feed["properties"]
      assert sorted_keys(feed_props) == ["name"]

      assert {h_entries, []} =
               Enum.split_with(h_feed["children"], fn item -> "h-entry" in item["type"] end)

      assert h_entry = List.first(h_entries)
      assert sorted_keys(h_entry) == ["id", "properties", "type"]
      assert entry_props = h_entry["properties"]
      assert sorted_keys(entry_props) == ["content", "published", "url"]
      assert [content] = Map.get(entry_props, "content")
      assert sorted_keys(content) == ["html", "value"]

      refute h_entry["children"]

      assert {url, link} =
               Enum.find(rel_urls, fn {_url, link} -> link["type"] == "application/mf2+html" end)

      assert url == "https://blog.jim-nielsen.com/feed.html"

      assert %{
               "rels" => ["alternate"],
               "title" => "RSS: HTML Feed",
               "type" => "application/mf2+html"
             } = link
    end
  end

  defp sorted_keys(data), do: Map.keys(data) |> Enum.sort()

  defp read_feed!(name) do
    Path.join(__DIR__, "../../feeden/priv/examples/#{name}")
    |> File.read!()
  end
end
