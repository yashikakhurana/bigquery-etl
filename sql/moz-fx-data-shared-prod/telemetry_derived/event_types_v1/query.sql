
-- Generated by ./bqetl generate events_daily
SELECT
  * EXCEPT (submission_date)
FROM
  `moz-fx-data-shared-prod.telemetry_derived.event_types_history_v1`
  {% if not is_init() %}
    WHERE
      submission_date = @submission_date
  {% endif %}
