{{ header }}
{% from 'macros.sql' import enumerate_table_combinations %}

WITH
{{
    enumerate_table_combinations(
        source_table,
        "all_combos",
        cubed_attributes,
        attribute_combinations,
        add_windows_release_sample = channel == "release",
        use_sample_id = use_sample_id
    )
}},
build_ids AS (
  SELECT
    app_build_id,
    channel,
  FROM
    sampled_source
  GROUP BY
    1,
    2
  HAVING
      COUNT(DISTINCT client_id) > {{ minimum_client_count }}
  UNION ALL
  SELECT
    '*',
    '*'
),
histograms_cte AS (
  SELECT
    {% if channel == "release" %}
      sampled,
    {% endif %}
    {{ attributes }},
    ARRAY(
      SELECT AS STRUCT
        {{metric_attributes}},
        {% if channel == "release" %}
        -- Logic to count clients based on sampled windows release data, which started in v119.
        -- If you're changing this, then you'll also need to change
        -- clients_daily_[scalar | histogram]_aggregates
          mozfun.glam.histogram_normalized_sum_with_original(value, IF(sampled, 10.0, 1.0)) AS aggregates,
        {% else %}
          mozfun.glam.histogram_normalized_sum_with_original(value, 1.0) AS aggregates,
        {% endif %}
      FROM unnest(histogram_aggregates)
    ) AS histogram_aggregates
  FROM
    sampled_source
),
unnested AS (
  SELECT
    {{ attributes }},
    {% for metric_attribute in metric_attributes_list %}
        histogram_aggregates.{{ metric_attribute }} AS {{ metric_attribute }},
    {% endfor %}
    aggregates.key AS bucket,
    aggregates.value AS value,
    aggregates.non_norm_value AS non_norm_value
  FROM
    histograms_cte,
    UNNEST(histogram_aggregates) AS histogram_aggregates,
    UNNEST(aggregates) AS aggregates
),
-- Find information that can be used to construct the bucket range. Most of the
-- distributions follow a bucketing rule of 8*log2(n). This doesn't apply to the
-- custom distributions e.g. GeckoView, which needs to incorporate information
-- from the probe info service.
-- See: https://mozilla.github.io/glean/book/user/metrics/custom_distribution.html
distribution_metadata AS (
    SELECT *
    FROM UNNEST(
        [
            {% for meta in custom_distribution_metadata_list %}
                STRUCT(
                    "{{ meta.type }}" as metric_type,
                    "{{ meta.name.replace('.', '_') }}" as metric,
                    {{ meta.range_min }} as range_min,
                    {{ meta.range_max }} as range_max,
                    {{ meta.bucket_count }} as bucket_count,
                    "{{ meta.histogram_type }}" as histogram_type
                )
                {{ "," if not loop.last else "" }}
            {% endfor %}
        ]
    )
    UNION ALL
    SELECT
      metric_type,
      metric,
      NULL AS range_min,
      MAX(SAFE_CAST(bucket AS INT64)) AS range_max,
      NULL AS bucket_count,
      NULL AS histogram_type
    FROM
      unnested
    WHERE
      NOT ENDS_WITH(metric_type, "custom_distribution")
    GROUP BY
      metric_type,
      metric
),
records as (
    SELECT
        {{ attributes }},
        {{ metric_attributes }},
        CAST(bucket AS STRING) AS bucket,
        1.0 * SUM(value) AS normalized_value,
        1.0 * SUM(non_norm_value) AS non_norm_value,
    FROM
        unnested
    GROUP BY
        {{ attributes }},
        {{ metric_attributes }},
        bucket
),
with_combos AS (
  SELECT
    records.* REPLACE (
      COALESCE(combo.ping_type, records.ping_type) AS ping_type,
      COALESCE(combo.os, records.os) AS os,
      COALESCE(combo.app_build_id, records.app_build_id) AS app_build_id
    )
  FROM
    records
  CROSS JOIN
    static_combos AS combo
),
aggregated_combos AS (
  SELECT
    ping_type,
    os,
    app_version,
    app_build_id,
    channel,
    metric,
    metric_type,
    key,
    agg_type,
    STRUCT<key STRING, value FLOAT64>(bucket, SUM(normalized_value)) AS record,
    STRUCT<key STRING, value FLOAT64>(bucket, SUM(non_norm_value)) AS non_norm_record,
  FROM
    with_combos
  INNER JOIN
    build_ids
  USING
    (app_build_id, channel)
  GROUP BY
      ping_type,
      os,
      app_version,
      app_build_id,
      channel,
      metric,
      metric_type,
      key,
      agg_type,
      bucket
)

SELECT
    * EXCEPT(metric_type, histogram_type),
    -- Suffix `custom_distribution` with bucketing type
    IF(
      histogram_type IS NOT NULL,
      CONCAT(metric_type, "_", histogram_type),
      metric_type
    ) as metric_type
FROM
    aggregated_combos
LEFT OUTER JOIN
    distribution_metadata
    USING (metric_type, metric)