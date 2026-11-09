# Walmart pipeline: setup record and CI/CD guide

This document records what was built, why, and what remains, so the pipeline can be
deployed through CI/CD. It contains no secrets. Passwords and tokens live only in
Databricks connections and in the environment at run time.

## 1. Architecture

```
Lakebase Postgres (walmart_db.raw, 6 tables)
  -> Lakeflow Connect ingestion pipeline "ingest_walmart"   (query-based, cursor = updated_timestamp)
  -> walmart.bronze.*                                      (raw landing)
  -> dbt (this repo): silver_t, silver_b, gold             (dbt deps, dbt build)
  -> walmart.walmart_metric_views.*                        (fact_order_items, dims, sales_order_metrics)
  -> Genie / dashboards
```

Orchestration: Lakeflow Job `walmart_pipeline_job` (dev id `660234436577868`), with tasks:

| Task | Type | Depends on | Notes |
|---|---|---|---|
| `Lakebase_ingestion` | pipeline_task (`ingest_walmart`) | none | Connection `walmart_lakebase_child` (dev) |
| `dbt_transformation` | dbt_task, source GIT | `Lakebase_ingestion` | `dbt deps`, `dbt build` |
| `base_view` | sql_task | `dbt_transformation` | see Open items |
| `creating_metric_view` | sql_task | `base_view` | see Open items |
| `walmart_kpi_dashboard` | dashboard_task | `creating_metric_view` | |

Latest successful full pass: run `213144827909973` (ingestion and dbt succeeded).

## 2. Environments

| | Dev | Prod |
|---|---|---|
| Workspace | `https://dbc-a4e7f3b4-dfcf.cloud.databricks.com` | same |
| Catalog | `walmart` | `walmart_prod` (created in UI with Default Storage) |
| Lakebase connection | `walmart_lakebase_child` (ACTIVE) | `walmart_lakebase_prod` (**does not exist yet**) |
| Bundle target | `dev` (mode development) | `prod` (mode production) |
| Bundle root path | `/Workspace/Users/<user>/.bundle/walmart_pipeline/dev` | `/Workspace/Users/vinayshetty7899@gmail.com/walmart_pipeline` |
| Schedule | none in bundle | none in bundle (add paused, see below) |

Warehouse for dbt tasks: `88712a7ffa1cbac4` (Serverless Starter Warehouse, PRO, serverless enabled).

Variables defined in `databricks.yml`: `catalog`, `lakebase_connection`, `warehouse_id`.
Prod overrides `catalog` and `lakebase_connection`.

## 3. Repositories

| Repo | Purpose | State |
|---|---|---|
| `vinayshetty777/Walmart_DBT_DATABRICKS` (GitHub) | dbt project and bundle for the whole pipeline | Pushed. HEAD `c43faf4` |
| `C:\Users\asus\walmart-metric-views` (local git) | Metric-view bundle (`sales_order_metrics`, base views, grain test) | Local only, not pushed. Deployed to `walmart.walmart_metric_views` |
| `C:\Users\asus\Documents\dbt\walmart_project\walmart-dbt-project` | Local working copy of the dbt project | Inside a larger parent git repo. Do not push that parent repo (it contains unrelated files and a `secrets/` folder) |

### Commits in `Walmart_DBT_DATABRICKS` (in order)

| Commit | What |
|---|---|
| `4102c6a` | dbt project: silver/gold models, tests, snapshots (initial) |
| `e6a0f7d` | README replaced |
| (dbt fixes, committed in the dbt repo) | Removed employee fan-out: `obt_b` no longer joins employees; `fact_orders` drops `employee_id`; `eph_employees` reads `employees_t`; `fact_orders.yml` adds a grain test |
| `a727a2e` | `profiles.yml` added for the dbt task (see section 5) |
| `5e4149b` | Bundle: `databricks.yml`, `resources/walmart_pipeline_job.job.yml`, `resources/ingest_walmart.pipeline.yml` |
| `c43faf4` | Prod target; catalog, connection, and warehouse parameterized |

## 4. Fixes made along the way

