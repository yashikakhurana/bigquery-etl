-- Creates a backwards-compatible flattened events dataset created from gcp-ingested event pings
-- Designed to provide continuity for the `events` dataset via a user-facing union view
WITH base AS (
  SELECT
    DATE(submission_timestamp) AS submission_date,
    document_id,
    client_id,
    normalized_channel,
    normalized_country_code AS country,
    environment.settings.locale AS locale,
    normalized_app_name AS app_name,
    metadata.uri.app_version AS app_version,
    normalized_os AS os,
    normalized_os_version AS os_version,
    environment.experiments AS experiments,
    sample_id,
    payload.session_id AS session_id,
    SAFE.TIMESTAMP_MILLIS(payload.process_start_timestamp) AS session_start_time,
    payload.subsession_id AS subsession_id,
    submission_timestamp AS `timestamp`,
    `moz-fx-data-shared-prod.udf.deanonymize_event`(e).*,
    event_process,
    application.build_id,
    environment.build.architecture AS build_architecture,
    environment.profile.creation_date AS profile_creation_date,
    environment.settings.is_default_browser,
    environment.settings.attribution.source AS attribution_source,
    environment.settings.attribution.dltoken AS attribution_dltoken,
    environment.system.is_wow64 AS system_is_wow64,
    environment.system.memory_mb AS system_memory_mb,
    metadata.geo.city,
    profile_group_id
  FROM
    `moz-fx-data-shared-prod.telemetry.event`
  CROSS JOIN
    UNNEST(
      [
        STRUCT("content" AS event_process, payload.events.content AS events),
        ("dynamic", payload.events.dynamic),
        ("extension", payload.events.extension),
        ("gpu", payload.events.gpu),
        ("parent", payload.events.parent)
      ]
    )
  CROSS JOIN
    UNNEST(events) AS e
  WHERE
    DATE(submission_timestamp) = @submission_date
)
SELECT
  *
FROM
  base
WHERE
  -- See https://bugzilla.mozilla.org/show_bug.cgi?id=1703362
  NOT (
    event_category = 'security'
    AND event_method = 'unexpectedload'
    AND mozfun.map.get_key(event_map_values, 'contenttype') = 'TYPE_STYLESHEET'
    AND mozfun.norm.truncate_version(app_version, 'major')
    BETWEEN 84
    AND 87
  )
  AND
  -- See https://bugzilla.mozilla.org/show_bug.cgi?id=1803833
  NOT (
    event_category = 'normandy'
    AND event_method = 'validationFailed'
    AND mozfun.map.get_key(event_map_values, 'reason') = 'invalid-feature'
    AND mozfun.map.get_key(event_map_values, 'feature') IN ('nimbus-qa-1', 'nimbus-qa-2')
    AND mozfun.norm.truncate_version(app_version, 'major') <= 108
  )
  AND
  -- See https://mozilla-hub.atlassian.net/browse/DENG-7513
  NOT (
    event_category = 'security'
    AND event_method = 'unexpectedload'
    AND normalized_channel = 'release'
    AND mozfun.norm.truncate_version(app_version, 'major')
    BETWEEN 133
    AND 135
  )
