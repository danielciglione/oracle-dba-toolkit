-- =====================================================
-- Oracle Database Health Check Script
-- Version: 3.1 for Oracle 19c+ (Standalone & RAC)
-- Purpose: Comprehensive database health assessment
-- Safety: READ-ONLY operations only (no DDL/DML)
-- Author: Daniel Ciglione - June 2025
-- =====================================================

SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING ON
SET PAGESIZE 2000
SET LINESIZE 200
SET TRIMSPOOL ON
SET TRIMOUT ON
SET SERVEROUTPUT ON

-- Detect if this is a RAC environment
COLUMN is_rac NEW_VALUE v_is_rac
SELECT CASE WHEN COUNT(*) > 1 THEN 'TRUE' ELSE 'FALSE' END as is_rac 
FROM gv$instance;

-- Store instance count
COLUMN inst_count NEW_VALUE v_inst_count
SELECT COUNT(*) as inst_count FROM gv$instance;

-- Generate timestamp for report
COLUMN current_time NEW_VALUE report_time
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD_HH24-MI-SS') current_time FROM dual;

-- Start spooling to file
SPOOL healthcheck_&report_time..txt

PROMPT =====================================================
PROMPT     ORACLE DATABASE HEALTH CHECK REPORT
PROMPT =====================================================
PROMPT
SELECT 'Report Generated: ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI:SS') as report_info FROM dual;
PROMPT

-- =====================================================
-- 1. DATABASE OVERVIEW
-- =====================================================
PROMPT =====================================================
PROMPT 1. DATABASE OVERVIEW
PROMPT =====================================================
PROMPT

-- Show cluster information - CORRECTED: Using proper PL/SQL variables
DECLARE
    v_is_rac VARCHAR2(5);
    v_inst_count NUMBER;
BEGIN
    SELECT CASE WHEN COUNT(*) > 1 THEN 'TRUE' ELSE 'FALSE' END, COUNT(*) 
    INTO v_is_rac, v_inst_count 
    FROM gv$instance;
    
    IF v_is_rac = 'TRUE' THEN
        DBMS_OUTPUT.PUT_LINE('** RAC ENVIRONMENT DETECTED - ' || v_inst_count || ' instances **');
    ELSE
        DBMS_OUTPUT.PUT_LINE('** STANDALONE ENVIRONMENT **');
    END IF;
END;
/

COLUMN db_name FORMAT A15
COLUMN platform_name FORMAT A30
COLUMN version FORMAT A20
COLUMN startup_time FORMAT A20
COLUMN database_role FORMAT A15
COLUMN open_mode FORMAT A15
COLUMN log_mode FORMAT A15
COLUMN inst_id FORMAT 99
COLUMN instance_name FORMAT A15
COLUMN host_name FORMAT A20
COLUMN status FORMAT A15

-- For RAC, show all instances; for standalone, show single instance
SELECT 
    d.name as db_name,
    i.inst_id,
    i.instance_name,
    i.host_name,
    i.status,
    d.platform_name,
    i.version,
    TO_CHAR(i.startup_time, 'DD-MON-YY HH24:MI') as startup_time,
    d.database_role,
    d.open_mode,
    d.log_mode
FROM v$database d
CROSS JOIN gv$instance i
ORDER BY i.inst_id;

PROMPT
PROMPT Database Uptime by Instance:
SELECT 
    inst_id,
    instance_name,
    ROUND((SYSDATE - startup_time)) || ' days, ' ||
    ROUND(24*((SYSDATE - startup_time) - ROUND(SYSDATE - startup_time))) || ' hours' as uptime
FROM gv$instance
ORDER BY inst_id;

-- =====================================================
-- 2. INSTANCE CONFIGURATION
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 2. INSTANCE CONFIGURATION
PROMPT =====================================================
PROMPT

COLUMN parameter FORMAT A30
COLUMN value FORMAT A40
COLUMN description FORMAT A50

PROMPT Key Instance Parameters (All Instances):
SELECT 
    inst_id,
    name as parameter,
    value,
    SUBSTR(description, 1, 50) as description
