-- ================================================================
-- AWR WAIT EVENTS ANALYSIS SCRIPT
-- ================================================================
-- Author: Daniel Ciglione - June 2025
-- Description: This script analyzes wait events in Oracle AWR.
-- It allows filtering by time period, instance, and specific events.
-- Usage: Execute in SQL*Plus or compatible Oracle SQL client.
-- Note: Requires access to dba_hist_snapshot and dba_hist_system_event views.
-- Version: Compatible with Oracle 11g and later
-- Compatibility: RAC and Standalone environments
-- ================================================================

-- ================================================================
-- FILTER TYPE REFERENCE
-- 1 = Last N days from current time (rolling N*24 hours backward)
-- 2 = Specific date range (start_date to end_date)  
-- 3 = Snapshot ID range (start_snap to end_snap)
-- ================================================================

-- Set SQL*Plus environment variables for better output
SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING ON
SET PAGESIZE 1000
SET LINESIZE 150
SET TRIMSPOOL ON
SET TRIMOUT ON

-- Column definitions for formatting
col instance_number for 999 heading "Inst"
col snap_id for 99999999 heading "Snap ID"
col snap_time for a20 heading "Snapshot Time"
col event_name for a40 heading "Wait Event"
col total_waits for 999,999,999,999 heading "Total Waits"
col time_waited_sec for 999,999,999.99 heading "Time Waited (s)"
col avg_wait_ms for 9,999.99 heading "Avg Wait (ms)"
col waits_per_sec for 999,999.99 heading "Waits/Sec"
col pct_total_time for 999.99 heading "% Total Time"

-- Prompt for filter type
prompt 
prompt ================================================================
prompt AWR WAIT EVENTS ANALYSIS
prompt ================================================================
prompt 
prompt Choose filter type:
prompt [1] - Last N days (analyze recent performance)
prompt [2] - Specific date range (historical analysis)
prompt [3] - Snapshot ID range (precise AWR selection)
prompt 
accept filter_type number prompt 'Enter your option (1, 2 or 3): '

-- Validate and override if invalid, keeping same variable name
column filter_type new_value filter_type noprint

SELECT 
  CASE 
    WHEN &&filter_type BETWEEN 1 AND 3 THEN &&filter_type
    ELSE 2
  END as filter_type
FROM dual;

SELECT 
  CASE 
    WHEN &&filter_type = 1 THEN 'Selected: Last N days analysis'
    WHEN &&filter_type = 2 THEN 'Selected: Date range analysis'  
    WHEN &&filter_type = 3 THEN 'Selected: Snapshot range analysis'
  END as filter_status
FROM dual;

-- ================================================================
-- CONTEXTUAL INPUT COLLECTION
-- ================================================================

-- Show user what inputs they need based on their choice
SELECT 
  CASE &&filter_type
    WHEN 1 THEN 
      'LAST N DAYS ANALYSIS - You need: Number of days to analyze'
    WHEN 2 THEN
      'DATE RANGE ANALYSIS - You need: Start and end dates'  
    WHEN 3 THEN
      'SNAPSHOT RANGE ANALYSIS - You need: Snapshot ID range'
  END as input_guide
FROM dual;

prompt 
prompt ================================================================
prompt INPUT COLLECTION
prompt ================================================================

-- For days filter (only relevant when filter_type = 1)
accept days_back number default 1 prompt 'How many days back (ignore if not using Last N Days): ' 

prompt 
prompt Valid date formats (ignore if not using Date Range):
prompt   Date only: DD-MON-YYYY (e.g., 15-JAN-2024, 31-DEC-2023)
prompt   Date+Time: DD-MON-YYYY HH24:MI:SS (e.g., 15-JAN-2024 14:30:00)
prompt Valid months: JAN, FEB, MAR, APR, MAY, JUN, JUL, AUG, SEP, OCT, NOV, DEC
prompt 

-- For date filter (only relevant when filter_type = 2)
accept start_date char default '01-JAN-2024' prompt 'Start date (ignore if not using Date Range): '
accept end_date char default '31-DEC-2024' prompt 'End date (ignore if not using Date Range): '

