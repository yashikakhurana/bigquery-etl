CREATE OR REPLACE VIEW
  `moz-fx-glam-prod.glam_etl.glam_desktop_beta_aggregates` AS (
    WITH base AS (
      SELECT
        * EXCEPT (percentiles, non_norm_percentiles),
        IF(
          percentiles IS NOT NULL,
          NULL,
          mozfun.glam.histogram_cast_struct(histogram)
        ) AS struct_histogram,
        IF(
          metric_type IN ("scalar", "keyed-scalar")
          OR non_norm_percentiles IS NOT NULL,
          NULL,
          mozfun.glam.histogram_cast_struct(non_norm_histogram)
        ) AS struct_non_norm_histogram,
        percentiles AS existing_percentiles,
        non_norm_percentiles AS existing_non_norm_percentiles
      FROM
        `moz-fx-glam-prod.glam_etl.glam_desktop_beta_aggregates_v1`
      WHERE
  -- filter based on https://github.com/mozilla/python_mozaggregator/blob/6c0119bfd0b535346c37cb3f707d998039d3e24b/mozaggregator/service.py#L51
        (
          metric NOT LIKE r"%search\_counts%"
          AND metric NOT LIKE r"%browser\_search%"
          AND metric NOT LIKE r"%event\_counts%"
          AND metric NOT LIKE r"%browser\_engagement\_navigation%"
          AND metric NOT LIKE r"%manager\_message\_size%"
          AND metric NOT LIKE r"%dropped\_frames\_proportion%"
        )
        AND metric_type NOT IN ("boolean", "keyed-scalar-boolean")
    ),
    calculated_percentiles AS (
      SELECT
        * EXCEPT (struct_histogram, struct_non_norm_histogram),
        IF(
          struct_histogram IS NOT NULL,
          mozfun.glam.histogram_cast_json(
            ARRAY<STRUCT<key STRING, value FLOAT64>>[
              ('0.1', mozfun.glam.percentile(0.1, struct_histogram, metric_type)),
              ('1', mozfun.glam.percentile(1, struct_histogram, metric_type)),
              ('5', mozfun.glam.percentile(5, struct_histogram, metric_type)),
              ('25', mozfun.glam.percentile(25, struct_histogram, metric_type)),
              ('50', mozfun.glam.percentile(50, struct_histogram, metric_type)),
              ('75', mozfun.glam.percentile(75, struct_histogram, metric_type)),
              ('95', mozfun.glam.percentile(95, struct_histogram, metric_type)),
              ('99', mozfun.glam.percentile(99, struct_histogram, metric_type)),
              ('99.9', mozfun.glam.percentile(99.9, struct_histogram, metric_type))
            ]
          ),
          existing_percentiles
        ) AS percentiles,
        IF(
          struct_non_norm_histogram IS NOT NULL,
          mozfun.glam.histogram_cast_json(
            ARRAY<STRUCT<key STRING, value FLOAT64>>[
              ('0.1', mozfun.glam.percentile(0.1, struct_non_norm_histogram, metric_type)),
              ('1', mozfun.glam.percentile(1, struct_non_norm_histogram, metric_type)),
              ('5', mozfun.glam.percentile(5, struct_non_norm_histogram, metric_type)),
              ('25', mozfun.glam.percentile(25, struct_non_norm_histogram, metric_type)),
              ('50', mozfun.glam.percentile(50, struct_non_norm_histogram, metric_type)),
              ('75', mozfun.glam.percentile(75, struct_non_norm_histogram, metric_type)),
              ('95', mozfun.glam.percentile(95, struct_non_norm_histogram, metric_type)),
              ('99', mozfun.glam.percentile(99, struct_non_norm_histogram, metric_type)),
              ('99.9', mozfun.glam.percentile(99.9, struct_non_norm_histogram, metric_type))
            ]
          ),
          existing_non_norm_percentiles
        ) AS non_norm_percentiles
      FROM
        base
    )
    SELECT
      version,
      os,
      build_id,
      process,
      metric,
      metric_key,
      client_agg_type,
      metric_type,
      total_users,
      histogram,
      percentiles,
      total_sample,
      non_norm_histogram,
      IF(
        metric_type IN ("scalar", "keyed-scalar"),
        percentiles,
        non_norm_percentiles
      ) AS non_norm_percentiles
    FROM
      calculated_percentiles
  )