FROM gv$parameter 
WHERE name IN (
    'memory_target', 'memory_max_target', 'sga_target', 'sga_max_size',
    'pga_aggregate_target', 'processes', 'sessions', 'cpu_count',
    'db_cache_size', 'shared_pool_size', 'large_pool_size',
    'log_buffer', 'db_writer_processes', 'log_archive_dest_1',
    'cluster_database', 'instance_number', 'thread'
)
ORDER BY inst_id, name;

-- RAC-specific configuration - CORRECTED: Using proper PL/SQL variables
DECLARE
    v_is_rac VARCHAR2(5);
BEGIN
    SELECT CASE WHEN COUNT(*) > 1 THEN 'TRUE' ELSE 'FALSE' END 
    INTO v_is_rac 
    FROM gv$instance;
    
    IF v_is_rac = 'TRUE' THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('=== RAC-SPECIFIC CONFIGURATION ===');
    END IF;
END;
/

PROMPT
PROMPT RAC Services Status (RAC Only):
COLUMN service_name FORMAT A25
COLUMN inst_id FORMAT 99

-- Simple conditional query for RAC services - Using WHERE condition instead of substitution variable
SELECT 
    inst_id,
    name as service_name,
    pdb
FROM gv$services
WHERE name NOT IN ('SYS$BACKGROUND', 'SYS$USERS')
  AND (SELECT COUNT(*) FROM gv$instance) > 1  -- RAC check within query
ORDER BY name, inst_id;

-- =====================================================
-- 3. MEMORY UTILIZATION
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 3. MEMORY UTILIZATION
PROMPT =====================================================
PROMPT

PROMPT SGA Memory Breakdown:
COLUMN component FORMAT A25
COLUMN current_size_gb FORMAT 999.99
COLUMN max_size_gb FORMAT 999.99
COLUMN pct_of_sga FORMAT 999.99

SELECT 
    component,
    ROUND(current_size/1024/1024/1024, 2) as current_size_gb,
    ROUND(max_size/1024/1024/1024, 2) as max_size_gb,
    ROUND(current_size*100/(SELECT SUM(current_size) FROM v$sga_dynamic_components), 2) as pct_of_sga
FROM v$sga_dynamic_components
WHERE current_size > 0
ORDER BY current_size DESC;

PROMPT
PROMPT PGA Memory Statistics:
COLUMN statistic FORMAT A35
COLUMN value_mb FORMAT 999,999,999.99

SELECT 
    name as statistic,
    ROUND(value/1024/1024, 2) as value_mb
FROM v$pgastat 
WHERE name IN (
    'aggregate PGA target parameter',
    'total PGA allocated',
    'total PGA inuse',
    'PGA memory freed back to OS'
)
ORDER BY value DESC;

PROMPT
PROMPT Memory Advisory (PGA):
COLUMN advice_status FORMAT A20
COLUMN size_gb FORMAT 999.99
COLUMN estd_time_factor FORMAT 999.99

SELECT 
    pga_target_for_estimate/1024/1024/1024 as size_gb,
    pga_target_factor as size_factor,
    estd_pga_cache_hit_percentage as cache_hit_pct,
    estd_overalloc_count as overalloc_count
FROM v$pga_target_advice
WHERE pga_target_factor BETWEEN 0.5 AND 2
ORDER BY pga_target_factor;

-- =====================================================
-- 4. STORAGE ANALYSIS
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 4. STORAGE ANALYSIS
PROMPT =====================================================
PROMPT

PROMPT Tablespace Usage:
COLUMN file_name FORMAT A50
COLUMN tablespace_name FORMAT A25
COLUMN total_gb FORMAT 99,999,999.99
COLUMN used_gb FORMAT 99,999,999.99
COLUMN free_gb FORMAT 99,999,999.99
COLUMN pct_used FORMAT 999.99

