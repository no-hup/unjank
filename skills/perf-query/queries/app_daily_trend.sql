SELECT
  DATE(_PARTITIONTIME) AS date,
  ROUND(SAFE_DIVIDE(
    COUNTIF(trace_info.screen_info.frozen_frame_ratio > 0), COUNT(*)
  ) * 100, 2) AS frozen_frames_pct,
  ROUND(SAFE_DIVIDE(
    COUNTIF(trace_info.screen_info.slow_frame_ratio > 0.5), COUNT(*)
  ) * 100, 2) AS slow_render_pct,
  COUNT(*) AS sample_count
FROM `{{TABLE}}`
WHERE
  _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {{DAYS}} DAY)
  AND event_type = 'SCREEN_TRACE'
  AND trace_info.screen_info IS NOT NULL
  AND trace_info.screen_info.frozen_frame_ratio BETWEEN 0 AND 1
  AND trace_info.screen_info.slow_frame_ratio BETWEEN 0 AND 1
GROUP BY date
HAVING sample_count >= {{MIN_SAMPLES}}
ORDER BY date ASC
