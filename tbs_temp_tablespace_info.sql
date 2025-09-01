-- ================================================================================
-- ORACLE TEMPORARY TABLESPACE USAGE MONITORING SCRIPT
-- Description: Comprehensive monitoring of temporary tablespace usage and sessions
-- Author: Daniel Oliveira - June 2025
-- ================================================================================

-- Set formatting for better visual output
SET PAGESIZE 100
SET LINESIZE 150
SET FEEDBACK OFF
SET VERIFY OFF

-- Column formatting
COLUMN tablespace_name FORMAT A20 HEADING 'Tablespace Name'
COLUMN total_mb FORMAT 999,999.99 HEADING 'Total Size (MB)'
COLUMN used_mb FORMAT 999,999.99 HEADING 'Used Space (MB)'
COLUMN free_mb FORMAT 999,999.99 HEADING 'Free Space (MB)'
COLUMN usage_pct FORMAT 999.99 HEADING 'Usage %'
COLUMN status FORMAT A10 HEADING 'Status'

COLUMN sid_serial FORMAT A12 HEADING 'SID,Serial#'
COLUMN username FORMAT A15 HEADING 'Database User'
COLUMN osuser FORMAT A15 HEADING 'OS User'
COLUMN spid FORMAT A8 HEADING 'OS PID'
COLUMN program FORMAT A25 HEADING 'Program'
COLUMN module FORMAT A20 HEADING 'Module'
COLUMN mb_used FORMAT 999,999.99 HEADING 'Temp Used (MB)'
COLUMN tablespace FORMAT A15 HEADING 'Tablespace'
COLUMN statements FORMAT 999 HEADING 'Stmts'
COLUMN sql_id FORMAT A13 HEADING 'SQL ID'

PROMPT
PROMPT ================================================================================
PROMPT                        TEMPORARY TABLESPACE OVERVIEW
PROMPT ================================================================================

-- Enhanced Temporary Tablespace Usage Summary
SELECT 
    ts.tablespace_name,
    NVL(df.total_mb, 0) AS total_mb,
    NVL(tu.used_mb, 0) AS used_mb,
    NVL(df.total_mb, 0) - NVL(tu.used_mb, 0) AS free_mb,
    CASE 
        WHEN NVL(df.total_mb, 0) = 0 THEN 0
        ELSE ROUND((NVL(tu.used_mb, 0) / df.total_mb) * 100, 2)
    END AS usage_pct,
    ts.status
FROM 
    dba_tablespaces ts
LEFT JOIN (
    -- Total allocated space per temporary tablespace
    SELECT 
        t.tablespace_name,
        SUM(t.bytes) / 1024 / 1024 AS total_mb
    FROM 
        dba_temp_files t
    GROUP BY 
        t.tablespace_name
) df ON ts.tablespace_name = df.tablespace_name
LEFT JOIN (
    -- Current usage per temporary tablespace
    SELECT 
        ss.tablespace_name,
        SUM(ss.used_blocks * ts.block_size) / 1024 / 1024 AS used_mb
    FROM 
        v$sort_segment ss,
        v$tablespace vts,
        dba_tablespaces ts
    WHERE 
        ss.tablespace_name = ts.tablespace_name
        AND vts.name = ss.tablespace_name
    GROUP BY 
        ss.tablespace_name
) tu ON ts.tablespace_name = tu.tablespace_name
WHERE 
    ts.contents = 'TEMPORARY'
ORDER BY 
    ts.tablespace_name;

PROMPT
PROMPT ================================================================================
PROMPT                        TEMPORARY SPACE USAGE BY SESSION
PROMPT ================================================================================

-- Enhanced Session-level Temporary Space Usage
SELECT 
    s.sid || ',' || s.serial# AS sid_serial,
    s.username,
    s.osuser,
    p.spid,
    SUBSTR(s.program, 1, 25) AS program,
    SUBSTR(s.module, 1, 20) AS module,
    SUM(su.blocks) * ts.block_size / 1024 / 1024 AS mb_used,
    su.tablespace,
    COUNT(*) AS statements,
    s.sql_id