SELECT 
    ts.tablespace_name,
    ROUND(NVL(df.total_space, 0)/1024/1024/1024, 2) as total_gb,
    ROUND(NVL(df.total_space - fs.free_space, 0)/1024/1024/1024, 2) as used_gb,
    ROUND(NVL(fs.free_space, 0)/1024/1024/1024, 2) as free_gb,
    ROUND(NVL((df.total_space - fs.free_space) * 100 / df.total_space, 0), 2) as pct_used
FROM dba_tablespaces ts,
     (SELECT tablespace_name, SUM(bytes) total_space 
      FROM dba_data_files GROUP BY tablespace_name) df,
     (SELECT tablespace_name, SUM(bytes) free_space 
      FROM dba_free_space GROUP BY tablespace_name) fs
WHERE ts.tablespace_name = df.tablespace_name(+)
  AND ts.tablespace_name = fs.tablespace_name(+)
  AND ts.contents != 'TEMPORARY'
ORDER BY pct_used DESC;

PROMPT
PROMPT Temporary Tablespace Usage:
SELECT 
    tablespace_name,
    ROUND(SUM(bytes_used)/1024/1024/1024, 2) as used_gb,
    ROUND(SUM(bytes_free)/1024/1024/1024, 2) as free_gb,
    ROUND(SUM(bytes_used)*100/SUM(bytes_used + bytes_free), 2) as pct_used
FROM v$temp_space_header
GROUP BY tablespace_name;

PROMPT
PROMPT Tablespace Growth Analysis (Last 30 Days):
COLUMN tablespace_name FORMAT A30
COLUMN resize_time FORMAT A20
COLUMN ts_mb FORMAT 99,999,999,999.90
COLUMN used_mb FORMAT 99,999,999,999.90
COLUMN incr_mb FORMAT 99,999,999.90

-- Optimized historical tablespace growth using AWR data
WITH recent_growth AS (
    SELECT 
        h.tablespace_id,
        h.rtime,
        h.snap_id,
        h.tablespace_size,
        h.tablespace_usedsize,
        LAG(h.tablespace_usedsize, 1) OVER (PARTITION BY h.tablespace_id ORDER BY h.snap_id) as prev_used
    FROM dba_hist_tbspc_space_usage h
    WHERE h.snap_id IN (
        SELECT snap_id FROM dba_hist_snapshot 
        WHERE begin_interval_time > SYSDATE - 30
    )
),
block_size AS (
    SELECT value as block_bytes FROM v$parameter WHERE name = 'db_block_size'
)
SELECT * FROM (
    SELECT 
        v.name as tablespace_name,
        TO_CHAR(TO_DATE(rg.rtime, 'MM/DD/YYYY HH24:MI:SS'), 'DD-MON-YY HH24:MI') as resize_time,
        ROUND(rg.tablespace_size * bs.block_bytes/1024/1024, 2) as ts_mb,
        ROUND(rg.tablespace_usedsize * bs.block_bytes/1024/1024, 2) as used_mb,
        ROUND((rg.tablespace_usedsize - NVL(rg.prev_used, rg.tablespace_usedsize)) * bs.block_bytes/1024/1024, 2) as incr_mb
    FROM recent_growth rg,
         v$tablespace v,
         dba_tablespaces t,
         block_size bs
    WHERE rg.tablespace_id = v.ts#
      AND v.name = t.tablespace_name
      AND t.contents NOT IN ('UNDO', 'TEMPORARY')
      AND (rg.tablespace_usedsize - NVL(rg.prev_used, rg.tablespace_usedsize)) * bs.block_bytes/1024/1024 > 10
    ORDER BY rg.snap_id DESC
)
WHERE ROWNUM <= 30;  -- Show only top 30 growth events

