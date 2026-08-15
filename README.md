# Retail Medallion ETL — Azure Databricks + Unity Catalog

ETL de datos retail bajo arquitectura medallion (**Bronze → Silver → Golden**) sobre Azure Databricks, con gobierno de datos vía Unity Catalog, publicación en Azure SQL Database, dashboard en Databricks Lakeview, y despliegue automatizado a dos ambientes (desarrollo y producción) vía GitHub Actions.

## 1. Objetivo

Construir una única fuente de verdad de ventas retail a partir de tres fuentes heterogéneas — dos transaccionales (Superstore, E-commerce) y una de referencia (calendario de feriados) — integrarlas, limpiarlas, y transformarlas progresivamente hasta tablas analíticas listas para consumo en Power BI / Databricks Lakeview.

## 2. Infraestructura provisionada

| Recurso | Nombre / Valor |
|---|---|
| Resource Group | `rg-retailprojectdr` |
| Storage Account (ADLS Gen2) | `adlsretailproject0826` |
| Containers | `raw`, `retail-data`, `uc-managed` |
| SQL Server | `serverretail` |
| Azure SQL Database | `retail_medallion_golden` (schema `golden`) |
| Azure Key Vault | `akv-retailprojectdr` |
| Databricks workspace — desarrollo | `adbsretailproject0826` |
| Databricks workspace — producción | `adbsretailproject0826Prod` |
| Unity Catalog — catalog | `retail_medallion_dev` (dev) / `retail_medallion` (prod) |

## 3. Fuentes de datos (contenido real en `raw/`)

### 3.1 Superstore — `raw/superstore/` (grano: línea de orden)
CSV clásico de ventas retail, 9994 filas, encoding **ISO-8859-1** (no UTF-8), fechas en formato **M/d/yyyy**.

| Columna | Tipo | Contenido |
|---|---|---|
| `Row_ID` | INT | Identificador secuencial único de la fila (llave real de la fuente) |
| `Order_ID` | STRING | Identificador del pedido (se repite entre líneas de un mismo pedido) |
| `Order_Date`, `Ship_Date` | STRING | Fecha de pedido y de despacho |
| `Ship_Mode` | STRING | Modalidad de envío |
| `Customer_ID`, `Customer_Name` | STRING | Cliente |
| `Segment` | STRING | Segmento del cliente (Consumer, Corporate, Home Office) |
| `Country`, `City`, `State`, `Postal_Code`, `Region` | STRING | Geografía del pedido |
| `Product_ID`, `Category`, `Sub_Category`, `Product_Name` | STRING | Jerarquía y detalle del producto |
| `Sales` | DOUBLE | Monto vendido de la línea |
| `Quantity` | INT | Unidades vendidas |
| `Discount` | DOUBLE | Descuento aplicado, como fracción (0.2 = 20%) |
| `Profit` | DOUBLE | Ganancia neta de la línea (ya calculada en la fuente) |

Propósito: fuente principal de ventas de canal físico, con el histórico más largo (2014–2017) y la única con ganancia real reportada por línea.

### 3.2 E-commerce — `raw/ecommerce/` (grano: 1 fila por día, sin Order_ID/Customer_ID/Region)
1000 filas, un día por fila, consecutivos (2023-01-01 a 2025-09-26). Fechas en formato **d-M-yyyy**.

| Columna | Tipo | Contenido |
|---|---|---|
| `Date` | STRING | Fecha (única por fila) |
| `Product_Category` | STRING | Categoría del producto predominante ese día |
| `Price` | DOUBLE | Precio unitario promedio del día |
| `Discount` | DOUBLE | Descuento del día, en escala 0–50 (porcentaje directo, no fracción) |
| `Customer_Segment` | STRING | Segmento predominante (Occasional, Regular, Premium) |
| `Marketing_Spend` | DOUBLE | Gasto de marketing del día |
| `Units_Sold` | INT | Unidades vendidas el día |

Propósito: canal digital, con el gasto de marketing como dato distintivo que ninguna otra fuente tiene — habilita el análisis de retorno de marketing (ROI) que no se puede hacer con Superstore.

### 3.3 Calendario de feriados — `raw/calendar/` (grano: fecha)
151 filas, feriados federales de EE. UU. 2014–2026 (`New Year's Day`, `MLK Day`, `Washington's Birthday`, `Memorial Day`, `Juneteenth`, `Independence Day`, `Labor Day`, `Columbus Day`, `Veterans Day`, `Thanksgiving`, `Christmas`, con sus fechas "observed" cuando caen en fin de semana). Generado con la librería Python `holidays` — los datasets de feriados disponibles en Kaggle no cubrían el rango real de fechas de las otras dos fuentes (2014–2017 y 2023–2025); usarlos tal cual habría producido cero coincidencias en el enriquecimiento.

