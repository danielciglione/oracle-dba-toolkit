-- =====================================================================
-- COMPLETE ORACLE LOCKS AND BLOCKING ANALYSIS SCRIPT
-- =====================================================================
-- Author: Daniel Ciglione - June 2025
-- Description: This script provides a comprehensive analysis of locks and blocking sessions in Oracle.
-- It includes an executive summary, blocking hierarchy, active locks by object, critical wait events,
-- SQL statements from blocked/blocking sessions, and more.
-- It is designed to help DBAs quickly identify and resolve locking issues in the database.
-- Usage: Execute in SQL*Plus or any compatible Oracle SQL client.
-- Note: Ensure you have the necessary privileges to access v$ views and dba_objects.
-- Version: Compatible with Oracle 11g and later
-- =====================================================================

SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING ON
SET PAGESIZE 2000
SET LINESIZE 200
SET TRIMSPOOL ON
SET TRIMOUT ON
COLUMN username FORMAT A15
COLUMN program FORMAT A20
COLUMN machine FORMAT A15
COLUMN osuser FORMAT A12
COLUMN sql_text FORMAT A60
COLUMN object_name FORMAT A25
COLUMN lock_type FORMAT A15
COLUMN mode_held FORMAT A12
COLUMN mode_requested FORMAT A12
COLUMN wait_event FORMAT A30

PROMPT
PROMPT =====================================================================
PROMPT                    COMPLETE LOCKS AND BLOCKING ANALYSIS
PROMPT =====================================================================
PROMPT

PROMPT =====================================================================
PROMPT             1. EXECUTIVE SUMMARY - BLOCKING OVERVIEW
PROMPT =====================================================================
PROMPT

SELECT /*+ USE_HASH(s,l) */
    'BLOCKED SESSIONS' as type,
    COUNT(*) as quantity
FROM v$session s, v$lock l
WHERE s.sid = l.sid
AND l.block = 0
AND l.request > 0
UNION ALL
SELECT 
    'BLOCKING SESSIONS' as type,
    COUNT(DISTINCT s.sid) as quantity
FROM v$session s, v$lock l
WHERE s.sid = l.sid
AND l.block > 0
UNION ALL
SELECT 
    'TOTAL ACTIVE LOCKS' as type,
    COUNT(*) as quantity
FROM v$lock
WHERE block > 0 OR request > 0;

PROMPT
PROMPT =====================================================================
PROMPT            2. BLOCKING HIERARCHY - DEPENDENCY TREE 
PROMPT =====================================================================
PROMPT

WITH lock_tree AS (
    SELECT 
        blocker.sid as blocker_sid,
        blocker.serial# as blocker_serial,
        blocker.username as blocker_user,
        blocker.program as blocker_program,
        blocker.machine as blocker_machine,
        blocker.status as blocker_status,
        waiter.sid as waiter_sid,
        waiter.serial# as waiter_serial,
        waiter.username as waiter_user,
        waiter.program as waiter_program,
        waiter.machine as waiter_machine,
        waiter.status as waiter_status,
        waiter.seconds_in_wait as wait_time_sec,
        waiter.event as wait_event,
        l1.type as lock_type,
        DECODE(l1.lmode,
            0, 'None',
            1, 'Null',
            2, 'Row-S (SS)',
            3, 'Row-X (SX)',
            4, 'Share',
            5, 'S/Row-X (SSX)',
            6, 'Exclusive',
            l1.lmode) as mode_held,
        DECODE(l2.request,
            0, 'None',
            1, 'Null',
            2, 'Row-S (SS)',
            3, 'Row-X (SX)',
            4, 'Share',
            5, 'S/Row-X (SSX)',
            6, 'Exclusive',
            l2.request) as mode_requested
    FROM v$lock l1, v$lock l2, v$session blocker, v$session waiter
    WHERE l1.block = 1
    AND l2.request > 0
    AND l1.id1 = l2.id1
    AND l1.id2 = l2.id2
    AND l1.type = l2.type
    AND l1.sid = blocker.sid
    AND l2.sid = waiter.sid
)
SELECT 
    '*** BLOCKER ***' as type,
    blocker_sid as sid,
    blocker_serial as serial#,
    blocker_user as username,
    blocker_program as program,
    blocker_machine as machine,
    blocker_status as status,
    NULL as wait_time_sec,
    lock_type,
    mode_held,
    mode_requested
FROM lock_tree
UNION ALL
SELECT 
    '    -> WAITING' as type,
    waiter_sid as sid,
    waiter_serial as serial#,
    waiter_user as username,
    waiter_program as program,
    waiter_machine as machine,
    waiter_status as status,
    wait_time_sec,
    lock_type,
    mode_held,
    mode_requested
FROM lock_tree
ORDER BY 1, 2;

PROMPT
PROMPT =====================================================================
PROMPT                  3. ACTIVE LOCKS BY OBJECT
PROMPT =====================================================================
PROMPT