-- ================================================================
-- DATE VALIDATION (only processed when filter_type = 2)
-- ================================================================

-- Date regex pattern for maintainability
DEFINE date_regex = '^(0[1-9]|[12][0-9]|3[01])-(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)-[0-9]{4}( (0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9])?$'

-- Enhanced validation with clear messaging
column validation_status new_value validation_status noprint
column continue_script new_value continue_script noprint

SELECT 
  CASE 
    WHEN &&filter_type != 2 THEN 'SKIP_DATE_VALIDATION'  -- Skip validation for non-date filters
    WHEN NOT REGEXP_LIKE('&&start_date', '&&date_regex') THEN
      'INVALID_START_DATE'
    WHEN NOT REGEXP_LIKE('&&end_date', '&&date_regex') THEN  
      'INVALID_END_DATE'
    ELSE 
      'VALID'
  END as validation_status,
  CASE 
    WHEN &&filter_type != 2 THEN 'YES'  -- Always continue for non-date filters
    WHEN REGEXP_LIKE('&&start_date', '&&date_regex') AND
         REGEXP_LIKE('&&end_date', '&&date_regex') THEN
      'YES'
    ELSE 
      'NO'
  END as continue_script
FROM dual;

-- Show validation results only for date range filter
SELECT 
  CASE 
    WHEN &&filter_type != 2 THEN 'Date validation skipped (not using Date Range filter)'
    WHEN '&&validation_status' = 'INVALID_START_DATE' THEN 
      'INVALID START DATE: [&&start_date]' || CHR(10) ||
      '   Use format: DD-MON-YYYY or DD-MON-YYYY HH24:MI:SS' || CHR(10) ||
      '   Examples: 15-JAN-2024, 31-DEC-2024 23:59:59'
    WHEN '&&validation_status' = 'INVALID_END_DATE' THEN
      'INVALID END DATE: [&&end_date]' || CHR(10) ||
      '   Use format: DD-MON-YYYY or DD-MON-YYYY HH24:MI:SS' || CHR(10) ||
      '   Examples: 15-JAN-2024, 31-DEC-2024 23:59:59'
    WHEN '&&validation_status' = 'VALID' THEN
      'Date validation successful'
    ELSE
      'Unknown validation state'
  END as validation_result
FROM dual;

-- Smart date parsing (only when using date range filter)
column parsed_start_date new_value parsed_start_date noprint
column parsed_end_date new_value parsed_end_date noprint

SELECT 
  CASE 
    WHEN &&filter_type != 2 THEN 'NOT_USED'  -- Default for non-date filters
    WHEN LENGTH(TRIM('&&start_date')) <= 11 THEN 
      TO_CHAR(TO_DATE('&&start_date', 'DD-MON-YYYY'), 'DD-MON-YYYY HH24:MI:SS')
    ELSE 
      TO_CHAR(TO_DATE('&&start_date', 'DD-MON-YYYY HH24:MI:SS'), 'DD-MON-YYYY HH24:MI:SS')
  END as parsed_start_date,
  CASE 
    WHEN &&filter_type != 2 THEN 'NOT_USED'  -- Default for non-date filters
    WHEN LENGTH(TRIM('&&end_date')) <= 11 THEN 
      TO_CHAR(TO_DATE('&&end_date', 'DD-MON-YYYY') + (86399/86400), 'DD-MON-YYYY HH24:MI:SS')
    ELSE 
      TO_CHAR(TO_DATE('&&end_date', 'DD-MON-YYYY HH24:MI:SS'), 'DD-MON-YYYY HH24:MI:SS')
  END as parsed_end_date
FROM dual;

-- For snapshot filter (only relevant when filter_type = 3)
accept start_snap number default 1 prompt 'Starting Snapshot ID (ignore if not using Snapshot Range): '
accept end_snap number default 999999 prompt 'Ending Snapshot ID (ignore if not using Snapshot Range): '

