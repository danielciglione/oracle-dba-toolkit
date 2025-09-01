-- =====================================================
-- Oracle Database SGA Usage
-- Purpose: Check SGA memory usage
-- Note: "Free" column reflects only the 'free memory' entry per pool, not total free memory.
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
COLUMN pool    HEADING "Pool"
COLUMN name    HEADING "Name"
COLUMN sgasize HEADING "Total SGA" FORMAT 999,999,999

SELECT
    f.pool
  , f.name
  , s.sgasize
  , ROUND(f.bytes/s.sgasize*100, 2) "Pct_Free"
FROM
    (SELECT SUM(bytes) sgasize, pool FROM v$sgastat GROUP BY pool) s
  , v$sgastat f
WHERE
    f.name = 'free memory'
  AND f.pool = s.pool
/