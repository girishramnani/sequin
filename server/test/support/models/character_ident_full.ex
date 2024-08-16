defmodule Sequin.Test.Support.Models.CharacterIdentFull do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  schema "characters_ident_full" do
    field :name, :string
    field :house, :string
    field :planet, :string
    field :is_active, :boolean
    field :tags, {:array, :string}
  end

  def where_id(query \\ base_query(), id) do
    from(cf in query, where: cf.id == ^id)
  end

  defp base_query(query \\ __MODULE__) do
    from(cf in query, as: :character_ident_full)
  end
end
