# TowerDB

A [Tower](https://github.com/mimiquate/tower) reporter that stores errors and exceptions in a PostgreSQL database using Ecto.

## Installation

Add `tower_db` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tower_db, "~> 0.1.0"},
    {:postgrex, ">= 0.0.0"}
  ]
end
```

## Setup
### Manual setup

Register the reporter with Tower.

```elixir
config :tower, reporters: [TowerDB]
```

Configure TowerDB to use your application's Ecto repo:

```elixir
config :tower_db, repo: MyApp.Repo
```


TowerDB requires database tables to store error events. Generate an Ecto migration:

```bash
mix ecto.gen.migration add_tower_db
```

Then call the `up` and `down` functions in your migration:

```elixir
defmodule MyApp.Repo.Migrations.AddTowerDB do
  use Ecto.Migration

  def up, do: TowerDB.Migration.up()
  def down, do: TowerDB.Migration.down()
end
```

Run the migration:

```bash
mix ecto.migrate
```

## License

See [LICENSE](LICENSE).