PROMPT
PROMPT Tablespace Growth Summary (Last 30 Days):
-- Optimized query with reduced joins and calculations
WITH block_size AS (
    SELECT value/1024/1024 as mb_per_block 
    FROM v$parameter 
    WHERE name = 'db_block_size'
),
recent_snaps AS (
    SELECT snap_id 
    FROM dba_hist_snapshot 
    WHERE begin_interval_time > SYSDATE - 30
),
ts_growth AS (
    SELECT 
        h.tablespace_id,
        MIN(h.tablespace_usedsize) as min_used,
        MAX(h.tablespace_usedsize) as max_used,
        COUNT(*) as snap_count
    FROM dba_hist_tbspc_space_usage h
    WHERE h.snap_id IN (SELECT snap_id FROM recent_snaps)
    GROUP BY h.tablespace_id
    HAVING MAX(h.tablespace_usedsize) > MIN(h.tablespace_usedsize)
)
SELECT 
    v.name as tablespace_name,
    ROUND((tg.max_used - tg.min_used) * bs.mb_per_block, 2) as total_growth_mb,
    ROUND((tg.max_used - tg.min_used) * bs.mb_per_block / 30, 2) as avg_daily_growth_mb,
    tg.snap_count as snapshots_analyzed
FROM ts_growth tg,
     v$tablespace v,
     dba_tablespaces t,
     block_size bs
WHERE tg.tablespace_id = v.ts#
  AND v.name = t.tablespace_name
  AND t.contents NOT IN ('UNDO', 'TEMPORARY')
ORDER BY total_growth_mb DESC;

-- =====================================================
-- 5. PERFORMANCE METRICS
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 5. PERFORMANCE METRICS
PROMPT =====================================================
PROMPT

PROMPT Key Performance Ratios:
COLUMN metric FORMAT A35
COLUMN value FORMAT 999,999.99
COLUMN status FORMAT A15

WITH perf_metrics AS (
SELECT 'Buffer Cache Hit Ratio' as metric, 
       ROUND((1 - (phy.value/(cur.value + con.value)))*100, 2) as value,
       CASE WHEN (1 - (phy.value/(cur.value + con.value)))*100 > 95 THEN 'GOOD'
            WHEN (1 - (phy.value/(cur.value + con.value)))*100 > 90 THEN 'ACCEPTABLE'
            ELSE 'POOR' END as status
FROM v$sysstat cur, v$sysstat con, v$sysstat phy
WHERE cur.name = 'db block gets'
  AND con.name = 'consistent gets'
  AND phy.name = 'physical reads'
UNION ALL
SELECT 'Library Cache Hit Ratio', 
       ROUND(SUM(pins - reloads) * 100 / SUM(pins), 2),
       CASE WHEN ROUND(SUM(pins - reloads) * 100 / SUM(pins), 2) > 95 THEN 'GOOD'
            WHEN ROUND(SUM(pins - reloads) * 100 / SUM(pins), 2) > 90 THEN 'ACCEPTABLE'
            ELSE 'POOR' END
FROM v$librarycache
UNION ALL
SELECT 'Dictionary Cache Hit Ratio',
       ROUND((1 - SUM(getmisses)/SUM(gets)) * 100, 2),
       CASE WHEN ROUND((1 - SUM(getmisses)/SUM(gets)) * 100, 2) > 95 THEN 'GOOD'
            WHEN ROUND((1 - SUM(getmisses)/SUM(gets)) * 100, 2) > 90 THEN 'ACCEPTABLE'
            ELSE 'POOR' END
FROM v$rowcache
WHERE gets > 0
)
SELECT metric, value, status FROM perf_metrics;

PROMPT
PROMPT Top Wait Events (Current):
COLUMN wait_class FORMAT A20
COLUMN event FORMAT A35
COLUMN total_waits FORMAT 999,999,999
COLUMN time_waited_sec FORMAT 999,999,999.99
COLUMN avg_wait_ms FORMAT 999,999.99

SELECT 
    wait_class,
    event,
    total_waits,
    ROUND(time_waited/100, 2) as time_waited_sec,
    ROUND(average_wait*10, 2) as avg_wait_ms
FROM v$system_event
WHERE wait_class != 'Idle'
  AND total_waits > 0
ORDER BY time_waited DESC
FETCH FIRST 10 ROWS ONLY;

-- =====================================================
-- 6. SQL PERFORMANCE ANALYSIS
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 6. SQL PERFORMANCE ANALYSIS
PROMPT =====================================================
PROMPT

