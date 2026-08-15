CREATE EXTERNAL LOCATION IF NOT EXISTS `exlt-raw`
  URL 'abfss://raw@${storageName}.dfs.core.windows.net/'
  WITH (STORAGE CREDENTIAL credential)
  COMMENT 'Ubicacion externa para los CSV crudos (Superstore + E-commerce + Calendario de feriados)';

CREATE EXTERNAL LOCATION IF NOT EXISTS `exlt-retail-data`
  URL 'abfss://retail-data@${storageName}.dfs.core.windows.net/'
  WITH (STORAGE CREDENTIAL credential)
  COMMENT 'Ubicacion externa para las tablas bronze/silver/golden del proyecto retail';

CREATE EXTERNAL LOCATION IF NOT EXISTS `exlt-uc-managed`
  URL 'abfss://uc-managed@${storageName}.dfs.core.windows.net/'
  WITH (STORAGE CREDENTIAL credential)
  COMMENT 'Ubicacion externa dedicada al almacenamiento managed de Unity Catalog (separada de los datos del proyecto)';

CREATE CATALOG IF NOT EXISTS ${catalogo}
  MANAGED LOCATION 'abfss://uc-managed@${storageName}.dfs.core.windows.net/${catalogo}';

USE CATALOG ${catalogo};

CREATE SCHEMA IF NOT EXISTS ${catalogo}.bronze COMMENT 'Datos crudos, tal cual llegan de la fuente (Extract)';
CREATE SCHEMA IF NOT EXISTS ${catalogo}.silver COMMENT 'Datos limpios y tipados por fuente (Transform)';
CREATE SCHEMA IF NOT EXISTS ${catalogo}.golden COMMENT 'Datos agregados listos para consumo (Load / BI)';

CREATE TABLE IF NOT EXISTS ${catalogo}.bronze.superstore_raw (
  Row_ID INT,
  Order_ID STRING,
  Order_Date STRING,
  Ship_Date STRING,
  Ship_Mode STRING,
  Customer_ID STRING,
  Customer_Name STRING,
  Segment STRING,
  Country STRING,
  City STRING,
  State STRING,
  Postal_Code STRING,
  Region STRING,
  Product_ID STRING,
  Category STRING,
  Sub_Category STRING,
  Product_Name STRING,
  Sales DOUBLE,
  Quantity INT,
  Discount DOUBLE,
  Profit DOUBLE,
  _source_file STRING,
  _ingest_timestamp TIMESTAMP,
  _source_system STRING
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/bronze/superstore_raw';

CREATE TABLE IF NOT EXISTS ${catalogo}.bronze.ecommerce_raw (
  Date STRING,
  Product_Category STRING,
  Price DOUBLE,
  Discount DOUBLE,
  Customer_Segment STRING,
  Marketing_Spend DOUBLE,
  Units_Sold INT,
  _source_file STRING,
  _ingest_timestamp TIMESTAMP,
  _source_system STRING
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/bronze/ecommerce_raw';

CREATE TABLE IF NOT EXISTS ${catalogo}.bronze.calendar_holidays (
  Date STRING,
  Holiday STRING,
  _source_file STRING,
  _ingest_timestamp TIMESTAMP,
  _source_system STRING
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/bronze/calendar_holidays';

CREATE TABLE IF NOT EXISTS ${catalogo}.silver.superstore_clean (
  order_id STRING,
  order_date DATE,
  customer_id STRING,
  customer_segment STRING,
  region STRING,
  product_id STRING,
  category STRING,
  sub_category STRING,
  sales_amount DOUBLE,
  quantity INT,
  discount_pct DOUBLE,
  profit_amount DOUBLE,
  lead_time_days INT,
  profit_margin_pct DOUBLE,
  is_holiday BOOLEAN,
  holiday_name STRING,
  _transform_timestamp TIMESTAMP
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/silver/superstore_clean';

CREATE TABLE IF NOT EXISTS ${catalogo}.silver.ecommerce_daily_clean (
  order_date DATE,
  category STRING,
  customer_segment STRING,
  sales_amount DOUBLE,
  units_sold INT,
  discount_pct DOUBLE,
  marketing_spend DOUBLE,
  profit_amount DOUBLE,
  profit_margin_pct DOUBLE,
  is_holiday BOOLEAN,
  holiday_name STRING,
  _transform_timestamp TIMESTAMP
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/silver/ecommerce_daily_clean';

CREATE TABLE IF NOT EXISTS ${catalogo}.golden.dim_product (
  product_id STRING,
  category STRING,
  sub_category STRING
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/golden/dim_product';

CREATE TABLE IF NOT EXISTS ${catalogo}.golden.dim_customer (
  customer_id STRING,
  customer_segment STRING,
  region STRING
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/golden/dim_customer';

CREATE TABLE IF NOT EXISTS ${catalogo}.golden.fact_sales (
  order_id STRING,
  order_date DATE,
  customer_id STRING,
  product_id STRING,
  region STRING,
  sales_amount DOUBLE,
  quantity INT,
  discount_pct DOUBLE,
  profit_amount DOUBLE,
  profit_margin_pct DOUBLE
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/golden/fact_sales';

CREATE TABLE IF NOT EXISTS ${catalogo}.golden.agg_sales_by_category_month (
  year_month STRING,
  category STRING,
  region STRING,
  source_system STRING,
  total_sales DOUBLE,
  total_profit DOUBLE,
  avg_profit_margin DOUBLE,
  total_units INT,
  num_orders LONG
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/golden/agg_sales_by_category_month';

CREATE TABLE IF NOT EXISTS ${catalogo}.golden.agg_sales_by_holiday (
  is_holiday BOOLEAN,
  holiday_name STRING,
  source_system STRING,
  total_sales DOUBLE,
  total_profit DOUBLE,
  num_orders LONG,
  avg_order_value DOUBLE
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/golden/agg_sales_by_holiday';

CREATE TABLE IF NOT EXISTS ${catalogo}.golden.ecommerce_marketing_roi (
  year_month STRING,
  category STRING,
  total_sales DOUBLE,
  total_marketing_spend DOUBLE,
  roi DOUBLE
)
USING DELTA
LOCATION 'abfss://retail-data@${storageName}.dfs.core.windows.net/golden/ecommerce_marketing_roi';