-- Show what will actually be used
SELECT 
  CASE &&filter_type
    WHEN 1 THEN 'Will analyze last &&days_back days'
    WHEN 2 THEN 'Will analyze from &&start_date to &&end_date'
    WHEN 3 THEN 'Will analyze snapshots &&start_snap to &&end_snap'
  END as final_configuration
FROM dual;

prompt

-- Instance filter
accept instance_filter number default 0 prompt 'Instance number (0 for all): '

prompt 
prompt ================================================================
prompt EVENT FILTER OPTIONS
prompt ================================================================
prompt Common events:
prompt - db file sequential read     - log file parallel write
prompt - db file scattered read      - direct path write
prompt - gc buffer busy acquire      - enq: HW - contention
prompt 
prompt Filter rules:
prompt  'ALL' - Analyze all wait events
prompt  Exact name - Match specific event (e.g., 'db file sequential read')
prompt  3+ characters - Pattern matching (e.g., 'read' matches all read events)
prompt  1-2 characters - Exact match only (e.g., 'gc' matches only event named 'gc')
prompt 
prompt Examples:
prompt   'log' → finds log file parallel write, log file sync, etc.
prompt   'read' → finds db file sequential read, scattered read, etc.
prompt   'gc' → finds only exact event named 'gc' (use 'gc ' for pattern)
prompt 
accept event_filter char default 'ALL' prompt 'Event filter [ALL/exact name/3+ chars for pattern]: '

-- Grouping option
prompt 
prompt Grouping options:
prompt 1 - By snapshot (detailed)
prompt 2 - Summary by event
prompt 3 - Summary by hour
prompt 
accept group_option number default 2 prompt 'Choose grouping option (1, 2 or 3): '

prompt 
prompt Running analysis...
prompt 

-- ================================================================
-- UNIFIED CTE STRUCTURE - All CTEs in single WITH clause
-- ================================================================

