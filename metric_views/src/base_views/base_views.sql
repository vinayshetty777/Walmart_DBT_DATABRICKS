-- Base views for the walmart metric views.
-- Run before the metric views (see databricks.yml job dependency).

-- Order-item fact, grain = one row per (order_id, order_item_id, store_id).
-- walmart.gold.fact_orders repeats each order item once per employee of its store
-- (~10 rows per item). Employee is dropped here, so each item appears exactly once.
-- Grain is enforced by tests/fact_order_items_grain_check.sql.
CREATE OR REPLACE TABLE walmart.walmart_metric_views.fact_order_items AS
SELECT DISTINCT
  order_id,
  order_item_id,
  store_id,
  product_id,
  customer_id,
  quantity,
  unit_price,
  line_amount
FROM walmart.gold.fact_orders;

-- SCD2 dimensions: current rows are marked with dbt_valid_to = '9999-12-31' (not NULL).
CREATE OR REPLACE VIEW walmart.walmart_metric_views.v_dim_orders_current AS
SELECT
  order_item_id,
  order_id,
  order_status,
  payment_method,
  order_timestamp
FROM walmart.gold.dim_orders
WHERE dbt_valid_to = '9999-12-31';

CREATE OR REPLACE VIEW walmart.walmart_metric_views.v_dim_products_current AS
SELECT
  product_id,
  product_name,
  category,
  brand,
  price
FROM walmart.gold.dim_products
WHERE dbt_valid_to = '9999-12-31';

CREATE OR REPLACE VIEW walmart.walmart_metric_views.v_dim_stores_current AS
SELECT
  store_id,
  store_name,
  store_city,
  store_province,
  store_country
FROM walmart.gold.dim_stores
WHERE dbt_valid_to = '9999-12-31';

-- Customer PII (name, email, phone) is intentionally excluded.
CREATE OR REPLACE VIEW walmart.walmart_metric_views.v_dim_customers_current AS
SELECT
  customer_id,
  customer_city,
  customer_province,
  customer_country
FROM walmart.gold.dim_customers
WHERE dbt_valid_to = '9999-12-31';