PROMPT Top SQL by Executions (Last Hour):
COLUMN sql_text FORMAT A60
COLUMN executions FORMAT 999,999,999
COLUMN avg_elapsed_ms FORMAT 999,999.99
COLUMN cpu_per_exec_ms FORMAT 999.99

SELECT 
    SUBSTR(sql_text, 1, 60) as sql_text,
    executions,
    ROUND(elapsed_time/executions/1000, 2) as avg_elapsed_ms,
    ROUND(cpu_time/executions/1000, 2) as cpu_per_exec_ms,
    sql_id
FROM v$sql
WHERE executions > 0
  AND last_active_time > SYSDATE - 1/24
ORDER BY executions DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT Top SQL by Elapsed Time (Last Hour):
SELECT 
    SUBSTR(sql_text, 1, 60) as sql_text,
    executions,
    ROUND(elapsed_time/1000000, 2) as total_elapsed_sec,
    ROUND(elapsed_time/executions/1000, 2) as avg_elapsed_ms,
    sql_id
FROM v$sql
WHERE executions > 0
  AND last_active_time > SYSDATE - 1/24
ORDER BY elapsed_time DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT SQL with High Parse Ratio:
COLUMN parse_calls FORMAT 999,999,999
COLUMN parse_ratio FORMAT 999.99

SELECT 
    SUBSTR(sql_text, 1, 60) as sql_text,
    executions,
    parse_calls,
    ROUND(parse_calls*100/GREATEST(executions,1), 2) as parse_ratio,
    sql_id
FROM v$sql
WHERE executions > 100
  AND parse_calls > executions * 0.5
ORDER BY parse_calls DESC
FETCH FIRST 10 ROWS ONLY;

-- =====================================================
-- 7. SESSION ANALYSIS
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 7. SESSION ANALYSIS
PROMPT =====================================================
PROMPT

PROMPT Current Session Summary (All Instances):
COLUMN status FORMAT A15
COLUMN count FORMAT 99,999,999

SELECT 
    inst_id,
    status, 
    COUNT(*) as count
FROM gv$session
GROUP BY inst_id, status
ORDER BY inst_id, count DESC;

PROMPT
PROMPT Sessions by Program (Active - All Instances):
COLUMN program FORMAT A30

SELECT * FROM (
    SELECT 
        inst_id,
        SUBSTR(program, 1, 30) as program,
        COUNT(*) as count
    FROM gv$session
    WHERE status = 'ACTIVE'
    GROUP BY inst_id, program
    ORDER BY inst_id, count DESC
)
WHERE ROWNUM <= 20;

PROMPT
PROMPT Long Running Sessions (>30 minutes - All Instances):
COLUMN username FORMAT A20
COLUMN program FORMAT A25
COLUMN minutes_active FORMAT 9,999,999

SELECT 
    s.inst_id,
    s.username,
    SUBSTR(s.program, 1, 25) as program,
    s.status,
    ROUND((SYSDATE - s.logon_time) * 24 * 60) as minutes_active,
    s.sid,
    s.serial#
FROM gv$session s
WHERE s.status = 'ACTIVE'
  AND s.username IS NOT NULL
  AND (SYSDATE - s.logon_time) * 24 * 60 > 30
ORDER BY s.inst_id, minutes_active DESC;

-- RAC-specific session analysis - CORRECTED: Using proper PL/SQL variables
DECLARE
    v_is_rac VARCHAR2(5);
BEGIN
    SELECT CASE WHEN COUNT(*) > 1 THEN 'TRUE' ELSE 'FALSE' END 
    INTO v_is_rac 
    FROM gv$instance;
    
    IF v_is_rac = 'TRUE' THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('=== RAC SESSION DISTRIBUTION ===');
    END IF;
END;
/

PROMPT
PROMPT Session Distribution Across Instances (RAC):
SELECT 
    inst_id,
    status,
    COUNT(*) as session_count,
    ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1) as pct_of_total
FROM gv$session
WHERE (SELECT COUNT(*) FROM gv$instance) > 1  -- RAC check within query
GROUP BY inst_id, status
ORDER BY inst_id, status;

