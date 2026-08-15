USE CATALOG ${catalogo};

DROP TABLE IF EXISTS ${catalogo}.golden.fact_sales;
DROP TABLE IF EXISTS ${catalogo}.golden.dim_product;
DROP TABLE IF EXISTS ${catalogo}.golden.dim_customer;
DROP TABLE IF EXISTS ${catalogo}.golden.agg_sales_by_category_month;
DROP TABLE IF EXISTS ${catalogo}.golden.agg_sales_by_holiday;
DROP TABLE IF EXISTS ${catalogo}.golden.ecommerce_marketing_roi;

DROP TABLE IF EXISTS ${catalogo}.silver.superstore_clean;
DROP TABLE IF EXISTS ${catalogo}.silver.ecommerce_daily_clean;

DROP TABLE IF EXISTS ${catalogo}.bronze.superstore_raw;
DROP TABLE IF EXISTS ${catalogo}.bronze.ecommerce_raw;
DROP TABLE IF EXISTS ${catalogo}.bronze.calendar_holidays;
