WITH base AS (
  SELECT 
    key,
    fields,
    fields.customfield_12310921 AS raw_sprint,
    unnest(changelog.values) AS change
  FROM read_ndjson(
    'out_mesos/jira.jsonl',
    auto_detect = true,
    ignore_errors = true,
    maximum_object_size = 50000000
  )
  WHERE fields.project.key = 'MESOS'
  AND fields.issuetype.subtask='False'
),

-- Flatten sprint entries and changelog items
split_sprints AS (
  SELECT
    key,
    fields,
    change.id AS change_id,
    change.author AS change_author,
    CAST(change.created  AS TIMESTAMP) AS change_time,
    unnest(change.items) AS change_item,
    regexp_replace(sprint_raw, '^\\"|\"$', '') AS sprint_entry
  FROM base,
  unnest(raw_sprint) AS t(sprint_raw)
),

-- Extract structured sprint metadata
parsed_sprints AS (
  SELECT
    key,
    fields,
    change_id,
    change_author,
    change_time,
    change_item,
    regexp_extract(sprint_entry, 'id=(\d+)', 1) AS sprint_id,
    regexp_extract(sprint_entry, 'name=([^,]+)', 1) AS sprint_name,
    regexp_extract(sprint_entry, 'startDate=([^,]+)', 1) AS sprint_start,
    regexp_extract(sprint_entry, 'endDate=([^,]+)', 1) AS sprint_end,
    regexp_extract(sprint_entry, 'state=([^,]+)', 1) AS sprint_state
  FROM split_sprints
),

-- Separate relevant changelog entries
status_changes AS (
  SELECT
    key,
    change_time,
    change_item.fromString AS from_status,
    change_item.toString AS to_status
  FROM split_sprints
  WHERE change_item.field = 'status'
),

sprint_changes AS (
  SELECT
    key,
    change_time,
    change_item.fromString AS from_sprint,
    change_item.toString AS to_sprint
  FROM split_sprints
  WHERE change_item.field = 'Sprint'
),

estimation_changes AS (
  SELECT
    key,
    change_time,
    CAST(change_item.fromString AS DOUBLE) AS from_estimation,
    CAST(change_item.toString AS DOUBLE) AS to_estimation
  FROM split_sprints
  WHERE change_item.field = 'customfield_12310293'
),
-- Combine and compute sprint-related status and change tracking
joined AS (
  SELECT
    ps.sprint_id,
    ps.sprint_name,
    ps.sprint_start,
    ps.sprint_end,
    ps.sprint_state,
    ps.key,
    ps.fields.customfield_12310293 as estimation,
    ps.fields.status.name as currentStatus,
    ps.fields.issuetype.name as issuetype,
    Concat(ps.fields.issuetype.name, '. ', ps.fields.summary, '. ', replace(replace(ps.fields.description, '\n', ' '), '\r', ' ')) as text,

    -- status at sprint start
    (
      SELECT sc.to_status
      FROM status_changes sc
      WHERE sc.key = ps.key AND sc.change_time <= CAST(ps.sprint_start AS TIMESTAMP)
      ORDER BY sc.change_time DESC
      LIMIT 1
    ) AS status_start,

    -- status at sprint end
    (
      SELECT sc.to_status
      FROM status_changes sc
      WHERE sc.key = ps.key AND sc.change_time <= CAST(ps.sprint_end AS TIMESTAMP)
      ORDER BY sc.change_time DESC
      LIMIT 1
    ) AS status_end,

    -- when added
    (
      SELECT min(sc.change_time)
      FROM sprint_changes sc
      WHERE sc.key = ps.key 
        AND sc.to_sprint LIKE '%' || ps.sprint_name || '%'
    ) AS added_dates,

    -- when removed
    (
      SELECT max(sc.change_time)
      FROM sprint_changes sc
      WHERE sc.key = ps.key 
        AND sc.from_sprint LIKE '%' || ps.sprint_name || '%'
        AND (sc.to_sprint NOT LIKE '%' || ps.sprint_name || '%' OR sc.to_sprint IS NULL)
    ) AS removed_dates,

    -- estimation at start
    (
      SELECT CAST(ec.to_estimation AS DOUBLE)
      FROM estimation_changes ec
      WHERE ec.key = ps.key AND ec.change_time <= CAST(ps.sprint_start AS TIMESTAMP)
      ORDER BY ec.change_time DESC
      LIMIT 1
    ) AS estimation_start,

    -- estimation at end
    (
      SELECT CAST(ec.to_estimation AS DOUBLE)
      FROM estimation_changes ec
      WHERE ec.key = ps.key AND ec.change_time <= CAST(ps.sprint_end AS TIMESTAMP)
      ORDER BY ec.change_time DESC
      LIMIT 1
    ) AS estimation_end
  FROM parsed_sprints ps
)

