-- Query for fenix_derived.tos_rollout_enrollments_v1
            -- For more information on writing queries see:
            -- https://docs.telemetry.mozilla.org/cookbooks/bigquery/querying.html
SELECT DISTINCT
  client_id,
  submission_timestamp,
  JSON_VALUE(event_extra, '$.experiment') AS slug,
  JSON_VALUE(event_extra, '$.branch') AS branch
FROM
  `moz-fx-data-shared-prod.fenix.events_stream`
WHERE
  1 = 1
  AND DATE(submission_timestamp) = @submission_date
  AND event_category = 'nimbus_events'
  AND event_name = 'enrollment'
  AND JSON_VALUE(event_extra, '$.experiment') IN (
    'new-onboarding-experience-experiment-phase-1-android',
    'new-onboarding-experience-experiment-phase-2-android',
    'new-onboarding-experience-experiment-phase-3-android',
    'new-onboarding-experience-experiment-phase-4-android'
  )
