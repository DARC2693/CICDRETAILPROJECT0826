USE CATALOG ${catalogo};

GRANT USE CATALOG ON CATALOG ${catalogo} TO `retail_engineers`;
GRANT USE SCHEMA, CREATE TABLE, MODIFY, SELECT ON SCHEMA ${catalogo}.bronze TO `retail_engineers`;
GRANT USE SCHEMA, CREATE TABLE, MODIFY, SELECT ON SCHEMA ${catalogo}.silver TO `retail_engineers`;
GRANT USE SCHEMA, CREATE TABLE, MODIFY, SELECT ON SCHEMA ${catalogo}.golden TO `retail_engineers`;

GRANT USE CATALOG ON CATALOG ${catalogo} TO `retail_readers`;
GRANT USE SCHEMA, SELECT ON SCHEMA ${catalogo}.golden TO `retail_readers`;

REVOKE SELECT ON SCHEMA ${catalogo}.bronze FROM `retail_readers`;
REVOKE SELECT ON SCHEMA ${catalogo}.silver FROM `retail_readers`;

GRANT READ FILES ON EXTERNAL LOCATION `exlt-raw` TO `retail_engineers`;
GRANT READ FILES, WRITE FILES ON EXTERNAL LOCATION `exlt-retail-data` TO `retail_engineers`;
GRANT READ FILES, WRITE FILES ON EXTERNAL LOCATION `exlt-uc-managed` TO `retail_engineers`;
