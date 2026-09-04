# TowerDB

A [Tower](https://github.com/mimiquate/tower) reporter that stores errors and exceptions in a PostgreSQL database using Ecto.

> [!WARNING]
> **Not production ready.** TowerDB is under active development and its API may still change. We use it in several applications at [Mimiquate](https://mimiquate.com), but it hasn't yet reached the bar we'd consider production ready. Use it at your own risk.
>
> Features we're waiting on before calling it production ready:
>
> - Pruner
> - Enable / Disable reporter via config var and via remote shell
> - Performance test

## Installation

Add `tower_db` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tower_db, "~> 0.7.0"}
  ]
end
```

Then fetch the dependencies:

```bash
mix deps.get
```

## Setup

Add TowerDB to your Tower reporters:

```elixir
# config/config.exs
config :tower, reporters: [TowerDB]
```

Configure the Ecto repo that TowerDB will use to store events:

```elixir
config :tower_db, repo: MyApp.Repo
```

TowerDB requires database tables to store error events. Generate an Ecto migration:

```bash
mix ecto.gen.migration add_tower_db
```

If you want to use a repo different from MyApp.Repo as its primary repo, specify it with the `-r` flag:

```bash
mix ecto.gen.migration add_tower_db -r MyApp.SecondaryRepo
```

Then add the following content to the generated migration file:

```elixir
defmodule MyApp.Repo.Migrations.AddTowerDB do
  use Ecto.Migration

  def up, do: TowerDB.Migration.up(from: 0, to: 7)
  def down, do: TowerDB.Migration.down(from: 7, to: 0)
end
```

Run the migration:

```bash
mix ecto.migrate
```

## License

See [LICENSE](LICENSE).

