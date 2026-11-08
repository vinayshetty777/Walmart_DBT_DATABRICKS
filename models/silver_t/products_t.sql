{{ config(materialized='incremental', unique_key='product_id') }}

select 
    *,
    current_timestamp() AS processed_at
from 
    {{ source('bronze', 'products') }}
{% if is_incremental() %}
where updated_timestamp > (select coalesce(max(updated_timestamp), '1900-01-01') from {{ this }})
{% endif %}