SELECT 
    s.sid,
    s.serial#,
    s.username,
    s.program,
    s.machine,
    s.osuser,
    o.object_name,
    o.object_type,
    l.type as lock_type,
    DECODE(l.lmode,
        0, 'None',
        1, 'Null',
        2, 'Row-S (SS)',
        3, 'Row-X (SX)',
        4, 'Share',
        5, 'S/Row-X (SSX)',
        6, 'Exclusive',
        l.lmode) as mode_held,
    DECODE(l.request,
        0, 'None',
        1, 'Null',
        2, 'Row-S (SS)',
        3, 'Row-X (SX)',
        4, 'Share',
        5, 'S/Row-X (SSX)',
        6, 'Exclusive',
        l.request) as mode_requested,
    CASE WHEN l.block = 1 THEN 'BLOCKING' 
         WHEN l.request > 0 THEN 'WAITING' 
         ELSE 'ACTIVE' END as lock_status
FROM v$lock l
JOIN v$session s ON l.sid = s.sid
LEFT JOIN dba_objects o ON (l.type = 'TM' AND l.id1 = o.object_id)
WHERE (l.block > 0 OR l.request > 0)
ORDER BY object_name, lock_status, s.sid;

PROMPT
PROMPT =====================================================================
PROMPT             4. SESSIONS WITH CRITICAL WAIT EVENTS
PROMPT =====================================================================
PROMPT

SELECT 
    s.sid,
    s.serial#,
    s.username,
    s.program,
    s.machine,
    s.status,
    s.event as wait_event,
    s.state,
    s.seconds_in_wait,
    s.wait_time,
    s.p1text,
    s.p1,
    s.p2text,
    s.p2,
    s.p3text,
    s.p3,
    s.blocking_session,
    s.blocking_session_status
FROM v$session s
WHERE s.event IN (
    'enq: TX - row lock contention',
    'enq: TM - contention',
    'enq: UL - contention',
    'library cache lock',
    'library cache pin',
    'row cache lock',
    'DFS lock handle',
    'buffer busy waits',
    'read by other session',
    'gc buffer busy acquire',
    'gc buffer busy release'
)
AND s.username IS NOT NULL
ORDER BY s.seconds_in_wait DESC, s.sid;

PROMPT
PROMPT =====================================================================
PROMPT      5. SQL STATEMENTS FROM SESSIONS INVOLVED IN BLOCKING
PROMPT =====================================================================
PROMPT

SELECT 
    s.sid,
    s.serial#,
    s.username,
    s.status,
    CASE WHEN EXISTS (SELECT 1 FROM v$lock l WHERE l.sid = s.sid AND l.block = 1) 
         THEN 'BLOCKER'
         WHEN EXISTS (SELECT 1 FROM v$lock l WHERE l.sid = s.sid AND l.request > 0) 
         THEN 'BLOCKED'
         ELSE 'OTHERS' END as session_type,
    s.event,
    s.seconds_in_wait,
    NVL(sq.sql_text, 'N/A') as sql_text
FROM v$session s
LEFT JOIN (
    SELECT DISTINCT sql_id, 
           FIRST_VALUE(sql_text) OVER (PARTITION BY sql_id ORDER BY child_number) as sql_text
    FROM v$sql
) sq ON s.sql_id = sq.sql_id
WHERE s.sid IN (
    SELECT DISTINCT l.sid 
    FROM v$lock l 
    WHERE l.block > 0 OR l.request > 0
)
AND s.username IS NOT NULL
ORDER BY session_type, s.sid;

PROMPT
PROMPT =====================================================================
PROMPT         6. WAIT EVENTS STATISTICS (RECENT EVENTS)
PROMPT =====================================================================
PROMPT

SELECT 
    event,
    total_waits,
    total_timeouts,
    time_waited,
    average_wait,
    ROUND((time_waited / SUM(time_waited) OVER()) * 100, 2) as pct_total_wait_time
FROM v$system_event
WHERE event IN (
    'enq: TX - row lock contention',
    'enq: TM - contention', 
    'enq: UL - contention',
    'library cache lock',
    'library cache pin',
    'row cache lock',
    'buffer busy waits',
    'latch free',
    'latch: cache buffers chains'
)
AND total_waits > 0
ORDER BY time_waited DESC;

PROMPT
PROMPT =====================================================================
PROMPT              7. TRANSACTION (TX) LOCKS DETAILS
PROMPT =====================================================================
PROMPT

SELECT 
    s.sid,
    s.serial#,
    s.username,
    s.program,
    s.machine,
    l.type,
    l.id1,
    l.id2,
    DECODE(l.lmode,
        0, 'None',
        1, 'Null', 
        2, 'Row-S (SS)',
        3, 'Row-X (SX)',
        4, 'Share',
        5, 'S/Row-X (SSX)',
        6, 'Exclusive') as mode_held,
    DECODE(l.request,
        0, 'None',
        1, 'Null',
        2, 'Row-S (SS)', 
        3, 'Row-X (SX)',
        4, 'Share',
        5, 'S/Row-X (SSX)',
        6, 'Exclusive') as mode_requested,
    l.ctime as hold_time_sec,
    l.block,
    s.event,
    s.seconds_in_wait