-- Final output grouped by sprint and issue
SELECT DISTINCT
  sprint_id,
  sprint_name,
  sprint_start,
  sprint_end,
  sprint_state,
  key AS issue_key,
  status_start,
  status_end,
  CAST(estimation AS DOUBLE) estimation,
  currentStatus,
  issuetype,
  estimation_start,
  estimation_end,
  text,
  CASE
    WHEN status_start IS NULL OR status_start = '' THEN 'Open'
    WHEN lower(status_start) IN ('closed', 'resolved') THEN 'Done'
    ELSE 'In Progress'
  END AS status_start_category,

  CASE
    WHEN status_end IS NULL OR status_end = '' THEN 'Open'
    WHEN lower(status_end) IN ('closed', 'resolved') THEN 'Done'
    ELSE 'In Progress'
  END AS status_end_category,

  added_dates,
  removed_dates,

-- Sprint ledger flow model variables
    CASE
    WHEN status_start_category = 'In Progress'
        AND (added_dates is null OR added_dates <= CAST(sprint_start AS TIMESTAMP) OR added_dates >= CAST(sprint_end AS TIMESTAMP )) 
    THEN COALESCE(estimation_start, CAST(estimation AS DOUBLE))
    ELSE 0
    END AS carried_in,
    CASE
    WHEN status_start_category = 'Open'
        AND (added_dates is null OR added_dates <= CAST(sprint_start AS TIMESTAMP) OR added_dates >= CAST(sprint_end AS TIMESTAMP ))
    THEN COALESCE(estimation_start, CAST(estimation AS DOUBLE))
    ELSE 0
    END AS planned,
  CASE
    WHEN status_start_category IN ('Open', 'In Progress') AND added_dates > CAST(sprint_start AS TIMESTAMP) AND added_dates < CAST(sprint_end AS TIMESTAMP) THEN COALESCE(estimation_start, CAST(estimation AS DOUBLE))
    ELSE 0
  END AS unplanned_added,

  CASE
    WHEN estimation_start IS NOT NULL AND estimation_end IS NOT NULL
    THEN estimation_end - estimation_start
    ELSE 0
  END AS estimation_change,

  CASE
    WHEN removed_dates IS NOT NULL THEN -1*COALESCE(estimation_end, estimation_start,  CAST(estimation AS DOUBLE))
    ELSE 0
  END AS removed,

  CASE
    WHEN status_end_category = 'Done' and removed=0 THEN -1*COALESCE(estimation_end, estimation_start,  CAST(estimation AS DOUBLE))
    ELSE 0
  END AS completed,

  CASE
    WHEN removed_dates IS NULL AND status_end_category != 'Done'
    THEN -1*COALESCE(estimation_end, estimation_start,  CAST(estimation AS DOUBLE))
    ELSE 0
  END AS carried_over

FROM joined
WHERE sprint_id IS NOT NULL
ORDER BY sprint_start, sprint_id, issue_key