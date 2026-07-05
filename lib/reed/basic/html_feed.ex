defmodule Reed.Basic.HtmlFeed do
  @moduledoc false

  @doc """
  Decodes an HTML microformats2 feed and passes it to the transformers.
  """
  def parse(html_body, url, user_state) when is_binary(html_body) do
    case Microformats2.parse(html_body, url) do
      :error ->
        {:error, "failed to parse microformats"}

      %{"items" => items} ->
        case Enum.filter(items, fn %{"type" => types} -> "h-feed" in types end) do
          [feed] ->
            feed
            |> parse_h_feed()
            |> Reed.Basic.JsonFeed.parse_map(user_state)

          [] ->
            {:error, "no h-feeds in document"}

          _feeds ->
            {:error, "more than one h-feed in document"}
        end
    end
  end

  defp parse_h_feed(%{"properties" => props} = item) do
    items =
      item
      |> Map.get("children", [])
      |> Enum.map(&parse_entry/1)
      |> Enum.reject(&is_nil/1)

    %{
      "title" => get_prop(props, "name") || "Untitled",
      "items" => items
    }
  end

  defp parse_entry(%{"type" => types, "properties" => props} = entry) do
    if "h-entry" in types do
      content = get_prop(props, "content", "value")
      content_html = get_prop(props, "content", "html")
      published = get_prop(props, "published")
      url = get_prop(props, "url")

      %{
        "id" => Map.fetch!(entry, "id"),
        "url" => url,
        "content" => content,
        "content_html" => content_html,
        "date_published" => published
      }
    else
      nil
    end
  end

  defp get_prop(props, key) do
    Map.get(props, key) |> List.first()
  end

  defp get_prop(props, key, subkey) do
    case Map.get(props, key) |> List.first() do
      prop when is_map(prop) -> Map.get(prop, subkey)
      _ -> nil
    end
  end
end
