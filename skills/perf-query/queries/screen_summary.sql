SELECT
  REGEXP_REPLACE(event_name, '^_st_', '') AS screen_name,
  COUNT(*) AS total_samples,
  ROUND(SAFE_DIVIDE(
    COUNTIF(trace_info.screen_info.frozen_frame_ratio > 0), COUNT(*)
  ) * 100, 2) AS frozen_frames_pct,
  ROUND(SAFE_DIVIDE(
    COUNTIF(trace_info.screen_info.slow_frame_ratio > 0.5), COUNT(*)
  ) * 100, 2) AS slow_render_pct
FROM `{{TABLE}}`
WHERE
  _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {{DAYS}} DAY)
  AND event_type = 'SCREEN_TRACE'
  AND trace_info.screen_info IS NOT NULL
  AND trace_info.screen_info.frozen_frame_ratio BETWEEN 0 AND 1
  AND trace_info.screen_info.slow_frame_ratio BETWEEN 0 AND 1
GROUP BY screen_name
HAVING total_samples >= {{MIN_SAMPLES}}
ORDER BY total_samples DESC
LIMIT {{MAX_SCREENS}}
