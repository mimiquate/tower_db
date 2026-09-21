# TowerDB

A [Tower](https://github.com/mimiquate/tower) reporter that stores errors and exceptions in a PostgreSQL database using Ecto.

> [!WARNING]
> **Not production ready.** TowerDB is under active development and its API may still change. We use it in several applications at [Mimiquate](https://mimiquate.com), but it hasn't yet reached the bar we'd consider production ready. Use it at your own risk.
>
> Features we're waiting on before calling it production ready:
>
> - Performance test

## Installation

Add `tower_db` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tower_db, "~> 0.9.0"}
  ]
end
```

Then fetch the dependencies:

```bash
mix deps.get
```

## Setup

Add `TowerDB` to your Tower reporters:

```elixir
# config/config.exs

config(
  :tower,
  :reporters,
  [
    # along any other possible reporters
    TowerDB
  ]
)
```

And configure `:tower_db`.


```elixir
# config/runtime.exs

if config_env() == :prod do
  config :tower_db,
    enabled: true,
    repo: MyApp.Repo
end
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

  def up, do: TowerDB.Migration.up(from: 0, to: 8)
  def down, do: TowerDB.Migration.down(from: 8, to: 0)
end
```

Run the migration:

```bash
mix ecto.migrate
```

## Reporting

That's it.
There's no extra source code needed to get reports in your database.

Tower will automatically report any errors (exceptions, throws or abnormal exits) occurring in your application.
That includes errors in any plug call (including Phoenix), Oban jobs, async task or any other Elixir process.


You can also enable or disable the reporter at runtime:

```elixir
TowerDB.disable()
TowerDB.enable()
```

## Pruner

TowerDB can automatically delete old or excess events so storage stays bounded. It's enabled by default with the settings below; configure `:pruner` under `:tower_db` to change that:

```elixir
# config/config.exs

# enabled with defaults (same as not setting :pruner at all)
config :tower_db, pruner: []

# enabled, overriding only the settings you name (the rest keep their defaults)
config :tower_db, pruner: [max_age: {30, :days}]

# disabled entirely
config :tower_db, pruner: false
```

Available settings, all optional:

| key                   | meaning                                   | default            |
| --------------------- | ------------------------------------------ | ------------------- |
| `max_age`             | how long an event is kept before deletion  | `{90, :days}`        |
| `max_size`            | total events kept across all issues        | `100_000`            |
| `max_size_per_issue`  | events kept per issue                      | `1_000`              |
| `interval`            | time between prune runs                    | `{30, :seconds}`     |
| `batch_size`          | max rows deleted per batch                 | `1_000`              |

`max_age` and `interval` are `{amount, unit}` tuples, with `unit` one of `:seconds`, `:minutes`, `:hours`, or `:days`.

`max_age`, `max_size` and `max_size_per_issue` accept `:infinity` to disable that specific check.

Each prune run deletes, in batches of `batch_size`:

1. events older than `max_age` (unless `:infinity`);
2. for each issue, the oldest events beyond `max_size_per_issue` (unless `:infinity`);
3. the oldest events beyond `max_size` overall (unless `:infinity`).

## License

See [LICENSE](LICENSE).

