defmodule Reed.Handler do
  @moduledoc false
  @behaviour Saxy.Handler

  # Handle both RSS 2.0 and Atom vocabularies
  @feed_names ["rss", "feed", "channel"]
  @item_names ["item", "entry"]

  @client_keys [:feed_info, :current_item, :halted, :private, :flavor]

  def client_state(state), do: Map.take(state, @client_keys)

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:end_document, _data, state) do
    {:ok, state}
  end

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attributes}, state) do
    current_path = [name | state.current_path]

    new_state =
      cond do
        name in @item_names ->
          %{state | current_item: %{}, current_path: current_path}

        not is_nil(state.current_item) ->
          idx = next_item_idx(state.current_item, current_path)
          current_path = [idx | current_path]
          local_path = item_path(current_path)

          current_item =
            if attributes != [] do
              put_in(state.current_item, access(local_path), Map.new(attributes))
            else
              state.current_item
            end

          %{
            state
            | current_path: current_path,
              current_item: current_item
          }

        true ->
          flavor = maybe_flavor(state.flavor, name, attributes)

          current_path =
            if name in @feed_names do
              current_path
            else
              idx = next_feed_idx(state.feed_private, current_path)
              [idx | current_path]
            end

          local_path = feed_path(current_path)

          feed_private =
            if attributes != [] do
              put_in(state.feed_private, access(local_path), Map.new(attributes))
            else
              state.feed_private
            end

          %{
            state
            | current_path: current_path,
              feed_private: feed_private,
              flavor: flavor
          }
      end

    {:ok, new_state}
  end

  @impl Saxy.Handler
  def handle_event(:end_element, name, state) do
    new_state =
      cond do
        not is_nil(state.current_item) and name in @item_names ->
          state
          |> maybe_deflate_feed()
          |> process_transforms()

        not is_nil(state.current_item) ->
          local_path = item_path(state.current_path)
          value = value_at(state.current_item, local_path, state.current_text)

          %{
            state
            | current_item: put_in(state.current_item, access(local_path), value),
              current_text: "",
              current_path: get_parent_path(state.current_path)
          }

        true ->
          local_path = feed_path(state.current_path)
          value = value_at(state.feed_private, local_path, state.current_text)

          # Reset `feed_info` so that next time it is needed it will be re-created by
          # deflating `feed_private` (before `process_transforms/1`, or after the
          # entire parse is complete).
          %{
            state
            | feed_private: put_in(state.feed_private, access(local_path), value),
              feed_info: %{},
              current_text: "",
              current_path: get_parent_path(state.current_path)
          }
      end

    if state.halted, do: {:stop, new_state}, else: {:ok, new_state}
  end

  @impl Saxy.Handler
  def handle_event(:characters, chars, state) do
    {:ok, %{state | current_text: state.current_text <> chars}}
  end

  def get_item_handler!(options) when is_map(options) do
    item_handler = Map.get(options, :transform, [& &1])

    cond do
      is_function(item_handler, 1) ->
        [item_handler]

      is_list(item_handler) && Enum.all?(item_handler, &is_function/1) ->
        item_handler

      true ->
        raise ArgumentError,
              "`:transform` must either be an arity-1 function or a list of arity-1 functions"
    end
  end

  # Look at first chunk, to see if it's json or xml. If neither,
  # assume it's HTML.
  def detect_parser!(chunk) do
    test = String.trim_leading(chunk)

    case test do
      "<?xml" <> _rest -> :xml
      "<rss" <> _rest -> :xml
      "<feed" <> _rest -> :xml
      "{" <> _rest -> :json
      _ -> :html
    end
  end

  def process_transforms(state) do
    state = %{state | current_item: deflate(state.current_item)}

    client_state =
      Enum.reduce_while(state.transform, client_state(state), fn step, acc ->
        case step.(acc) do
          {instruction, _new} = res when instruction in [:halt, :cont] ->
            res

          new_state when is_map(new_state) ->
            {:cont, new_state}

          :halt ->
            {:halt, acc}
        end
      end)

    parent_path = get_parent_path(state.current_path)
    state = Map.merge(state, client_state)

    %{
      state
      | current_item: nil,
        current_text: "",
        current_path: parent_path
    }
  end

  @doc """
  Peforms final steps on collected data.

  1. Deflates the `feed_private` if it hasn't been deflated already.
  2. Reverses the order of collected items so that they appear in the same
    order as in the original source.
  3. If `normalize_rss` option is true, normalizes both `feed_info` and
    `private.items` into a standardized format.
  """
  def finalize(%{normalize_rss: true} = user_state) do
    deflate_and_reorder(user_state) |> Reed.Basic.Transformer.normalize_rss()
  end

  def finalize(user_state), do: deflate_and_reorder(user_state)

  # Private functions

  # Deflates the `feed_private` if it hasn't been deflated already, and
  # Reverses the order of collected items so that they appear in the same order
  # as in the original source.
  defp deflate_and_reorder(user_state) do
    state = maybe_deflate_feed(user_state) |> client_state()
    items = get_in(state, [:private, :items]) || []
    put_in(state, [:private, :items], Enum.reverse(items))
  end

  defp maybe_deflate_feed(%{feed_private: private, feed_info: info} = state)
       when map_size(info) == 0 and map_size(private) != 0 do
    %{state | feed_info: deflate(state.feed_private)}
  end

  defp maybe_deflate_feed(state), do: state

  # Change singleton `%{0 => value}` to `value`, and multiple to a list of
  # values, recursively.
  defp deflate(%{0 => _} = value) do
    case Map.values(value) do
      [subvalue] -> deflate(subvalue)
      multiple -> Enum.map(multiple, &deflate/1)
    end
  end

  defp deflate(value) when is_map(value) do
    Enum.map(value, fn {name, subv} -> {name, deflate(subv)} end) |> Map.new()
  end

  defp deflate(value), do: value

  @keys [
    {:name, "rss", "rss"},
    {:name, "feed", "atom"},
    {:attribute, "xmlns:yt", "youtube"},
    {:attribute, "xmlns:media", "media"},
    {:attribute, "xmlns:itunes", "itunes"},
    {:attribute, "xmlns:podcast", "podcast"}
  ]

  # Detects the various root elements and namespace declarations.
  defp maybe_flavor(nil, name, attributes) do
    att_map = Map.new(attributes)

    flavors =
      Enum.reduce(@keys, [], fn
        {:name, root_name, flavor}, acc ->
          if name == root_name do
            [flavor | acc]
          else
            acc
          end

        {:attribute, xmlns, flavor}, acc ->
          if Map.has_key?(att_map, xmlns) do
            [flavor | acc]
          else
            acc
          end
      end)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.join("+")

    if flavors == "" do
      nil
    else
      flavors
    end
  end

  defp maybe_flavor(flavor, _name, _attributes), do: flavor

  # Handles the case where the element has BOTH attributes and text content,
  # by creating a `_text_` item in the map.
  defp value_at(collection, path, text) do
    case {get_in(collection, path), String.trim(text)} do
      {nil, text} ->
        text

      {value, ""} ->
        value

      {value, text} when is_map(value) ->
        Map.put(value, "_text_", text)

      {value, text} ->
        raise "#{inspect(path)} has non-map value #{inspect(value)} and text #{text}"
    end
  end

  # The path functions below create 0-indexed paths. Since multiple child elements with
  # the same name may be contained in a feed or item element, each child element
  # and attribute in the "inflated" result is parsed as a map with 0-indexed key
  # and the value of the element or attribute, like this:
  #
  # %{"link" => %{
  #  0 => %{
  #    "href" => "https://www.mux.com/?utm_campaign=fireball&utm_source=DF",
  #    "rel" => "alternate",
  #    "type" => "text/html"
  #  },
  #  1 => %{
  #    "href" => "http://df4.us/x95",
  #    "rel" => "shorturl",
  #    "type" => "text/html"
  #  }
  # }}
  #
  # The state maintains the current path as a list of keys (always with a 0-indexed key at
  # the head of the list) all the way down to the root element name, like this:
  # `[0, "link", "item", "channel", "rss"]`.
  #
  # The `current_path` is then truncated and reversed to get the feed- or item-local path
  # that the current value will be located at within the "inflated" `feed_private` or
  # `current_item` map, e.g. `["link", 0]`.
  #
  # Nested elements keep the 0-indexed scheme before being deflated. Exmaple: current path
  # `[0, "media:title", 0, "media:content", "item", "channel", "rss"]`, and its local path
  # `["media:content", 0, "media:title", 0]`, where `media:title` is a child element of
  # `media:content`.
  #
  # These "inflated" map values are deflated recursively to singleton or list values
  # before being presented to the client for transformation. So the "link" value shown
  # above deflates to a list as seen by the client:
  #
  # %{"link" => [
  #  %{
  #    "href" => "https://www.mux.com/?utm_campaign=fireball&utm_source=DF",
  #    "rel" => "alternate",
  #    "type" => "text/html"
  #  },
  #  %{
  #    "href" => "http://df4.us/x95",
  #    "rel" => "shorturl",
  #    "type" => "text/html"
  #  }
  # ]}
  defp next_item_idx(current_item, path) do
    next_idx(current_item, item_path(path))
  end

  defp next_feed_idx(feed_private, path) do
    next_idx(feed_private, feed_path(path))
  end

  defp next_idx(item, local_path) do
    case get_in(item, local_path) do
      %{0 => _} = value when is_map(value) -> map_size(value)
      _ -> 0
    end
  end

  def item_path(path) do
    path
    |> Enum.split_while(&(&1 not in @item_names))
    |> elem(0)
    |> Enum.reverse()
  end

  defp feed_path(path) do
    path |> Enum.reverse()
  end

  defp get_parent_path(path) do
    [idx | rest] = path

    if is_integer(idx) do
      [_ | parent_path] = rest
      parent_path
    else
      rest
    end
  end

  defp access(path) do
    path |> Enum.map(&Access.key(&1, %{}))
  end
end