WITH snapshot_range AS (
  SELECT DISTINCT 
    s.snap_id,
    s.dbid,
    s.instance_number,
    s.begin_interval_time,
    s.end_interval_time,
    EXTRACT(DAY FROM (s.end_interval_time - s.begin_interval_time)) * 86400 +
    EXTRACT(HOUR FROM (s.end_interval_time - s.begin_interval_time)) * 3600 +
    EXTRACT(MINUTE FROM (s.end_interval_time - s.begin_interval_time)) * 60 +
    EXTRACT(SECOND FROM (s.end_interval_time - s.begin_interval_time)) as interval_seconds
  FROM dba_hist_snapshot s
  WHERE 1=1
    -- Filter by selected type
    AND (
      -- Filter Type 1: Last N days
      (&&filter_type = 1 AND s.end_interval_time >= SYSDATE - &&days_back) OR
      -- Filter Type 2: Specific date range
      (&&filter_type = 2 AND s.end_interval_time BETWEEN 
        TO_DATE('&&parsed_start_date', 'DD-MON-YYYY HH24:MI:SS') AND 
        TO_DATE('&&parsed_end_date', 'DD-MON-YYYY HH24:MI:SS')) OR
      -- Filter Type 3: Snapshot ID range  
      (&&filter_type = 3 AND s.snap_id BETWEEN &&start_snap AND &&end_snap)
    )
    -- Instance filter
    AND (&&instance_filter = 0 OR s.instance_number = &&instance_filter)
),
wait_events_delta AS (
  SELECT 
    sr.snap_id,
    sr.instance_number,
    sr.begin_interval_time,
    sr.end_interval_time,
    sr.interval_seconds,
    se.event_name,
    se.total_waits - LAG(se.total_waits) OVER (
      PARTITION BY se.event_name, se.instance_number 
      ORDER BY se.snap_id
    ) as waits_delta,
    (se.time_waited_micro - LAG(se.time_waited_micro) OVER (
      PARTITION BY se.event_name, se.instance_number 
      ORDER BY se.snap_id
    )) / 1000000 as time_waited_delta_sec
  FROM dba_hist_system_event se
  JOIN snapshot_range sr ON (
    se.snap_id = sr.snap_id AND 
    se.dbid = sr.dbid AND 
    se.instance_number = sr.instance_number
  )
  WHERE 1=1
    -- Enhanced event filtering with exact match and pattern matching
    AND (
      UPPER('&&event_filter') = 'ALL' OR 
      (
        -- Allow exact match always
        UPPER(se.event_name) = UPPER('&&event_filter') OR
        -- Pattern matching with minimum length to prevent overly broad results
        (
          UPPER(se.event_name) LIKE UPPER('%&&event_filter%') AND
          LENGTH(TRIM('&&event_filter')) >= 3
        )
      )
    )
    -- Exclude idle events
    AND se.event_name NOT IN (
      'SQL*Net message from client',
      'SQL*Net message to client', 
      'rdbms ipc message',
      'smon timer',
      'pmon timer',
      'Streams AQ: waiting for time',
      'wait for unread message on broadcast channel'
    )
),
event_stats AS (
  SELECT 
    snap_id,
    instance_number,
    begin_interval_time,
    end_interval_time,
    interval_seconds,
    event_name,
    waits_delta as total_waits,
    time_waited_delta_sec as time_waited_sec,
    CASE 
      WHEN waits_delta > 0 THEN 
        (time_waited_delta_sec * 1000) / waits_delta 
      ELSE 0 
    END as avg_wait_ms,
    CASE 
      WHEN interval_seconds > 0 THEN 
        waits_delta / interval_seconds 
      ELSE 0 
    END as waits_per_sec
  FROM wait_events_delta
  WHERE waits_delta > 0 
    AND time_waited_delta_sec > 0
),
-- Conditional aggregations that only process when needed
snapshot_detail AS (
  SELECT 
    instance_number,
    snap_id,
    end_interval_time,
    event_name,
    total_waits,
    time_waited_sec,
    avg_wait_ms,
    waits_per_sec
  FROM event_stats
  WHERE &&group_option = 1 
    AND time_waited_sec >= 0.01
),
snapshot_total AS (
  SELECT SUM(time_waited_sec) AS total_time_waited_sec 
  FROM snapshot_detail
),
event_summary AS (
  SELECT 
    event_name,
    SUM(total_waits) as total_waits,
    SUM(time_waited_sec) as time_waited_sec,
    SUM(time_waited_sec * 1000) as total_time_waited_ms,
    SUM(interval_seconds) as total_interval_seconds
  FROM event_stats
  WHERE &&group_option = 2
    AND time_waited_sec >= 0.01
  GROUP BY event_name
),
event_summary_total AS (
  SELECT SUM(time_waited_sec) as grand_total_time_sec
  FROM event_summary
),
hourly_summary AS (
  SELECT
    TRUNC(end_interval_time, 'HH24') AS hour_time,
    event_name,
    SUM(total_waits) AS total_waits,
    SUM(time_waited_sec) AS time_waited_sec,
    SUM(time_waited_sec * 1000) AS total_time_waited_ms,
    SUM(interval_seconds) AS total_interval_seconds
  FROM event_stats
  WHERE &&group_option = 3
    AND time_waited_sec >= 0.01
  GROUP BY TRUNC(end_interval_time, 'HH24'), event_name
),
hourly_totals AS (
  SELECT
    hour_time,
    SUM(time_waited_sec) AS hour_total_time_sec
  FROM hourly_summary
  GROUP BY hour_time
)
-- Single query with conditional output
SELECT 
  instance_number,
  snap_id,
  snap_time,
  event_name,
  total_waits,
  time_waited_sec,
  avg_wait_ms,
  waits_per_sec,
  pct_total_time
