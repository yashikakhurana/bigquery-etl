CREATE OR REPLACE VIEW
  `moz-fx-data-shared-prod.telemetry.fx_health_ind_clients_daily_by_os`
AS
SELECT
  *
FROM
  `moz-fx-data-shared-prod.telemetry_derived.fx_health_ind_clients_daily_by_os_v1`
