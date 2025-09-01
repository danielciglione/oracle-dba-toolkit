-- =====================================================================
-- TOP SQL PERFORMANCE ANALYSIS - ENHANCED VERSION
-- Identify Top SQLs from determined period with improved accuracy
-- Author: Daniel Ciglione - July 2025
-- Version: 2.0
-- =====================================================================

-- Configuration Settings
SET PAGESIZE 100
SET LINESIZE 300
SET VERIFY OFF
SET FEEDBACK OFF
SET TIMING OFF

-- Variables for database identification
COLUMN db_name NEW_VALUE db_name
COLUMN instance_name NEW_VALUE instance_name
SELECT name AS db_name FROM v$database;
SELECT instance_name FROM v$instance;

PROMPT =====================================================================
PROMPT              TOP SQL PERFORMANCE ANALYSIS
PROMPT Database: &db_name / Instance: &instance_name
PROMPT =====================================================================
PROMPT
ACCEPT hours_back NUMBER DEFAULT 24 PROMPT 'Enter hours to analyze (default 24): '
ACCEPT top_count NUMBER DEFAULT 20 PROMPT 'Enter number of top SQLs to show (default 20): '

-- Validate input parameters
WHENEVER SQLERROR EXIT SQL.SQLCODE
DECLARE
    v_hours_back NUMBER := &hours_back;
    v_top_count NUMBER := &top_count;
BEGIN
    IF v_hours_back < 1 OR v_hours_back > 168 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Hours must be between 1 and 168 (1 week)');
    END IF;
    IF v_top_count < 1 OR v_top_count > 100 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Top count must be between 1 and 100');
    END IF;
END;
/
WHENEVER SQLERROR CONTINUE

PROMPT
PROMPT =====================================================================
PROMPT 1. TOP SQLs BY ELAPSED TIME (Last &&hours_back hours)
PROMPT =====================================================================

COL rank FORMAT 999
COL sql_id FORMAT A13
COL plan_hash_value FORMAT 9999999999 HEADING 'PLAN_HASH'
COL executions FORMAT 999,999,999
COL avg_elapsed_sec FORMAT 999,999.99
COL total_elapsed_sec FORMAT 9,999,999.99
COL avg_cpu_sec FORMAT 999,999.99
COL cpu_percent FORMAT 999.9 HEADING 'CPU%'
COL avg_buffer_gets FORMAT 999,999,999
COL avg_disk_reads FORMAT 999,999,999
COL sql_text FORMAT A60 WORD_WRAPPED

WITH sql_stats AS (
    SELECT 
        s.sql_id,
        s.plan_hash_value,
        SUM(s.executions_delta) executions,
        SUM(s.elapsed_time_delta) elapsed_time,
        SUM(s.cpu_time_delta) cpu_time,
        SUM(s.buffer_gets_delta) buffer_gets,
        SUM(s.disk_reads_delta) disk_reads,
        MAX(s.module) module
    FROM dba_hist_sqlstat s
    JOIN dba_hist_snapshot sn 
        ON s.snap_id = sn.snap_id
        AND s.dbid = sn.dbid
        AND s.instance_number = sn.instance_number
    WHERE sn.end_interval_time >= SYSDATE - (&&hours_back/24)
      AND s.executions_delta > 0
      AND s.elapsed_time_delta > 0
    GROUP BY s.sql_id, s.plan_hash_value
)
SELECT 
    rank,
    sql_id,
    plan_hash_value,
    executions,
    total_elapsed_sec,
    avg_elapsed_sec,
    avg_cpu_sec,
    cpu_percent,
    avg_buffer_gets,
    avg_disk_reads,
    sql_text