FROM (
  SELECT 
    sd.instance_number,
    sd.snap_id,
    TO_CHAR(sd.end_interval_time, 'DD/MM/YY HH24:MI') as snap_time,
    sd.event_name,
    sd.total_waits,
    ROUND(sd.time_waited_sec, 2) as time_waited_sec,
    ROUND(sd.avg_wait_ms, 2) as avg_wait_ms,
    ROUND(sd.waits_per_sec, 2) as waits_per_sec,
    ROUND(100 * sd.time_waited_sec / NULLIF(st.total_time_waited_sec, 0), 2) as pct_total_time,
    sd.snap_id as sort1,
    sd.time_waited_sec as sort2,
    1 as query_type
  FROM snapshot_detail sd
  CROSS JOIN snapshot_total st
  WHERE &&group_option = 1
  UNION ALL
  SELECT 
    NULL as instance_number,
    NULL as snap_id,
    'TOTAL' as snap_time,
    es.event_name,
    es.total_waits,
    ROUND(es.time_waited_sec, 2) as time_waited_sec,
    COALESCE(ROUND(es.total_time_waited_ms / NULLIF(es.total_waits, 0), 2), 0) as avg_wait_ms,
    ROUND(es.total_waits / NULLIF(es.total_interval_seconds, 0), 2) as waits_per_sec,
    ROUND(100 * es.time_waited_sec / NULLIF(est.grand_total_time_sec, 0), 2) as pct_total_time,
    0 as sort1,
    es.time_waited_sec as sort2,
    2 as query_type
  FROM event_summary es
  CROSS JOIN event_summary_total est
  WHERE &&group_option = 2
  UNION ALL
  SELECT 
    NULL as instance_number,
    NULL as snap_id,
    TO_CHAR(hs.hour_time, 'DD/MM/YY HH24')||':00' as snap_time,
    hs.event_name,
    hs.total_waits,
    ROUND(hs.time_waited_sec, 2) as time_waited_sec,
    COALESCE(ROUND(hs.total_time_waited_ms / NULLIF(hs.total_waits, 0), 2), 0) as avg_wait_ms,
    ROUND(hs.total_waits / NULLIF(hs.total_interval_seconds, 0), 2) as waits_per_sec,
    ROUND(100 * hs.time_waited_sec / NULLIF(ht.hour_total_time_sec, 0), 2) as pct_total_time,
    TO_NUMBER(TO_CHAR(hs.hour_time, 'HH24')) as sort1,
    hs.time_waited_sec as sort2,
    3 as query_type
  FROM hourly_summary hs
  JOIN hourly_totals ht ON hs.hour_time = ht.hour_time
  WHERE &&group_option = 3
)
ORDER BY 
  query_type,
  sort1,
  sort2 DESC;

-- Final summary
prompt 
prompt ================================================================
prompt ANALYSIS SUMMARY
prompt ================================================================

