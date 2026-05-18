defmodule Reed.Basic.Link do
  @derive Jason.Encoder
  defstruct href: nil, rel: nil, type: nil

  @type t :: %__MODULE__{
          href: String.t(),
          rel: nil | String.t(),
          type: nil | String.t()
        }

  def to_link(data) when is_map(data) do
    data = AtomicMap.convert(data, safe: true)
    struct(__MODULE__, data)
  end

  def url(links, rels) do
    found_link =
      rels
      |> List.wrap()
      |> Enum.reduce_while(nil, fn rel, acc ->
        cond do
          rel == "any" -> {:halt, List.first(links)}
          found = Enum.find(links, fn link -> link.rel == rel end) -> {:halt, found}
          true -> {:cont, acc}
        end
      end)

    if found_link do
      found_link.href
    else
      nil
    end
  end
end

defimpl String.Chars, for: Reed.Basic.Link do
  def to_string(link), do: link.href
end