-- =====================================================
-- 8. LOCKS AND BLOCKING
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 8. LOCKS AND BLOCKING
PROMPT =====================================================
PROMPT

PROMPT Current Blocking Sessions (All Instances):
COLUMN blocking_session FORMAT 999999
COLUMN blocked_session FORMAT 999999
COLUMN blocking_inst FORMAT 99
COLUMN blocked_inst FORMAT 99
COLUMN lock_type FORMAT A15
COLUMN mode_held FORMAT A15
COLUMN mode_requested FORMAT A15

SELECT 
    l.inst_id as blocking_inst,
    s1.sid as blocking_session,
    (SELECT inst_id FROM gv$session WHERE sid = s2.sid AND ROWNUM = 1) as blocked_inst,
    s2.sid as blocked_session,
    l.type as lock_type,
    DECODE(l.lmode, 0,'None',1,'Null',2,'Row Share',3,'Row Excl',4,'Share',5,'Share Row Excl',6,'Exclusive') as mode_held,
    DECODE(l.request, 0,'None',1,'Null',2,'Row Share',3,'Row Excl',4,'Share',5,'Share Row Excl',6,'Exclusive') as mode_requested
FROM gv$lock l, gv$session s1, gv$session s2
WHERE l.sid = s1.sid
  AND l.inst_id = s1.inst_id
  AND l.id1 = ANY(SELECT id1 FROM gv$lock WHERE request > 0 AND sid = s2.sid)
  AND l.lmode > 0
  AND l.request = 0
ORDER BY l.inst_id, s1.sid;

-- RAC-specific: Global enqueue statistics - CORRECTED: Using proper PL/SQL variables
DECLARE
    v_is_rac VARCHAR2(5);
BEGIN
    SELECT CASE WHEN COUNT(*) > 1 THEN 'TRUE' ELSE 'FALSE' END 
    INTO v_is_rac 
    FROM gv$instance;
    
    IF v_is_rac = 'TRUE' THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('=== RAC GLOBAL ENQUEUE STATISTICS ===');
    END IF;
END;
/

PROMPT
PROMPT Global Enqueue Activity (RAC):
COLUMN enqueue_type FORMAT A15
COLUMN gets FORMAT 99,999,999,999
COLUMN waits FORMAT 99,999,999,999
COLUMN wait_time_sec FORMAT 99,999,999.99