WITH snapshot_range AS (
  SELECT DISTINCT 
    s.snap_id,
    s.dbid,
    s.instance_number,
    s.begin_interval_time,
    s.end_interval_time,
    EXTRACT(DAY FROM (s.end_interval_time - s.begin_interval_time)) * 86400 +
    EXTRACT(HOUR FROM (s.end_interval_time - s.begin_interval_time)) * 3600 +
    EXTRACT(MINUTE FROM (s.end_interval_time - s.begin_interval_time)) * 60 +
    EXTRACT(SECOND FROM (s.end_interval_time - s.begin_interval_time)) as interval_seconds
  FROM dba_hist_snapshot s
  WHERE 1=1
    AND (
      (&&filter_type = 1 AND s.end_interval_time >= SYSDATE - &&days_back) OR
      (&&filter_type = 2 AND s.end_interval_time BETWEEN 
        TO_DATE('&&parsed_start_date', 'DD-MON-YYYY HH24:MI:SS') AND 
        TO_DATE('&&parsed_end_date', 'DD-MON-YYYY HH24:MI:SS')) OR
      (&&filter_type = 3 AND s.snap_id BETWEEN &&start_snap AND &&end_snap)
    )
    AND (&&instance_filter = 0 OR s.instance_number = &&instance_filter)
),
wait_events_delta AS (
  SELECT 
    sr.snap_id,
    sr.instance_number,
    sr.begin_interval_time,
    sr.end_interval_time,
    sr.interval_seconds,
    se.event_name,
    se.total_waits - LAG(se.total_waits) OVER (
      PARTITION BY se.event_name, se.instance_number 
      ORDER BY se.snap_id
    ) as waits_delta,
    (se.time_waited_micro - LAG(se.time_waited_micro) OVER (
      PARTITION BY se.event_name, se.instance_number 
      ORDER BY se.snap_id
    )) / 1000000 as time_waited_delta_sec
  FROM dba_hist_system_event se
  JOIN snapshot_range sr ON (
    se.snap_id = sr.snap_id AND 
    se.dbid = sr.dbid AND 
    se.instance_number = sr.instance_number
  )
  WHERE 1=1
    AND (
      UPPER('&&event_filter') = 'ALL' OR 
      (
        UPPER(se.event_name) = UPPER('&&event_filter') OR
        (
          UPPER(se.event_name) LIKE UPPER('%&&event_filter%') AND
          LENGTH(TRIM('&&event_filter')) >= 3
        )
      )
    )
    AND se.event_name NOT IN (
      'SQL*Net message from client',
      'SQL*Net message to client', 
      'rdbms ipc message',
      'smon timer',
      'pmon timer',
      'Streams AQ: waiting for time',
      'wait for unread message on broadcast channel'
    )
),
event_stats AS (
  SELECT 
    snap_id,
    instance_number,
    begin_interval_time,
    end_interval_time,
    interval_seconds,
    event_name,
    waits_delta as total_waits,
    time_waited_delta_sec as time_waited_sec,
    CASE 
      WHEN waits_delta > 0 THEN 
        (time_waited_delta_sec * 1000) / waits_delta 
      ELSE 0 
    END as avg_wait_ms,
    CASE 
      WHEN interval_seconds > 0 THEN 
        waits_delta / interval_seconds 
      ELSE 0 
    END as waits_per_sec
  FROM wait_events_delta
  WHERE waits_delta > 0 
    AND time_waited_delta_sec > 0
)
SELECT 
  'Analysis Period' as metric,
  TO_CHAR(MIN(begin_interval_time), 'DD/MM/YYYY HH24:MI') || ' to ' ||
  TO_CHAR(MAX(end_interval_time), 'DD/MM/YYYY HH24:MI') as value
FROM event_stats
UNION ALL
SELECT 
  'Total Snapshots',
  COUNT(DISTINCT snap_id)||''
FROM event_stats  
UNION ALL
SELECT 
  'Instances Analyzed',
  COUNT(DISTINCT instance_number)||''
FROM event_stats
UNION ALL
SELECT 
  'Unique Events',
  COUNT(DISTINCT event_name)||''
FROM event_stats
UNION ALL
SELECT 
  'Total Wait Time (s)',
  TO_CHAR(ROUND(SUM(time_waited_sec), 2), '999,999,999.99')
FROM event_stats
UNION ALL
SELECT 
  'Total Waits',
  TO_CHAR(SUM(total_waits), '999,999,999,999')
FROM event_stats;

prompt 
prompt ================================================================
prompt TOP 10 EVENTS BY WAIT TIME
prompt ================================================================

col rank for 999 heading "Rank"

