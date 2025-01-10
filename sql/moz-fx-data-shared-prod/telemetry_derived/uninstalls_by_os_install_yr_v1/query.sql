SELECT
  DATE(submission_timestamp) AS submission_date,
  environment.system.os.install_year AS os_installation_year,
  COUNT(DISTINCT client_id) AS nbr_unique_clients_uninstalling,
FROM
  `moz-fx-data-shared-prod.telemetry.uninstall`
WHERE
  DATE(submission_timestamp) = @submission_date
  AND application.name = 'Firefox'
GROUP BY
  submission_date,
  os_installation_year