FROM v$lock l, v$session s
WHERE l.sid = s.sid
AND l.type = 'TX'
AND (l.block > 0 OR l.request > 0)
ORDER BY l.ctime DESC, s.sid;

PROMPT
PROMPT =====================================================================
PROMPT              8. LONG TRANSACTIONS AND UNDO USAGE
PROMPT =====================================================================
PROMPT

-- Set the transaction duration threshold in minutes (default: 5)
-- Note: Using &&VARIABLE syntax for reusable substitution without re-prompting
DEFINE LONG_TXN_MINUTES=5

SELECT 
    s.sid,
    s.serial#,
    s.username,
    s.program,
    s.status,
    t.start_time,
    ROUND(EXTRACT(DAY FROM (SYSTIMESTAMP - CAST(t.start_time AS TIMESTAMP))) * 24 * 60 +
          EXTRACT(HOUR FROM (SYSTIMESTAMP - CAST(t.start_time AS TIMESTAMP))) * 60 +
          EXTRACT(MINUTE FROM (SYSTIMESTAMP - CAST(t.start_time AS TIMESTAMP))), 2) as duration_minutes,
    ROUND(t.used_ublk * (SELECT TO_NUMBER(value) FROM v$parameter WHERE name = 'db_block_size') / 1024 / 1024, 2) as undo_mb,
    t.used_urec as undo_records,
    r.name as rollback_segment
FROM v$session s
JOIN v$transaction t ON s.taddr = t.addr
JOIN v$rollname r ON t.xidusn = r.usn
WHERE t.start_time IS NOT NULL
AND ROUND(EXTRACT(DAY FROM (SYSTIMESTAMP - CAST(t.start_time AS TIMESTAMP))) * 24 * 60 +
          EXTRACT(HOUR FROM (SYSTIMESTAMP - CAST(t.start_time AS TIMESTAMP))) * 60 +
          EXTRACT(MINUTE FROM (SYSTIMESTAMP - CAST(t.start_time AS TIMESTAMP))), 2) > &&LONG_TXN_MINUTES
ORDER BY 7 DESC;

PROMPT
PROMPT =====================================================================
PROMPT              9. MOST FREQUENTLY BLOCKED OBJECTS
PROMPT =====================================================================
PROMPT

-- Note: TM locks join to dba_objects for object details
-- TX locks will show NULL for object columns (handled by NVL in SELECT)
SELECT 
    NVL(o.owner, 'SYSTEM') as owner,
    NVL(o.object_name, 'TRANSACTION_LOCK') as object_name,
    NVL(o.object_type, 'TX') as object_type,
    COUNT(*) as lock_count,
    COUNT(CASE WHEN l.request > 0 THEN 1 END) as waiting_locks,
    COUNT(CASE WHEN l.block = 1 THEN 1 END) as blocking_locks
FROM v$lock l
LEFT JOIN dba_objects o ON (l.type = 'TM' AND l.id1 = o.object_id)
WHERE l.type IN ('TM', 'TX')
GROUP BY o.owner, o.object_name, o.object_type
HAVING COUNT(*) > 1
ORDER BY lock_count DESC;

PROMPT
PROMPT =========================================================================
PROMPT  10. RESOLUTION COMMANDS (REFERENCE ONLY - DO NOT EXECUTE AUTOMATICALLY) 
PROMPT =========================================================================
PROMPT WARNING: Review the following KILL commands carefully before execution!
PROMPT These commands will terminate active database sessions immediately.
PROMPT

SELECT 
    'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE;' as kill_command,
    s.sid,
    s.serial#,
    s.username,
    s.program,
    s.machine,
    'BLOCKER - ' || l.type || ' (' ||
    DECODE(l.lmode,
        0, 'None',
        1, 'Null',
        2, 'Row-S (SS)', 
        3, 'Row-X (SX)',
        4, 'Share',
        5, 'S/Row-X (SSX)',
        6, 'Exclusive',
        l.lmode) ||
    ') on (' || NVL(o.owner || '.' || o.object_name, 'SYSTEM_LOCK') || ')' as reason
FROM v$session s, v$lock l
LEFT JOIN dba_objects o ON (l.type = 'TM' AND l.id1 = o.object_id)
WHERE s.sid = l.sid
AND l.block = 1
AND s.username IS NOT NULL
ORDER BY s.sid;

PROMPT
PROMPT =====================================================================
PROMPT                    END OF LOCKS ANALYSIS
PROMPT =====================================================================
PROMPT
PROMPT INSTRUCTIONS:
PROMPT 1. First analyze the EXECUTIVE SUMMARY to understand the general situation
PROMPT 2. Check the BLOCKING HIERARCHY to identify dependencies
PROMPT 3. Examine the SQL STATEMENTS from problematic sessions
PROMPT 4. Use KILL SESSION commands only if necessary and with caution
PROMPT 5. Monitor WAIT STATISTICS for trends
PROMPT =====================================================================

SET FEEDBACK ON
SET VERIFY ON