1. **Employee fan-out.** `obt_b` joined `employees_t` on `store_id`, so each order item was repeated once per store employee (about 10 rows). `SUM(line_amount)` on `fact_orders` returned 189.4M; the correct total is 18,947,796.56. Fixed upstream in dbt, and downstream by `fact_order_items` (order item x store, one row per key).
2. **SCD2 current rows** use `dbt_valid_to = '9999-12-31'`, not NULL. All current-row views filter on that value.
3. **Lakebase ingestion failed on schedule.** The pipeline's connection used an OAuth token, which expires after one hour. Scheduled runs at 03:29 failed; a manual run at 20:18 on 2026-11-05 succeeded. Fix: a dedicated Postgres role `walmart_ingest` with a password stored in the connection (see section 6).
4. **dbt task could not find its profile.** Error: `Could not find profile named 'walmart-dbt-project'`. Fix: a committed `profiles.yml` read through `profiles_directory: .`, with no `warehouse_id` on the task (the docs say `profiles_directory` and `warehouse_id` can't be combined).
5. **`dbt seed` failed / was not needed.** Removed. The repo has a `seeds/` folder locally but none is needed by the models.
6. **Bundle path warning.** Prod root path moved from `/Workspace/Shared` (writable by all users) to the user's folder.

## 5. dbt task configuration (required)

In the job's `dbt_transformation` task:

- Source: Git, URL `https://github.com/vinayshetty777/Walmart_DBT_DATABRICKS.git`, branch `main`.
- Project directory: `.`
- Profiles directory: `.`
- SQL warehouse: **empty**. Catalog: **empty**. The profile supplies them.
- Commands: `dbt deps`, `dbt build`.

`profiles.yml` (committed, no secrets):

```yaml
walmart-dbt-project:
  target: dev
  outputs:
    dev:
      type: databricks
      catalog: walmart
      schema: default
      host: "{{ env_var('DBT_HOST', 'dbc-a4e7f3b4-dfcf.cloud.databricks.com') }}"
      http_path: /sql/1.0/warehouses/88712a7ffa1cbac4
      token: "{{ env_var('DBT_ACCESS_TOKEN') }}"
      threads: 4
```

Databricks injects `DBT_ACCESS_TOKEN` at run time for the job's Run As identity.
Prod needs its own profile target or an override for `catalog: walmart_prod`. **Not done yet.**

Git access: the Databricks user must have a GitHub connection under user settings, or the repo must be reachable.

## 6. Ingestion credentials (Lakebase)

- **Do not use the OAuth token** for scheduled runs. It expires after one hour.
- Create a dedicated Postgres role per environment, and grant it read access to the source:

```sql
CREATE ROLE walmart_ingest LOGIN PASSWORD '<generated>';
GRANT CONNECT ON DATABASE walmart_db TO walmart_ingest;
GRANT USAGE ON SCHEMA raw TO walmart_ingest;
GRANT SELECT ON ALL TABLES IN SCHEMA raw TO walmart_ingest;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT SELECT ON TABLES TO walmart_ingest;
```

- Generate the password locally (for example with `RandomNumberGenerator`), store it in a password manager, and enter it only in the Databricks connection form.
- Prod: create a separate role and password (for example `walmart_ingest_prod`), and a connection `walmart_lakebase_prod`. **Not done yet.**

## 7. Bundle commands

Run from `Walmart_DBT_DATABRICKS`. The CLI profile is `Vinay_chayapathi`.

```bash
databricks bundle validate -t dev  --profile Vinay_chayapathi
databricks bundle validate -t prod --profile Vinay_chayapathi

# Bind existing resources (done for dev; prod has none yet)
databricks bundle deployment bind walmart_pipeline_job 660234436577868 -t dev --auto-approve --profile Vinay_chayapathi
databricks bundle deployment bind ingest_walmart 576b9b68-9955-449c-829c-53f8168b1c83 -t dev --auto-approve --profile Vinay_chayapathi

# Deploy (NOT yet run for either target)
databricks bundle deploy -t dev  --profile Vinay_chayapathi
databricks bundle deploy -t prod --profile Vinay_chayapathi
databricks bundle run walmart_pipeline_job -t prod --profile Vinay_chayapathi
```

Bind before deploying. Without the bind, the bundle creates a second job and pipeline.

## 8. Open items (must finish before CI/CD)

1. **Prod Lakebase connection** `walmart_lakebase_prod` and role `walmart_ingest_prod`. Blocks the prod deploy.
2. **Prod dbt profile.** Add a `prod` output with `catalog: walmart_prod` to `profiles.yml`, or override it per target.
3. **Metric views.** `base_view` and `creating_metric_view` point at a file under the metric-view bundle's dev deployment (`/Workspace/Users/.../.bundle/walmart_metric_views/dev/files/...`). Either bring the metric-view SQL into this bundle, or call the metric-view job with `run_job_task`. Until then, prod will depend on a dev-only path.
4. **Dashboard task** `walmart_kpi_dashboard` is in the job but not in the bundle yet. Add it as a `dashboards` resource, or leave it as a UI-managed task and note that.
5. **Schedule.** Add a `schedule` block with `pause_status: PAUSED` to prod, then unpause after a successful manual run.
6. **Dev deploy.** Pending: it applies the `dbt build` change and parameterized YAML to the existing dev job.
7. **Metric-view repo.** `walmart-metric-views` is not pushed. Push it to its own GitHub repo, or fold it into this one.
8. **Grain test.** `tests/fact_order_items_grain_check.sql` is not wired into the job. Add it as a task, or rely on the dbt grain test in `fact_orders.yml`.

## 9. CI/CD plan (not yet built)

Proposed GitHub Actions flow, using a Databricks service principal instead of a personal token:

1. **On pull request:** `databricks bundle validate -t dev` and `dbt parse` (no warehouse access needed).
2. **On merge to `main`:** `databricks bundle deploy -t dev`, then `databricks bundle run walmart_pipeline_job -t dev`.
3. **Manual approval gate**, then `databricks bundle deploy -t prod` and `databricks bundle run walmart_pipeline_job -t prod`.

Secrets to store in GitHub (never in the repo):
- `DATABRICKS_HOST`, `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET` (service principal with OAuth M2M).
- `DBT_ACCESS_TOKEN` is injected by Databricks for the job's Run As identity, so CI doesn't need it.
- Lakebase passwords stay in the Databricks connections, not in GitHub.

Use a service principal for the job's Run As, so the schedule doesn't depend on a personal login.

## 10. Rules to keep

- Never commit tokens, passwords, or `.env` files. `.gitignore` excludes `dbt_packages/`, `target/`, `logs/`, `.env`.
- Don't push the parent git repo of the local dbt folder.
- After the bundle manages a resource, edit it in the bundle, not in the UI. Changes made in the UI are overwritten on the next deploy.
- Run `bundle validate` before every deploy.