FROM (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY s.elapsed_time DESC) rank,
        s.sql_id,
        s.plan_hash_value,
        s.executions,
        ROUND(s.elapsed_time/1000000, 2) total_elapsed_sec,
        ROUND(s.elapsed_time/NULLIF(s.executions,0)/1000000, 2) avg_elapsed_sec,
        ROUND(s.cpu_time/NULLIF(s.executions,0)/1000000, 2) avg_cpu_sec,
        ROUND(s.cpu_time*100/NULLIF(s.elapsed_time,0), 1) cpu_percent,
        ROUND(s.buffer_gets/NULLIF(s.executions,0), 0) avg_buffer_gets,
        ROUND(s.disk_reads/NULLIF(s.executions,0), 0) avg_disk_reads,
        SUBSTR(REGEXP_REPLACE(st.sql_text, '[[:space:]]+', ' '), 1, 60) sql_text
    FROM sql_stats s
    JOIN dba_hist_sqltext st 
        ON s.sql_id = st.sql_id 
        AND st.dbid = (SELECT dbid FROM v$database)
)
WHERE rank <= &&top_count;

PROMPT
PROMPT =====================================================================
PROMPT 2. TOP SQLs BY CPU TIME (Last &&hours_back hours)
PROMPT =====================================================================

WITH sql_stats AS (
    SELECT 
        s.sql_id,
        s.plan_hash_value,
        SUM(s.executions_delta) executions,
        SUM(s.elapsed_time_delta) elapsed_time,
        SUM(s.cpu_time_delta) cpu_time,
        SUM(s.buffer_gets_delta) buffer_gets,
        MAX(s.module) module
    FROM dba_hist_sqlstat s
    JOIN dba_hist_snapshot sn 
        ON s.snap_id = sn.snap_id
        AND s.dbid = sn.dbid
        AND s.instance_number = sn.instance_number
    WHERE sn.end_interval_time >= SYSDATE - &&hours_back/24
      AND s.executions_delta > 0
      AND s.cpu_time_delta > 0
    GROUP BY s.sql_id, s.plan_hash_value
)
SELECT 
    rank,
    sql_id,
    plan_hash_value,
    executions,
    total_cpu_sec,
    avg_cpu_sec,
    avg_elapsed_sec,
    avg_buffer_gets,
    module,
    sql_text
FROM (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY s.cpu_time DESC) rank,
        s.sql_id,
        s.plan_hash_value,
        s.executions,
        ROUND(s.cpu_time/1000000, 2) total_cpu_sec,
        ROUND(s.cpu_time/NULLIF(s.executions,0)/1000000, 2) avg_cpu_sec,
        ROUND(s.elapsed_time/NULLIF(s.executions,0)/1000000, 2) avg_elapsed_sec,
        ROUND(s.buffer_gets/NULLIF(s.executions,0), 0) avg_buffer_gets,
        s.module,
        SUBSTR(REGEXP_REPLACE(st.sql_text, '[[:space:]]+', ' '), 1, 60) sql_text
    FROM sql_stats s
    JOIN dba_hist_sqltext st 
        ON s.sql_id = st.sql_id 
        AND st.dbid = (SELECT dbid FROM v$database)
)
WHERE rank <= &&top_count;

PROMPT
PROMPT =====================================================================
PROMPT 3. TOP SQLs BY BUFFER GETS (Logical I/O)
PROMPT =====================================================================

WITH sql_stats AS (
    SELECT 
        s.sql_id,
        s.plan_hash_value,
        SUM(s.executions_delta) executions,
        SUM(s.elapsed_time_delta) elapsed_time,
        SUM(s.buffer_gets_delta) buffer_gets,
        SUM(s.disk_reads_delta) disk_reads,
        SUM(s.rows_processed_delta) rows_processed
    FROM dba_hist_sqlstat s
    JOIN dba_hist_snapshot sn 
        ON s.snap_id = sn.snap_id
        AND s.dbid = sn.dbid
        AND s.instance_number = sn.instance_number
    WHERE sn.end_interval_time >= SYSDATE - &&hours_back/24
      AND s.executions_delta > 0
      AND s.buffer_gets_delta > 0
    GROUP BY s.sql_id, s.plan_hash_value
)
SELECT 
    rank,
    sql_id,
    plan_hash_value,
    executions,
    total_buffer_gets,
    avg_buffer_gets,
    gets_per_row,
    avg_elapsed_sec,
    avg_disk_reads,
    sql_text
