-- Generated via ./bqetl generate experiment_monitoring
CREATE MATERIALIZED VIEW
IF
  NOT EXISTS `moz-fx-data-shared-prod.accounts_cirrus_derived.experiment_events_live_v1`
  PARTITION BY
    DATE(partition_date)
  OPTIONS
    (enable_refresh = TRUE, refresh_interval_minutes = 5)
  AS
  -- Cirrus apps uses specialized Glean structure per events
  WITH all_events AS (
    SELECT
      submission_timestamp,
      events,
      TRUE AS validation_errors_valid
    FROM
      `moz-fx-data-shared-prod.accounts_cirrus_live.enrollment_v1`
  ),
  experiment_events AS (
    SELECT
      submission_timestamp AS `timestamp`,
      event.category AS `type`,
      CAST(event.extra[SAFE_OFFSET(i)].value AS STRING) AS branch,
      CAST(event.extra[SAFE_OFFSET(j)].value AS STRING) AS experiment,
      event.name AS event_method,
      validation_errors_valid
    FROM
      all_events,
      UNNEST(events) AS event,
      -- Workaround for https://issuetracker.google.com/issues/182829918
      -- To prevent having the branch name set to the experiment slug,
      -- the number of generated array indices needs to be different.
      UNNEST(GENERATE_ARRAY(0, 50)) AS i,
      UNNEST(GENERATE_ARRAY(0, 51)) AS j
    WHERE
      event.category = 'cirrus_events'
      AND CAST(event.extra[SAFE_OFFSET(i)].key AS STRING) = 'branch'
      AND CAST(event.extra[SAFE_OFFSET(j)].key AS STRING) = 'experiment'
  )
  SELECT
    TIMESTAMP_TRUNC(`timestamp`, DAY) AS partition_date,
    DATE(`timestamp`) AS submission_date,
    `type`,
    experiment,
    branch,
    TIMESTAMP_ADD(
      TIMESTAMP_TRUNC(`timestamp`, HOUR),
    -- Aggregates event counts over 5-minute intervals
      INTERVAL(DIV(EXTRACT(MINUTE FROM `timestamp`), 5) * 5) MINUTE
    ) AS window_start,
    TIMESTAMP_ADD(
      TIMESTAMP_TRUNC(`timestamp`, HOUR),
      INTERVAL((DIV(EXTRACT(MINUTE FROM `timestamp`), 5) + 1) * 5) MINUTE
    ) AS window_end,
    COUNTIF(event_method = 'enroll' OR event_method = 'enrollment') AS enroll_count,
    COUNTIF(event_method = 'unenroll' OR event_method = 'unenrollment') AS unenroll_count,
    COUNTIF(event_method = 'graduate') AS graduate_count,
    COUNTIF(event_method = 'update') AS update_count,
    COUNTIF(event_method = 'enrollFailed') AS enroll_failed_count,
    COUNTIF(event_method = 'unenrollFailed') AS unenroll_failed_count,
    COUNTIF(event_method = 'updateFailed') AS update_failed_count,
    COUNTIF(event_method = 'disqualification') AS disqualification_count,
    COUNTIF(event_method = 'expose' OR event_method = 'exposure') AS exposure_count,
    -- order of operations bug means validation will always fail for clients before
    COUNTIF(
      event_method = 'validationFailed'
      AND validation_errors_valid
    ) AS validation_failed_count
  FROM
    experiment_events
  WHERE
    -- Limit the amount of data the materialized view is going to backfill when created.
    -- This date can be moved forward whenever new changes of the materialized views need to be deployed.
    timestamp > TIMESTAMP('2025-04-01')
  GROUP BY
    partition_date,
    submission_date,
    `type`,
    experiment,
    branch,
    window_start,
    window_end