SELECT 
    eq_type as enqueue_type,
    SUM(total_req#) as gets,
    SUM(total_wait#) as waits,
    ROUND(SUM(cum_wait_time)/100, 2) as wait_time_sec
FROM gv$enqueue_stat
WHERE (SELECT COUNT(*) FROM gv$instance) > 1  -- RAC check within query
  AND total_req# > 0
GROUP BY eq_type
ORDER BY wait_time_sec DESC, waits DESC;

-- =====================================================
-- 9. RAC-SPECIFIC ANALYSIS
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 9. RAC-SPECIFIC ANALYSIS
PROMPT =====================================================

-- Only show this section for RAC - CORRECTED: Using proper PL/SQL variables
DECLARE
    v_is_rac VARCHAR2(5);
BEGIN
    SELECT CASE WHEN COUNT(*) > 1 THEN 'TRUE' ELSE 'FALSE' END 
    INTO v_is_rac 
    FROM gv$instance;
    
    IF v_is_rac = 'TRUE' THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('=== CLUSTER INTERCONNECT ANALYSIS ===');
    ELSE
        DBMS_OUTPUT.PUT_LINE('** Skipping RAC Analysis - Standalone Environment **');
    END IF;
END;
/

PROMPT
PROMPT Cluster Interconnect Traffic (RAC):
COLUMN name FORMAT A35
COLUMN value_mb FORMAT 99,999,999,999.99

SELECT 
    inst_id,
    name,
    ROUND(value/1024/1024, 2) as value_mb
FROM gv$sysstat
WHERE name LIKE '%gc%bytes%'
  AND (SELECT COUNT(*) FROM gv$instance) > 1  -- RAC check within query
  AND value > 0
ORDER BY inst_id, value DESC;

PROMPT
PROMPT Global Cache Transfer Times (RAC):
COLUMN avg_time_ms FORMAT 999,999,999,999.99

SELECT 
    inst_id,
    name,
    ROUND(value, 2) as avg_time_ms
FROM gv$sysstat
WHERE name LIKE '%gc%time%'
  AND name NOT LIKE '%timeouts%'
  AND (SELECT COUNT(*) FROM gv$instance) > 1  -- RAC check within query
  AND value > 0
ORDER BY inst_id, value DESC;

PROMPT
PROMPT Global Cache Efficiency (RAC):
SELECT 
    i.inst_id,
    'Global Cache Hit Ratio' as metric,
    ROUND((1 - (s1.value / (s2.value + s3.value))) * 100, 2) as hit_ratio_pct
FROM gv$instance i,
     gv$sysstat s1,  -- gc blocks lost
     gv$sysstat s2,  -- gc cr blocks received  
     gv$sysstat s3   -- gc current blocks received
WHERE s1.inst_id = i.inst_id
  AND s2.inst_id = i.inst_id  
  AND s3.inst_id = i.inst_id
  AND s1.name = 'gc blocks lost'
  AND s2.name = 'gc cr blocks received'
  AND s3.name = 'gc current blocks received'
  AND (SELECT COUNT(*) FROM gv$instance) > 1  -- RAC check within query
  AND (s2.value + s3.value) > 0
ORDER BY i.inst_id;

COLUMN VALUE FORMAT A45
PROMPT
PROMPT Cluster Database Parameters (RAC):
SELECT 
    inst_id,
    name as parameter,
    value
FROM gv$parameter
WHERE name IN (
    'cluster_database',
    'cluster_database_instances', 
    'instance_number',
    'thread',
    'remote_listener',
    'cluster_interconnects'
)
  AND (SELECT COUNT(*) FROM gv$instance) > 1  -- RAC check within query
ORDER BY inst_id, name;

-- =====================================================
-- 10. BACKUP STATUS
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 10. BACKUP STATUS
PROMPT =====================================================
PROMPT

PROMPT Recent RMAN Backups:
COLUMN input_type FORMAT A15
COLUMN status FORMAT A15
COLUMN start_time FORMAT A20
COLUMN elapsed_hours FORMAT 999.99

SELECT 
    input_type,
    status,
    TO_CHAR(start_time, 'DD-MON-YY HH24:MI') as start_time,
    ROUND((end_time - start_time) * 24, 2) as elapsed_hours
FROM v$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;

PROMPT
PROMPT Archive Log Generation (Last 24 Hours):
COLUMN hour FORMAT A5
COLUMN archives_generated FORMAT 99,999,999

SELECT 
    TO_CHAR(first_time, 'HH24') as hour,
    COUNT(*) as archives_generated
FROM v$log_history
WHERE first_time > SYSDATE - 1
GROUP BY TO_CHAR(first_time, 'HH24')
ORDER BY hour;

-- =====================================================
-- 11. DATA GUARD STATUS (if applicable)
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 11. DATA GUARD STATUS
PROMPT =====================================================
PROMPT

-- Check if Data Guard is configured
DECLARE
    dg_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO dg_count 
    FROM v$archive_dest 
    WHERE status = 'VALID' AND dest_name LIKE 'LOG_ARCHIVE_DEST_%';
    
    IF dg_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Data Guard Configuration Detected');
    ELSE
        DBMS_OUTPUT.PUT_LINE('No Data Guard Configuration Found');
    END IF;
END;
/

PROMPT Data Guard Destinations:
COLUMN dest_name FORMAT A20
COLUMN destination FORMAT A50
COLUMN status FORMAT A15
COLUMN error FORMAT A50

SELECT 
    dest_name,
    destination,
    status,
    error
FROM v$archive_dest
WHERE status != 'INACTIVE'
ORDER BY dest_name;

-- =====================================================
-- 12. SECURITY OVERVIEW
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 12. SECURITY OVERVIEW
PROMPT =====================================================
PROMPT

PROMPT User Account Status:
COLUMN account_status FORMAT A20

SELECT 
    account_status,
    COUNT(*) as count
FROM dba_users
WHERE username NOT IN (
    'SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN','FLOWS_FILES',
    'MDSYS','ORDSYS','EXFSYS','DMSYS','WMSYS','CTXSYS',
    'ANONYMOUS','XDB','XS$NULL','ORACLE_OCM','APEX_040000'
)
GROUP BY account_status
ORDER BY count DESC;

PROMPT
PROMPT Privileged Users:
COLUMN username FORMAT A25
COLUMN granted_role FORMAT A30

SELECT DISTINCT
    grantee as username,
    granted_role
FROM dba_role_privs
WHERE granted_role IN ('DBA', 'SYSDBA', 'SYSOPER')
  AND grantee NOT IN ('SYS', 'SYSTEM')
ORDER BY grantee, granted_role;

-- =====================================================
-- 13. RECOMMENDATIONS
-- =====================================================
PROMPT
PROMPT =====================================================
PROMPT 13. HEALTH CHECK RECOMMENDATIONS
PROMPT =====================================================
PROMPT

-- Tablespace Usage Warnings
PROMPT Tablespace Usage Warnings:
SELECT 'WARNING: ' || tablespace_name || ' is ' || ROUND(pct_used, 1) || '% full' as recommendation
FROM (
    SELECT 
        ts.tablespace_name,
        ROUND(NVL((df.total_space - fs.free_space) * 100 / df.total_space, 0), 2) as pct_used
    FROM dba_tablespaces ts,
         (SELECT tablespace_name, SUM(bytes) total_space 
          FROM dba_data_files GROUP BY tablespace_name) df,
         (SELECT tablespace_name, SUM(bytes) free_space 
          FROM dba_free_space GROUP BY tablespace_name) fs
    WHERE ts.tablespace_name = df.tablespace_name(+)
      AND ts.tablespace_name = fs.tablespace_name(+)
      AND ts.contents != 'TEMPORARY'
)
WHERE pct_used > 85;

-- Memory Recommendations
PROMPT
PROMPT Memory Recommendations:
SELECT 'INFO: Consider PGA tuning on instance ' || inst_id || ' - current allocation: ' || 
       ROUND(value/1024/1024/1024, 1) || 'GB' as recommendation
FROM gv$pgastat 
WHERE name = 'total PGA allocated'
  AND value > (SELECT value * 1.2 FROM v$pgastat WHERE name = 'aggregate PGA target parameter');

-- Session Warnings  
PROMPT
PROMPT Session Warnings:
SELECT 'WARNING: Instance ' || inst_id || ' has ' || COUNT(*) || ' long-running sessions (>2 hours)' as recommendation
FROM gv$session
WHERE status = 'ACTIVE'
  AND username IS NOT NULL
  AND (SYSDATE - logon_time) * 24 > 2
GROUP BY inst_id
HAVING COUNT(*) > 0;

-- RAC-specific recommendations
PROMPT
PROMPT RAC-Specific Recommendations:
SELECT 'INFO: RAC Environment - Monitor interconnect latency and global cache efficiency' as recommendation
FROM dual
WHERE (SELECT COUNT(*) FROM gv$instance) > 1  -- RAC check within query
UNION ALL
SELECT 'WARNING: High global cache block transfer time detected on instance ' || inst_id as recommendation
FROM gv$sysstat
WHERE name = 'gc cr block receive time'
  AND value > 10  -- More than 10ms average
  AND (SELECT COUNT(*) FROM gv$instance) > 1;  -- RAC check within query

PROMPT
PROMPT =====================================================
PROMPT     END OF HEALTH CHECK REPORT
PROMPT =====================================================
PROMPT Report completed at:
SELECT TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI:SS') FROM dual;

SPOOL OFF

SET PAGESIZE 20
SET LINESIZE 80
SET FEEDBACK ON
SET VERIFY ON
SET HEADING ON

PROMPT
PROMPT Health check report has been saved to: healthcheck_&report_time..txt
PROMPT