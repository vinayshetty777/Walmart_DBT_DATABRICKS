-- Sales order metrics: one row per order item (grain), joined to current SCD2 dimensions.
CREATE OR REPLACE VIEW walmart.walmart_metric_views.sales_order_metrics
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
comment: "Retail order sales KPIs at order-item grain (one row per order item; an order can contain several items). Revenue, units, orders, sliced by product, store, customer location, and time. Includes all order statuses; filter on Order Status to scope."
source: walmart.walmart_metric_views.fact_order_items
filter: "orders.order_status IN ('Completed', 'Pending', 'Returned', 'Cancelled')"
joins:
  - name: orders
    source: walmart.walmart_metric_views.v_dim_orders_current
    'on': source.order_item_id = orders.order_item_id
  - name: products
    source: walmart.walmart_metric_views.v_dim_products_current
    'on': source.product_id = products.product_id
  - name: stores
    source: walmart.walmart_metric_views.v_dim_stores_current
    'on': source.store_id = stores.store_id
  - name: customers
    source: walmart.walmart_metric_views.v_dim_customers_current
    'on': source.customer_id = customers.customer_id
dimensions:
  - name: Order Date
    expr: DATE(orders.order_timestamp)
    comment: "Calendar date the order item was placed."
    display_name: "Order Date"
    synonyms: ["sale date", "purchase date"]
  - name: Order Month
    expr: DATE_TRUNC('MONTH', orders.order_timestamp)
    comment: "Month the order item was placed (first day of month)."
    display_name: "Order Month"
  - name: Order Status
    expr: orders.order_status
    comment: "Current status of the order: Completed, Pending, Returned, or Cancelled."
    display_name: "Order Status"
    synonyms: ["status"]
  - name: Payment Method
    expr: orders.payment_method
    comment: "Payment method used for the order."
    display_name: "Payment Method"
  - name: Product Category
    expr: products.category
    comment: "Product category."
    display_name: "Product Category"
    synonyms: ["category"]
  - name: Brand
    expr: products.brand
    comment: "Product brand."
    display_name: "Brand"
  - name: Store Name
    expr: stores.store_name
    comment: "Name of the store where the item was sold."
    display_name: "Store Name"
    synonyms: ["store"]
  - name: Store City
    expr: stores.store_city
    comment: "City of the store."
    display_name: "Store City"
  - name: Store Province
    expr: stores.store_province
    comment: "Province or state of the store."
    display_name: "Store Province"
  - name: Customer Province
    expr: customers.customer_province
    comment: "Province or state of the customer."
    display_name: "Customer Province"
  - name: Customer Country
    expr: customers.customer_country
    comment: "Country of the customer."
    display_name: "Customer Country"
measures:
  - name: Total Revenue
    expr: SUM(source.line_amount)
    comment: "Sum of order-item line amounts (quantity x unit price), in USD."
    display_name: "Total Revenue"
    synonyms: ["sales", "revenue", "gross sales"]
  - name: Units Sold
    expr: SUM(source.quantity)
    comment: "Total units sold across order items."
    display_name: "Units Sold"
    synonyms: ["quantity sold", "units"]
  - name: Order Items
    expr: COUNT(DISTINCT source.order_item_id)
    comment: "Number of distinct order items."
    display_name: "Order Items"
  - name: Orders
    expr: COUNT(DISTINCT source.order_id)
    comment: "Number of distinct orders. An order with several items is counted once per cell."
    display_name: "Orders"
    synonyms: ["order count", "number of orders"]
  - name: Customers Purchasing
    expr: COUNT(DISTINCT source.customer_id)
    comment: "Number of distinct customers who placed an order item in the selected slice."
    display_name: "Customers Purchasing"
    synonyms: ["unique customers", "buyers"]
  - name: Completed Revenue
    expr: SUM(source.line_amount) FILTER (WHERE orders.order_status = 'Completed')
    comment: "Revenue from order items with status Completed, in USD."
    display_name: "Completed Revenue"
  - name: Returned Revenue
    expr: SUM(source.line_amount) FILTER (WHERE orders.order_status = 'Returned')
    comment: "Revenue from order items with status Returned, in USD."
    display_name: "Returned Revenue"
  - name: Average Order Value
    expr: MEASURE(`Total Revenue`) / MEASURE(`Orders`)
    comment: "Total revenue divided by distinct orders, in USD."
    display_name: "Average Order Value"
    synonyms: ["AOV", "average basket"]
  - name: Average Unit Price
    expr: MEASURE(`Total Revenue`) / MEASURE(`Units Sold`)
    comment: "Total revenue divided by units sold, in USD."
    display_name: "Average Unit Price"
$$