FROM 
    v$sort_usage su,
    v$session s,
    v$process p,
    dba_tablespaces ts
WHERE 
    su.session_addr = s.saddr
    AND s.paddr = p.addr
    AND su.tablespace = ts.tablespace_name
GROUP BY 
    s.sid, s.serial#, s.username, s.osuser, p.spid, 
    s.program, s.module, ts.block_size, su.tablespace, s.sql_id
ORDER BY 
    mb_used DESC, s.sid;

PROMPT
PROMPT ================================================================================
PROMPT                        TOP SQL STATEMENTS USING TEMPORARY SPACE
PROMPT ================================================================================

-- Column formatting for SQL analysis
COLUMN sql_text FORMAT A60 HEADING 'SQL Text (First 60 chars)'
COLUMN executions FORMAT 999,999 HEADING 'Executions'
COLUMN temp_space_mb FORMAT 999,999.99 HEADING 'Temp Space (MB)'

-- Top SQL statements currently using temporary space
SELECT 
    sq.sql_id,
    SUM(su.blocks) * ts.block_size / 1024 / 1024 AS temp_space_mb,
    sq.executions,
    SUBSTR(sq.sql_text, 1, 60) AS sql_text
FROM 
    v$sort_usage su,
    v$session s,
    v$sql sq,
    dba_tablespaces ts
WHERE 
    su.session_addr = s.saddr
    AND s.sql_id = sq.sql_id
    AND su.tablespace = ts.tablespace_name
GROUP BY 
    sq.sql_id, sq.executions, sq.sql_text, ts.block_size
ORDER BY 
    temp_space_mb DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT ================================================================================
PROMPT                        TEMPORARY TABLESPACE CONFIGURATION
PROMPT ================================================================================

-- Column formatting for configuration details
COLUMN file_name FORMAT A50 HEADING 'File Name'
COLUMN autoextensible FORMAT A5 HEADING 'Auto'
COLUMN max_mb FORMAT 999,999.99 HEADING 'Max Size (MB)'
COLUMN increment_mb FORMAT 999.99 HEADING 'Increment (MB)'

-- Temporary tablespace file configuration
SELECT 
    tf.tablespace_name,
    tf.file_name,
    tf.bytes / 1024 / 1024 AS total_mb,
    tf.autoextensible,
    CASE 
        WHEN tf.maxbytes = 0 THEN 0
        ELSE tf.maxbytes / 1024 / 1024
    END AS max_mb,
    tf.increment_by * ts.block_size / 1024 / 1024 AS increment_mb
FROM 
    dba_temp_files tf,
    dba_tablespaces ts
WHERE 
    tf.tablespace_name = ts.tablespace_name
ORDER BY 
    tf.tablespace_name, tf.file_id;

PROMPT
PROMPT ================================================================================
PROMPT                        SUMMARY STATISTICS
PROMPT ================================================================================

-- Summary statistics
SELECT 
    'Total Temp Tablespaces' AS metric,
    COUNT(*) AS value
FROM 
    dba_tablespaces 
WHERE 
    contents = 'TEMPORARY'
UNION ALL
SELECT 
    'Active Sessions Using Temp',
    COUNT(DISTINCT s.sid)
FROM 
    v$sort_usage su,
    v$session s
WHERE 
    su.session_addr = s.saddr
UNION ALL
SELECT 
    'Total Temp Files',
    COUNT(*)
FROM 
    dba_temp_files
UNION ALL
SELECT 
    'Total Allocated Temp Space (MB)',
    ROUND(SUM(bytes) / 1024 / 1024, 2)
FROM 
    dba_temp_files;

-- Reset formatting
SET PAGESIZE 14
SET LINESIZE 80
SET FEEDBACK ON
SET VERIFY ON

PROMPT
PROMPT ================================================================================
PROMPT Script execution completed. 
PROMPT Monitor these metrics regularly for optimal temporary space management.
PROMPT ================================================================================