WITH snapshot_range AS (
  SELECT DISTINCT 
    s.snap_id,
    s.dbid,
    s.instance_number,
    s.begin_interval_time,
    s.end_interval_time,
    EXTRACT(DAY FROM (s.end_interval_time - s.begin_interval_time)) * 86400 +
    EXTRACT(HOUR FROM (s.end_interval_time - s.begin_interval_time)) * 3600 +
    EXTRACT(MINUTE FROM (s.end_interval_time - s.begin_interval_time)) * 60 +
    EXTRACT(SECOND FROM (s.end_interval_time - s.begin_interval_time)) as interval_seconds
  FROM dba_hist_snapshot s
  WHERE 1=1
    AND (
      (&&filter_type = 1 AND s.end_interval_time >= SYSDATE - &&days_back) OR
      (&&filter_type = 2 AND s.end_interval_time BETWEEN 
        TO_DATE('&&parsed_start_date', 'DD-MON-YYYY HH24:MI:SS') AND 
        TO_DATE('&&parsed_end_date', 'DD-MON-YYYY HH24:MI:SS')) OR
      (&&filter_type = 3 AND s.snap_id BETWEEN &&start_snap AND &&end_snap)
    )
    AND (&&instance_filter = 0 OR s.instance_number = &&instance_filter)
),
wait_events_delta AS (
  SELECT 
    sr.snap_id,
    sr.instance_number,
    sr.begin_interval_time,
    sr.end_interval_time,
    sr.interval_seconds,
    se.event_name,
    se.total_waits - LAG(se.total_waits) OVER (
      PARTITION BY se.event_name, se.instance_number 
      ORDER BY se.snap_id
    ) as waits_delta,
    (se.time_waited_micro - LAG(se.time_waited_micro) OVER (
      PARTITION BY se.event_name, se.instance_number 
      ORDER BY se.snap_id
    )) / 1000000 as time_waited_delta_sec
  FROM dba_hist_system_event se
  JOIN snapshot_range sr ON (
    se.snap_id = sr.snap_id AND 
    se.dbid = sr.dbid AND 
    se.instance_number = sr.instance_number
  )
  WHERE 1=1
    AND (
      UPPER('&&event_filter') = 'ALL' OR 
      (
        UPPER(se.event_name) = UPPER('&&event_filter') OR
        (
          UPPER(se.event_name) LIKE UPPER('%&&event_filter%') AND
          LENGTH(TRIM('&&event_filter')) >= 3
        )
      )
    )
    AND se.event_name NOT IN (
      'SQL*Net message from client',
      'SQL*Net message to client', 
      'rdbms ipc message',
      'smon timer',
      'pmon timer',
      'Streams AQ: waiting for time',
      'wait for unread message on broadcast channel'
    )
),
event_stats AS (
  SELECT 
    snap_id,
    instance_number,
    begin_interval_time,
    end_interval_time,
    interval_seconds,
    event_name,
    waits_delta as total_waits,
    time_waited_delta_sec as time_waited_sec,
    CASE 
      WHEN waits_delta > 0 THEN 
        (time_waited_delta_sec * 1000) / waits_delta 
      ELSE 0 
    END as avg_wait_ms,
    CASE 
      WHEN interval_seconds > 0 THEN 
        waits_delta / interval_seconds 
      ELSE 0 
    END as waits_per_sec
  FROM wait_events_delta
  WHERE waits_delta > 0 
    AND time_waited_delta_sec > 0
),
event_agg AS (
  SELECT
    event_name,
    SUM(total_waits) AS total_waits,
    SUM(time_waited_sec) AS time_waited_sec,
    SUM(time_waited_sec * 1000) AS total_time_waited_ms
  FROM event_stats
  GROUP BY event_name
)
SELECT * FROM (
  SELECT 
    ROW_NUMBER() OVER (ORDER BY ea.time_waited_sec DESC) as rank,
    ea.event_name,
    ROUND(ea.time_waited_sec, 2) as total_time_sec,
    ea.total_waits,
    COALESCE(ROUND(ea.total_time_waited_ms / NULLIF(ea.total_waits, 0), 2), 0) as avg_wait_ms,
    ROUND(100 * ea.time_waited_sec / NULLIF((SELECT SUM(time_waited_sec) FROM event_agg), 0), 2) as pct_total
  FROM event_agg ea
)
WHERE rank <= 10;

prompt 
prompt ================================================================
prompt Analysis completed! Restoring session settings...
prompt ================================================================

-- Cleanup defined variables
UNDEFINE date_regex
UNDEFINE filter_type
UNDEFINE days_back
UNDEFINE start_date
UNDEFINE end_date
UNDEFINE start_snap
UNDEFINE end_snap
UNDEFINE instance_filter
UNDEFINE event_filter
UNDEFINE group_option

-- Restore SQL*Plus defaults
SET VERIFY ON
SET FEEDBACK ON
SET HEADING ON
SET PAGESIZE 14
SET LINESIZE 80
SET TRIMSPOOL OFF
SET TRIMOUT OFF

prompt Script completed successfully.
prompt Session ready for next operations.

SET ECHO ON