| Columna | Tipo | Contenido |
|---|---|---|
| `Date` | STRING | Fecha del feriado (`yyyy-MM-dd`) |
| `Holiday` | STRING | Nombre del feriado |

Propósito: fuente de referencia (no transaccional), usada para enriquecer las otras dos con la señal de feriado/no feriado.

### 3.4 Por qué Superstore y E-commerce no se unen en una sola tabla
Grano incompatible: Superstore es línea de orden (con `Order_ID`, `Customer_ID`, `Region` reales); E-commerce es agregado diario sin esos campos. Forzar una unión habría requerido inventar identificadores sintéticos y dejar dimensiones vacías en la tabla de hechos. En su lugar, cada fuente se limpia en su propia tabla silver, y la comparación entre canales se resuelve en golden, en el grano que sí comparten (mes + categoría; feriado / no feriado).

## 4. Unity Catalog

**Storage Credential** `credential`: referencia un Access Connector for Azure Databricks vía Managed Identity — **no existe una sentencia SQL para crearlo**, se crea una sola vez por UI/CLI/API/Terraform; el código solo lo referencia.

**External Locations** (mismo storage credential, mismo Storage Account, 3 containers separados):
| External Location | Container | Contenido |
|---|---|---|
| `exlt-raw` | `raw` | CSV crudos (`superstore/`, `ecommerce/`, `calendar/`) |
| `exlt-retail-data` | `retail-data` | Tablas Delta `EXTERNAL` del medallion (`/bronze`, `/silver`, `/golden`) |
| `exlt-uc-managed` | `uc-managed` | Managed location del catalog (uso interno de Unity Catalog, separado de los datos del proyecto) |

**Catalog**: creado con `MANAGED LOCATION` apuntando a `exlt-uc-managed` (obligatorio si la cuenta no tiene Default Storage habilitado a nivel de metastore). **Schemas**: `bronze`, `silver`, `golden`.

**Grupos** (creados en el Account Console de Databricks, no en SQL): `retail_engineers` (acceso completo a bronze/silver/golden + external locations), `retail_readers` (solo `SELECT` sobre golden; bronze y silver explícitamente revocados).

## 5. Cómo cambia la información en cada capa

**Bronze — captura sin alterar.** Cada fuente se lee con schema explícito (no inferido, para evitar cambios silenciosos de tipo) y se escribe tal cual, agregando solo tres columnas de auditoría: `_source_file`, `_ingest_timestamp`, `_source_system`. No hay filtros ni limpieza — el objetivo es tener siempre disponible el dato exactamente como llegó, para poder reprocesar silver/golden sin volver a tocar las fuentes originales.

**Silver — limpieza, tipado y enriquecimiento, por fuente.** Cada una de las dos fuentes de venta se limpia por separado (ver tablas en la sección 6): deduplicación por la llave real, casteo seguro de fechas (`try_to_date`, que da `NULL` en vez de tumbar el job ante una fecha corrupta — las filas resultantes se descartan explícitamente), cálculo de columnas derivadas (`sales_amount`, `profit_margin_pct`, `lead_time_days` según la fuente), y un `LEFT JOIN` contra el calendario para agregar `is_holiday`/`holiday_name`. El objetivo es que silver sea la única versión confiable del dato — sin duplicados, sin fechas inválidas, con las unidades normalizadas (ej. descuento siempre como fracción 0–1, sin importar cómo venía en la fuente).

**Golden — agregación para consumo analítico.** Las dimensiones (`dim_product`, `dim_customer`) y la tabla de hechos (`fact_sales`) se derivan solo de Superstore, único origen con identificadores reales de producto/cliente. Las tablas agregadas (`agg_sales_by_category_month`, `agg_sales_by_holiday`) sí combinan ambas fuentes, porque se calculan en el grano que ambas comparten. `ecommerce_marketing_roi` es exclusiva de e-commerce. El objetivo de esta capa es que cualquier herramienta de BI pueda consumir directamente sin repetir lógica de negocio (deduplicación, cálculo de márgenes, normalización de descuentos ya están resueltos aguas arriba).

## 6. Tablas generadas, por capa

### Bronze
| Tabla | Contenido |
|---|---|
| `bronze.superstore_raw` | Las 21 columnas de Superstore sin transformar + metadata de auditoría |
| `bronze.ecommerce_raw` | Las 7 columnas de e-commerce sin transformar + metadata de auditoría |
| `bronze.calendar_holidays` | `Date`, `Holiday` sin transformar + metadata de auditoría |