FROM (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY s.buffer_gets DESC) rank,
        s.sql_id,
        s.plan_hash_value,
        s.executions,
        s.buffer_gets total_buffer_gets,
        ROUND(s.buffer_gets/NULLIF(s.executions,0), 0) avg_buffer_gets,
        ROUND(s.buffer_gets/NULLIF(s.rows_processed,0), 2) gets_per_row,
        ROUND(s.elapsed_time/NULLIF(s.executions,0)/1000000, 2) avg_elapsed_sec,
        ROUND(s.disk_reads/NULLIF(s.executions,0), 0) avg_disk_reads,
        SUBSTR(REGEXP_REPLACE(st.sql_text, '[[:space:]]+', ' '), 1, 60) sql_text
    FROM sql_stats s
    JOIN dba_hist_sqltext st 
        ON s.sql_id = st.sql_id 
        AND st.dbid = (SELECT dbid FROM v$database)
)
WHERE rank <= &&top_count;

PROMPT
PROMPT =====================================================================
PROMPT 4. TOP SQLs BY DISK READS (Physical I/O)
PROMPT =====================================================================

WITH sql_stats AS (
    SELECT 
        s.sql_id,
        s.plan_hash_value,
        SUM(s.executions_delta) executions,
        SUM(s.elapsed_time_delta) elapsed_time,
        SUM(s.buffer_gets_delta) buffer_gets,
        SUM(s.disk_reads_delta) disk_reads,
        SUM(s.physical_read_bytes_delta) phys_read_bytes
    FROM dba_hist_sqlstat s
    JOIN dba_hist_snapshot sn 
        ON s.snap_id = sn.snap_id
        AND s.dbid = sn.dbid
        AND s.instance_number = sn.instance_number
    WHERE sn.end_interval_time >= SYSDATE - &&hours_back/24
      AND s.executions_delta > 0
      AND s.disk_reads_delta > 0
    GROUP BY s.sql_id, s.plan_hash_value
)
SELECT 
    rank,
    sql_id,
    plan_hash_value,
    executions,
    total_disk_reads,
    avg_disk_reads,
    total_mb_read,
    avg_elapsed_sec,
    avg_buffer_gets,
    sql_text
FROM (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY s.disk_reads DESC) rank,
        s.sql_id,
        s.plan_hash_value,
        s.executions,
        s.disk_reads total_disk_reads,
        ROUND(s.disk_reads/NULLIF(s.executions,0), 0) avg_disk_reads,
        ROUND(s.phys_read_bytes/1024/1024, 2) total_mb_read,
        ROUND(s.elapsed_time/NULLIF(s.executions,0)/1000000, 2) avg_elapsed_sec,
        ROUND(s.buffer_gets/NULLIF(s.executions,0), 0) avg_buffer_gets,
        SUBSTR(REGEXP_REPLACE(st.sql_text, '[[:space:]]+', ' '), 1, 60) sql_text
    FROM sql_stats s
    JOIN dba_hist_sqltext st 
        ON s.sql_id = st.sql_id 
        AND st.dbid = (SELECT dbid FROM v$database)
)
WHERE rank <= &&top_count;

PROMPT
PROMPT =====================================================================
PROMPT 5. CURRENTLY ACTIVE CPU CONSUMING SESSIONS
PROMPT =====================================================================

COL program FORMAT A25 TRUNCATE
COL event FORMAT A30 TRUNCATE
COL cpu_usage_sec FORMAT 999,990
COL wait_time_sec FORMAT 999,990
COL module FORMAT A18 TRUNCATE
COL osuser FORMAT A10 TRUNCATE
COL username FORMAT A15
COL ospid FORMAT A8
COL sid FORMAT 99999
COL serial# FORMAT 999999
COL sql_id FORMAT A13
COL blocking_session FORMAT 99999 HEADING 'BLKNG_SID'

SELECT 
    ospid,
    sid,
    serial#,
    sql_id,
    username,
    program,
    module,
    osuser,
    status,
    event,
    blocking_session,
    cpu_usage_sec,
    wait_time_sec
