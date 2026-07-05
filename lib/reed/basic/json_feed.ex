defmodule Reed.Basic.JsonFeed do
  @moduledoc false

  @doc """
  Decodes a JSON feed and passes it to the transformers.
  """
  def parse(data, %{flavor: flavor} = user_state) when is_binary(data) and is_binary(flavor) do
    case Jason.decode(data, keys: :strings) do
      {:ok, data} when is_map(data) ->
        if String.contains?(flavor, "json") && is_nil(Map.get(data, "version")) do
          IO.puts("no version for flavor #{flavor}")
          {:error, "missing required version"}
        else
          parse_map(data, user_state)
        end

      {:ok, _data} ->
        {:error, "invalid data"}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Separates the "feed" and "items" elements from the map.

  Creates the `feed_info` and `current_item` elements, and passes the items
  individually to the transformers.
  """
  def parse_map(data, user_state) do
    # Set up :feed_info for transforms
    {items, feed} = Map.pop(data, "items", [])
    user_state = %{user_state | feed_private: %{"feed" => feed}}

    {final_state, _items} =
      Enum.reduce_while(items, {user_state, []}, fn item, {state, acc} ->
        # Set up :current_item and :current_path for transforms
        state = %{state | current_item: item, current_path: ["item", "feed"]}
        client_state = Reed.Handler.process_transforms(state)
        state = Map.merge(state, client_state)

        if state.halted do
          {:halt, {state, acc}}
        else
          {:cont, {state, [item | acc]}}
        end
      end)

    {:ok, Reed.Handler.finalize(final_state)}
  end
end