### Silver
| Tabla | Grano | Columnas propias | Transformaciones aplicadas |
|---|---|---|---|
| `silver.superstore_clean` | línea de orden | `order_id, order_date, customer_id, customer_segment, region, product_id, category, sub_category, sales_amount, quantity, discount_pct, profit_amount, lead_time_days, profit_margin_pct, is_holiday, holiday_name` | dedup por `Row_ID`; `try_to_date` formato `M/d/yyyy`; `lead_time_days = ship_date − order_date`; `profit_margin_pct = profit/sales`; enriquecimiento de calendario |
| `silver.ecommerce_daily_clean` | día | `order_date, category, customer_segment, sales_amount, units_sold, discount_pct, marketing_spend, profit_amount, profit_margin_pct, is_holiday, holiday_name` | dedup por `Date`; `try_to_date` formato `d-M-yyyy`; `sales_amount = Price × Units_Sold`; `discount_pct = Discount/100`; `profit_amount = sales_amount×(1−discount_pct) − marketing_spend` (usa el gasto real de la fuente en vez de asumir un margen fijo); enriquecimiento de calendario |

### Golden
| Tabla | Fuente(s) | Grano | Columnas | Qué responde |
|---|---|---|---|---|
| `golden.dim_product` | Superstore | producto | `product_id, category, sub_category` | Jerarquía de producto, deduplicada |
| `golden.dim_customer` | Superstore | cliente | `customer_id, customer_segment, region` | Atributos de cliente, deduplicados |
| `golden.fact_sales` | Superstore | línea de orden | `order_id, order_date, customer_id, product_id, region, sales_amount, quantity, discount_pct, profit_amount, profit_margin_pct` | Detalle transaccional para reportes y agregaciones ad-hoc |
| `golden.agg_sales_by_category_month` | ambas | mes + categoría + `source_system` | `year_month, category, region, source_system, total_sales, total_profit, avg_profit_margin, total_units, num_orders` | Evolución de ventas y ganancia por categoría/canal a lo largo del tiempo |
| `golden.agg_sales_by_holiday` | ambas | feriado/no feriado + `source_system` | `is_holiday, holiday_name, source_system, total_sales, total_profit, num_orders, avg_order_value` | ¿Las ventas suben en fechas festivas, y por cuánto? |
| `golden.ecommerce_marketing_roi` | e-commerce | mes + categoría | `year_month, category, total_sales, total_marketing_spend, roi` | ¿El gasto de marketing se traduce en ventas? `roi = total_sales / total_marketing_spend` |

## 7. Publicación en Azure SQL Database

Después de escribir las 6 tablas golden en Delta (Unity Catalog), el mismo proceso las publica vía JDBC en `retail_medallion_golden.golden.*` — mismas 6 tablas, mismas columnas, mismo contenido. Conexión con `encrypt=true`, credenciales leídas desde el secret scope respaldado por Key Vault (nunca en texto plano). Modo `overwrite`: cada corrida hace `DROP`+`CREATE`+`INSERT` completo — no es incremental, las tablas SQL siempre reflejan el estado más reciente del catalog. Esta capa existe para que herramientas que no tienen conector nativo a Unity Catalog (o para dar una segunda vía de acceso desacoplada del workspace de Databricks) puedan consumir el resultado igual.

## 8. CI/CD (2 ramas)

`construccion` (desarrollo) y `main` (producción). Push a `construccion` despliega y ejecuta en el workspace de desarrollo sobre un cluster **dedicado y efímero** (se crea con el job, se destruye al terminar). Push a `main` (vía merge de PR desde `construccion`) despliega y ejecuta en producción sobre un cluster **existente y permanente** — es el único cluster clásico que queda encendido entre despliegues.

El despliegue se hace vía API REST de Databricks (`curl`/`jq`, sin Databricks CLI): importa los notebooks de `proceso/` y los `.sql` de `PrepAmb/`/`seguridad/` al workspace, borra y recrea el Job por nombre (idempotente), lo ejecuta (`run-now`), y monitorea el resultado por *polling* hasta que termina — el Action falla si el resultado no es `SUCCESS`.

## 9. Dashboard (Databricks Lakeview)

6 visualizaciones + 3 indicadores, todas sobre `golden.*`:

