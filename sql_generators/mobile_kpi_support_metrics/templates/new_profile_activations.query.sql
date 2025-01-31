{{ header }}
WITH device_manufacturer_counts AS (
  SELECT
    submission_date,
    device_manufacturer,
    RANK() OVER(PARTITION BY submission_date ORDER BY COUNT(*) DESC) AS manufacturer_rank,
  FROM
  `{{ project_id }}.{{ dataset }}.new_profile_activation_clients`
  WHERE
    submission_date = @submission_date
  GROUP BY
    submission_date,
    device_manufacturer
)

SELECT
  submission_date,
  first_seen_date,
  normalized_channel,
  app_name,
  app_version,
  country,
  locale,
  os,
  os_version,
  -- Bucket device manufacturers with low count prior to aggregation
  IF(manufacturer_rank <= 150, device_manufacturer, "other") AS device_manufacturer,
  is_mobile,
  {% for field in product_attribution_fields.values() if not field.client_only %}
  {{ field.name }},
  {% endfor %}
  device_type,
  COALESCE(COUNTIF(is_activated), 0) AS activations,
  COALESCE(COUNTIF(is_early_engagement), 0) AS early_engagements,
FROM
  `{{ project_id }}.{{ dataset }}.new_profile_activation_clients`
LEFT JOIN
  device_manufacturer_counts
  USING(submission_date, device_manufacturer)
WHERE
  submission_date = @submission_date
GROUP BY
  submission_date,
  first_seen_date,
  normalized_channel,
  app_name,
  app_version,
  country,
  locale,
  os,
  os_version,
  device_type,
  device_manufacturer,
  is_mobile
  {% for field in product_attribution_fields.values() if not field.client_only %}
    {% if loop.first %},{% endif %}
    {{ field.name }}
    {% if not loop.last %},{% endif %}
  {% endfor %}
