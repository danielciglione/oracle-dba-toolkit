-- =====================================================
-- UNIFIED TABLESPACE USAGE MONITORING SCRIPT
-- =====================================================
-- This script provides multiple options to view tablespace usage:
-- 1 = All tablespaces (including TEMP)
-- 2 = Regular tablespaces only (excluding TEMP)  
-- 3 = Specific tablespace
-- 4 = TEMP tablespaces only
-- =====================================================
-- Author: Daniel Oliveira - June 2025
-- =====================================================

-- Execute appropriate query based on choice
SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING ON
SET PAGESIZE 1000
SET LINESIZE 150
SET TRIMSPOOL ON
SET TRIMOUT ON

PROMPT 
PROMPT =====================================================
PROMPT    TABLESPACE USAGE MONITORING OPTIONS
PROMPT =====================================================
PROMPT 1 - All tablespaces (including TEMP)
PROMPT 2 - Regular tablespaces only (excluding TEMP)
PROMPT 3 - Specific tablespace
PROMPT 4 - TEMP tablespaces only
PROMPT =====================================================
PROMPT

ACCEPT choice PROMPT 'Enter your choice (1-4): '

-- Set column formatting
COL "Tablespace" FOR A22
COL "Used MB" FOR 99,999,999
COL "Free MB" FOR 99,999,999
COL "Total MB" FOR 99,999,999
COL "Pct. Free" FOR 999
COL "Type" FOR A8

-- Clear screen and show header
CLEAR SCREEN
PROMPT
PROMPT =====================================================
PROMPT           TABLESPACE USAGE REPORT
PROMPT =====================================================
PROMPT

-- Handle specific tablespace choice
COLUMN choice_val NEW_VALUE choice_val NOPRINT
SELECT '&choice' choice_val FROM dual;

-- Prompt for tablespace name if choice is 3
ACCEPT tbs_name PROMPT 'Enter tablespace name (if choice 3): ' DEFAULT 'DUMMY'

-- Choice 1: All tablespaces (including TEMP)
SELECT * FROM (
    -- Regular tablespaces
    SELECT df.tablespace_name "Tablespace",
           'REGULAR' "Type",
           NVL(tu.totalusedspace, 0) "Used MB",
           (df.totalspace - NVL(tu.totalusedspace, 0)) "Free MB",
           df.totalspace "Total MB",
           ROUND(100 * ((df.totalspace - NVL(tu.totalusedspace, 0)) / df.totalspace)) "Pct. Free"
    FROM (SELECT tablespace_name,
                 ROUND(SUM(bytes) / 1048576) TotalSpace
          FROM dba_data_files 
          GROUP BY tablespace_name) df
    LEFT JOIN (SELECT ROUND(SUM(bytes)/(1024*1024)) totalusedspace, 
                      tablespace_name
               FROM dba_segments 
               GROUP BY tablespace_name) tu
    ON df.tablespace_name = tu.tablespace_name    
    UNION ALL    
    -- TEMP tablespaces
    SELECT tf.tablespace_name "Tablespace",
           'TEMP' "Type",
           NVL(ts.used_mb, 0) "Used MB",
           (tf.totalspace - NVL(ts.used_mb, 0)) "Free MB",
           tf.totalspace "Total MB",
           ROUND(100 * ((tf.totalspace - NVL(ts.used_mb, 0)) / tf.totalspace)) "Pct. Free"
    FROM (SELECT tablespace_name,
                 ROUND(SUM(bytes) / 1048576) TotalSpace
          FROM dba_temp_files 
          GROUP BY tablespace_name) tf
    LEFT JOIN (SELECT tablespace_name,
                      ROUND(SUM(bytes_used) / 1048576) used_mb
               FROM v$temp_space_header
               GROUP BY tablespace_name) ts
    ON tf.tablespace_name = ts.tablespace_name
) 
WHERE CASE 
    WHEN '&choice_val' = '1' THEN 1  -- All tablespaces
    WHEN '&choice_val' = '2' AND "Type" = 'REGULAR' THEN 1  -- Regular only
    WHEN '&choice_val' = '3' AND UPPER("Tablespace") = UPPER('&tbs_name') THEN 1  -- Specific
    WHEN '&choice_val' = '4' AND "Type" = 'TEMP' THEN 1  -- TEMP only
    ELSE 0
END = 1
ORDER BY "Type", "Tablespace" ASC;

-- Summary information
PROMPT
PROMPT =====================================================
SELECT CASE 
    WHEN '&choice_val' = '1' THEN 'SUMMARY: All tablespaces displayed'
    WHEN '&choice_val' = '2' THEN 'SUMMARY: Regular tablespaces only'
    WHEN '&choice_val' = '3' THEN 'SUMMARY: Specific tablespace - ' || UPPER('&tbs_name')
    WHEN '&choice_val' = '4' THEN 'SUMMARY: TEMP tablespaces only'
    ELSE 'SUMMARY: Invalid choice'
END AS "Report Summary"
FROM dual;

PROMPT =====================================================
PROMPT Report generated on: 
SELECT TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI:SS') "Current Date/Time" FROM dual;
PROMPT =====================================================

-- Reset column formatting
COL "Tablespace" CLEAR
COL "Used MB" CLEAR  
COL "Free MB" CLEAR
COL "Total MB" CLEAR
COL "Pct. Free" CLEAR
COL "Type" CLEAR

-- Undefine variables
UNDEFINE choice
UNDEFINE choice_val
UNDEFINE tbs_name

PROMPT
PROMPT Script execution completed.
PROMPT