| Widget | Tipo | Dataset | Qué muestra |
|---|---|---|---|
| Ventas Totales, Ganancia Total, Órdenes Totales | Counter (x3) | `agg_sales_by_category_month` | Totales acumulados de todo el histórico, ambos canales |
| Tendencia de Ventas por Canal | Línea, coloreada por `source_system` | `agg_sales_by_category_month` | Evolución mensual de ventas, separando Superstore (2014–2017) de e-commerce (2023–2025) — hace evidente que son períodos distintos, no comparables mes a mes |
| Ventas por Categoría | Barras, coloreadas por `source_system` | `agg_sales_by_category_month` | Qué categorías venden más en cada canal — las categorías no se solapan del todo (Superstore: Furniture/Office Supplies/Technology; e-commerce: Electronics/Fashion/Sports/Toys/Home Decor) |
| Ventas: Feriado vs. Día Normal | Barras, coloreadas por `source_system` | `agg_sales_by_holiday` | Compara el volumen de ventas en fechas festivas contra el resto del año |
| ROI de Marketing | Línea, coloreada por `category` | `ecommerce_marketing_roi` | Eficiencia del gasto de marketing por categoría a lo largo del tiempo (solo e-commerce, única fuente con este dato) |
| Ventas por Región | Barras | `fact_sales` (solo Superstore) | Distribución geográfica de ventas — única tabla con región real |

Publicado con permiso "Share data permission": cualquiera con el link ve los datos usando las credenciales del publicador, sin necesitar cuenta propia en el workspace.

## 10. Configuración previa requerida (antes de correr cualquier notebook)

1. **Access Connector for Azure Databricks**: crear en el resource group, con rol IAM `Storage Blob Data Contributor` sobre `adlsretailproject0826`.
2. **Storage Credential `credential`**: crear por UI de Databricks (Catalog → External Data → Credentials → Create credential), referenciando el Access Connector del paso 1. No existe forma de crearlo por SQL.
3. **3 containers** en `adlsretailproject0826`: `raw`, `retail-data`, `uc-managed`.
4. **Azure SQL Server** `serverretail` + **Database** `retail_medallion_golden`: Networking en modo `Selected networks` con "Allow Azure services and resources to access this server" habilitado (con `No access`, la conexión JDBC ni siquiera llega a nivel de red).
5. **Schema `golden`** dentro de `retail_medallion_golden`: `CREATE SCHEMA golden;` (Query Editor del portal, con el usuario admin del servidor).
6. **Key Vault `akv-retailprojectdr`**: permission model `Vault access policy` (más simple que RBAC para este caso — evita la fricción de ubicar el service principal `AzureDatabricks` en el buscador de asignación de roles). Access policy con `Get`+`List` sobre Secrets para el principal `AzureDatabricks`.
7. **4 secrets en el Key Vault**: `sql-server-host` (`serverretail.database.windows.net`), `sql-database-name` (`retail_medallion_golden`), `sql-user`, `sql-password`.
8. **Secret scope `retail-kv-scope`** en Databricks (`#secrets/createScope`), backed by `akv-retailprojectdr` — **crear en AMBOS workspaces** (`adbsretailproject0826` y `adbsretailproject0826Prod`), ya que cada workspace tiene su propio almacén de secret scopes.
9. **Grupos** `retail_engineers` y `retail_readers` en el Account Console de Databricks.
10. **Estructura de carpetas en cada workspace**: `PrepAmb/`, `proceso/`, `seguridad/`, `reversion/` como carpetas **hermanas** (mismo nivel) — los notebooks usan rutas relativas (`../PrepAmb/01_prepamb.sql`, `../seguridad/01_grants.sql`) que dependen de esta jerarquía exacta.
11. **Los 3 CSV en `raw/`**: `superstore/`, `ecommerce/`, `calendar/` (este último ya viene generado en `datasets/calendar/`).
12. **Secrets de GitHub** (por ambiente): host y token de cada workspace de Databricks, nombre del Storage Account, nombre del cluster permanente de producción.

## 11. Estructura del repositorio

```
databricks-app/
├── datasets/            # calendario generado + referencia de fuentes
├── dashboard/            # export del dashboard (.lvdash.json, .png, .txt con el link)
├── reversion/             # DROP de tablas + limpieza de rutas físicas
├── .github/workflows/    # CI/CD (2 ramas: construccion / main)
├── seguridad/             # GRANTS por grupo
├── PrepAmb/               # external locations, catalog, schemas, DDL de las 9 tablas
├── proceso/               # 7 notebooks del ETL
├── certificaciones/
├── evidencias/
├── databricks.yml         # Asset Bundle (alternativa de referencia, no es el flujo activo)
└── README.md
```

## 12. Reversión

`reversion/01_reversion.py` ejecuta el `DROP TABLE` de las 9 tablas y borra las rutas físicas correspondientes con `dbutils.fs.rm(recurse=True)` — necesario porque las tablas son `EXTERNAL`, y `DROP TABLE` no elimina los archivos Delta subyacentes por sí solo.
