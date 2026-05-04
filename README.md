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

### Migration Options

#### Versioned Migrations

TowerDB supports incremental migrations. When no version is specified:
- `up/0` runs all migrations up to the latest version
- `down/0` rolls back all migrations to the initial version

You can also specify a target version:

```elixir
def up, do: TowerDB.Migration.up(version: 1)
def down, do: TowerDB.Migration.down(version: 1)
```

When upgrading, migrations run incrementally from the last applied version up to the target version. When rolling back, migrations undo from the current version down to the specified version.

## License

See [LICENSE](LICENSE).

