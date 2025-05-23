{{ header }}
WITH extracted AS (
  SELECT
    *,
    DATE(submission_timestamp) AS submission_date,
    client_info.client_id,
    "{{ ping_type }}" AS ping_type,
    COALESCE(
      SAFE_CAST(SPLIT(client_info.app_display_version, '.')[OFFSET(0)] AS INT64),
      0
    ) AS app_version,
    client_info.os AS os,
    client_info.app_build AS app_build_id,
    client_info.app_channel AS channel
  FROM
    `moz-fx-data-shared-prod.{{ source_table }}`
  WHERE
    DATE(submission_timestamp) = {{ submission_date }}
    AND client_info.client_id IS NOT NULL
),
sampled_data AS (
  SELECT
    *
  FROM
    extracted
  WHERE
    -- If you're changing this, then you'll also need to change probe_counts_v1,
    -- where sampling is taken into account for counting clients.
    channel IN ("nightly", "beta")
    OR (channel = "release" AND os != "Windows")
    OR (
        channel = "release" AND
        os = "Windows" AND
        sample_id < 10)
),
histograms AS (
  SELECT
    {{ attributes }},
    ARRAY<
      STRUCT<
        key STRING,
        metric STRING,
        metric_type STRING,
        value ARRAY<STRUCT<key STRING, value INT64>>
      >
    >[{{ histograms }}] AS metadata
  FROM
    sampled_data
),
flattened_histograms AS (
  SELECT
    {{ attributes }},
    metadata.*
  FROM
    histograms,
    UNNEST(metadata) as metadata
  WHERE
    value IS NOT NULL
),
labeled_histograms AS (
  SELECT
    {{ attributes }},
    ARRAY<
      STRUCT<
        metric STRING,
        metric_type STRING,
        keyed_values ARRAY<
          STRUCT<
            key STRING,
            value ARRAY<STRUCT<key STRING, value INT64>>
          >
        >
      >
    >[{{ labeled_histograms }}] AS metadata
  FROM
    sampled_data
),
flattened_labeled_histograms AS (
  SELECT
    sample_id,
    client_id,
    ping_type,
    submission_date,
    os,
    app_version,
    app_build_id,
    channel,
    key,
    metric,
    metric_type,
    value
  FROM
    labeled_histograms,
    UNNEST(metadata) AS metadata,
    UNNEST(metadata.keyed_values) AS keyed_values
  WHERE
    key IS NOT NULL
    AND value IS NOT NULL
),
flattened_all_histograms AS (
  SELECT * FROM flattened_histograms
  UNION ALL
  SELECT * FROM flattened_labeled_histograms
),
-- ARRAY_CONCAT_AGG may fail if the array of records exceeds 20 MB when
-- serialized and shuffled. This may exhibit itself in a pathological case where
-- the a single client sends *many* pings in a single day. However, this case
-- has not been observed. If this does occur, each histogram should be unnested
-- aggregated. This will force more shuffles and is inefficient. This may be
-- mitigated by removing all of the empty entries which are sent to keep bucket
-- ranges contiguous.
--
-- Tested via org_mozilla_fenix.metrics_v1 for 2020-02-23, unnest vs concat
-- Slot consumed: 00:50:15 vs 00:06:45, Shuffled: 27.5GB vs 6.0 GB
aggregated AS (
  SELECT
    {{ attributes }},
    key,
    metric,
    metric_type,
    mozfun.map.sum(ARRAY_CONCAT_AGG(mozfun.glam.histogram_filter_high_values(value))) as value
  FROM
    flattened_all_histograms
  GROUP BY
    {{ attributes }},
    key,
    metric,
    metric_type
)
SELECT
  {{ attributes }},
  ARRAY_AGG(
    STRUCT<
      metric STRING,
      metric_type STRING,
      key STRING,
      agg_type STRING,
      value ARRAY<STRUCT<key STRING, value INT64>>
    >(metric, metric_type, key, 'summed_histogram', value)
  ) AS histogram_aggregates
FROM
  aggregated
GROUP BY
  {{ attributes }}