FROM (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY se.value DESC) rank,
        p.spid ospid,
        s.sid,
        s.serial#,
        s.sql_id,
        s.username,
        SUBSTR(s.program,1,25) program,
        s.module,
        s.osuser,
        s.status,
        s.event,
        s.blocking_session,
        se.value/100 cpu_usage_sec,
        s.seconds_in_wait wait_time_sec
    FROM v$session s
    JOIN v$sesstat se ON se.sid = s.sid
    JOIN v$statname sn ON se.statistic# = sn.statistic#
    JOIN v$process p ON s.paddr = p.addr
    WHERE sn.name = 'CPU used by this session'
      AND s.username NOT IN ('SYS', 'SYSTEM', 'DBSNMP', 'SYSMAN')
      AND s.status = 'ACTIVE'
      AND s.type = 'USER'
      AND se.value > 100  -- At least 1 second of CPU
)
WHERE rank <= 20;

PROMPT
PROMPT =====================================================================
PROMPT 6. LONG RUNNING OPERATIONS (Active and Idle Sessions)
PROMPT =====================================================================

COL username FORMAT A15
COL sid FORMAT 99999
COL status FORMAT A8
COL logon FORMAT A17
COL idle FORMAT A12
COL program FORMAT A25 TRUNCATE
COL sql_exec_start FORMAT A17
COL current_sql FORMAT A13 HEADING 'CURRENT_SQL'

SELECT * FROM (
    SELECT 
        sid,
        username,
        status,
        TO_CHAR(logon_time,'DD-MON HH24:MI:SS') logon,
        CASE 
            WHEN status = 'ACTIVE' THEN 'ACTIVE'
            ELSE LPAD(FLOOR(last_call_et/3600),3)||':'||
                 LPAD(FLOOR(MOD(last_call_et,3600)/60),2,'0')||':'||
                 LPAD(MOD(MOD(last_call_et,3600),60),2,'0')
        END idle,
        sql_id current_sql,
        TO_CHAR(sql_exec_start,'DD-MON HH24:MI:SS') sql_exec_start,
        SUBSTR(program, 1, 25) program
    FROM v$session
    WHERE type = 'USER'
      AND username IS NOT NULL
      AND (last_call_et > 3600 OR status = 'ACTIVE')  -- Idle > 1hr or Active
    ORDER BY 
        CASE WHEN status = 'ACTIVE' THEN 0 ELSE 1 END,
        last_call_et DESC
) WHERE ROWNUM <= 30;

PROMPT
PROMPT =====================================================================
PROMPT 7. EXECUTION PLAN FOR SPECIFIC SQL_ID (Interactive)
PROMPT =====================================================================
PROMPT
ACCEPT show_plan CHAR DEFAULT 'N' PROMPT 'Show execution plan for a specific SQL_ID? [Y/N] (default N): '

-- Only prompt for SQL_ID if user wants to see plan
ACCEPT plan_sql_id CHAR PROMPT 'Enter SQL_ID for execution plan (or press ENTER to skip): '

-- Display execution plan if SQL_ID provided
PROMPT
PROMPT =====================================================================
PROMPT EXECUTION PLAN ANALYSIS
PROMPT =====================================================================

-- Simple conditional execution
SET PAGESIZE 1000
SET LINESIZE 150

BEGIN
    IF '&plan_sql_id' IS NOT NULL AND LENGTH('&plan_sql_id') > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Showing execution plan for SQL_ID: &plan_sql_id');
        DBMS_OUTPUT.PUT_LINE('=====================================================================');
    ELSE
        DBMS_OUTPUT.PUT_LINE('No SQL_ID provided - skipping execution plan analysis');
    END IF;
END;
/

-- Execute DBMS_XPLAN if SQL_ID provided
SELECT * FROM table(DBMS_XPLAN.DISPLAY_AWR('&plan_sql_id'))
WHERE '&plan_sql_id' IS NOT NULL AND LENGTH('&plan_sql_id') > 0;

PROMPT
-- Set date and time variables for report generation
COLUMN report_date NEW_VALUE report_date
COLUMN report_time NEW_VALUE report_time
SELECT TO_CHAR(SYSDATE, 'DD-MON-YYYY') AS report_date, 
       TO_CHAR(SYSDATE, 'HH24:MI:SS') AS report_time 
FROM dual;
PROMPT =====================================================================
PROMPT              ANALYSIS COMPLETE - Generated: &&report_date &&report_time
PROMPT =====================================================================

-- Reset settings
SET FEEDBACK ON
SET VERIFY ON
SET TIMING ON