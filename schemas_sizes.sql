-- ======================================================================
-- Script: Object Size Analysis by Schema (Tables + LOBs)
-- Description: Shows table and LOB sizes by schema
-- Options: Enter a specific schema or 'ALL' for all non-SYS schemas
-- ======================================================================
-- Author: Daniel Oliveira - June 2025
-- ======================================================================

-- Prompt for schema input
ACCEPT p_schema PROMPT 'Enter SCHEMA (or ALL for all non-SYS schemas): '

-- Clear previous formatting
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES

SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING ON
SET PAGESIZE 2000
SET LINESIZE 200
SET TRIMSPOOL ON
SET TRIMOUT ON

COLUMN owner FORMAT A20 HEADING 'Schema|Owner'
COLUMN segment_name FORMAT A35 HEADING 'Table|Name'
COLUMN partitioned FORMAT A10 HEADING 'Parti-|tioned'
COLUMN last_analyzed FORMAT A12 HEADING 'Last|Analyzed'
COLUMN num_rows FORMAT 999,999,999,990 HEADING 'Number of|Rows'
COLUMN table_mb FORMAT 999,999,990.90 HEADING 'Table|Size (MB)'
COLUMN lob_mb FORMAT 999,999,990.90 HEADING 'LOB|Size (MB)'
COLUMN total_mb FORMAT 999,999,990.90 HEADING 'Total|Size (MB)'
COLUMN total_gb FORMAT 999,990.90 HEADING 'Total|Size (GB)'

-- Breaks and totals
BREAK ON REPORT
COMPUTE SUM LABEL 'GRAND TOTAL:' OF table_mb lob_mb total_mb ON REPORT

-- Report title
TTITLE CENTER 'OBJECT SIZE ANALYSIS REPORT BY SCHEMA' SKIP 2

-- Main improved query
SELECT 
    z.owner,
    z.segment_name,
    y.partitioned,
    TO_CHAR(y.last_analyzed, 'MM/DD/YYYY') AS last_analyzed,
    y.num_rows,
    SUM(z.table_mb) AS table_mb,
    SUM(z.lob_mb) AS lob_mb,
    SUM(z.table_mb) + SUM(z.lob_mb) AS total_mb,
    ROUND((SUM(z.table_mb) + SUM(z.lob_mb)) / 1024, 2) AS total_gb
FROM (
    -- Table sizes
    SELECT /*+ PARALLEL(s,4) */
        s.owner,
        s.segment_name,
        ROUND(SUM(s.bytes) / 1024 / 1024, 2) AS table_mb,
        0 AS lob_mb
    FROM dba_segments s
        INNER JOIN dba_tables t ON (s.segment_name = t.table_name AND s.owner = t.owner)
    WHERE s.segment_type LIKE 'TABLE%'
      AND (UPPER('&p_schema') = 'ALL' AND s.owner NOT IN ('SYS', 'SYSTEM', 'SYSAUX', 'DBSNMP', 'OUTLN', 'PERFSTAT', 'WMSYS', 'XDB', 'CTXSYS', 'ANONYMOUS', 'SYSMAN', 'MGMT_VIEW', 'OLAPSYS') 
           OR UPPER(s.owner) = UPPER('&p_schema'))
    GROUP BY s.owner, s.segment_name
    UNION ALL
    -- LOB sizes
    SELECT /*+ PARALLEL(s,4) */
        l.owner,
        l.table_name AS segment_name,
        0 AS table_mb,
        ROUND(SUM(s.bytes) / 1024 / 1024, 2) AS lob_mb
    FROM dba_segments s
        INNER JOIN dba_lobs l ON (s.segment_name = l.segment_name AND s.owner = l.owner)
    WHERE s.segment_type LIKE 'LOB%'
      AND (UPPER('&p_schema') = 'ALL' AND l.owner NOT IN ('SYS', 'SYSTEM', 'SYSAUX', 'DBSNMP', 'OUTLN', 'PERFSTAT', 'WMSYS', 'XDB', 'CTXSYS', 'ANONYMOUS', 'SYSMAN', 'MGMT_VIEW', 'OLAPSYS')
           OR UPPER(l.owner) = UPPER('&p_schema'))
    GROUP BY l.owner, l.table_name
) z
INNER JOIN dba_tables y ON (z.owner = y.owner AND z.segment_name = y.table_name)
GROUP BY z.owner, z.segment_name, y.partitioned, y.last_analyzed, y.num_rows
HAVING SUM(z.table_mb) + SUM(z.lob_mb) > 0
ORDER BY lob_mb DESC, total_mb, z.owner, z.segment_name;

-- Summary by Schema (only when ALL is selected)
PROMPT
PROMPT ======================================================================
PROMPT SUMMARY BY SCHEMA
PROMPT ======================================================================

COLUMN owner FORMAT A20 HEADING 'Schema|Owner'
COLUMN total_tables FORMAT 999,990 HEADING 'Total|Tables'
COLUMN total_table_mb FORMAT 999,999,990.90 HEADING 'Tables|Size (MB)'
COLUMN total_lob_mb FORMAT 999,999,990.90 HEADING 'LOBs|Size (MB)'
COLUMN total_mb FORMAT 999,999,990.90 HEADING 'Total|Size (MB)'
COLUMN total_gb FORMAT 999,990.90 HEADING 'Total|Size (GB)'

SELECT 
    owner,
    COUNT(*) AS total_tables,
    ROUND(SUM(table_mb), 2) AS total_table_mb,
    ROUND(SUM(lob_mb), 2) AS total_lob_mb,
    ROUND(SUM(table_mb) + SUM(lob_mb), 2) AS total_mb,
    ROUND((SUM(table_mb) + SUM(lob_mb)) / 1024, 2) AS total_gb
FROM (
    -- Table sizes
    SELECT 
        s.owner,
        s.segment_name,
        ROUND(SUM(s.bytes) / 1024 / 1024, 2) AS table_mb,
        0 AS lob_mb
    FROM dba_segments s
        INNER JOIN dba_tables t ON (s.segment_name = t.table_name AND s.owner = t.owner)
    WHERE s.segment_type LIKE 'TABLE%'
      AND (UPPER('&p_schema') = 'ALL' AND s.owner NOT IN ('SYS', 'SYSTEM', 'SYSAUX', 'DBSNMP', 'OUTLN', 'PERFSTAT', 'WMSYS', 'XDB', 'CTXSYS', 'ANONYMOUS', 'SYSMAN', 'MGMT_VIEW', 'OLAPSYS') 
           OR UPPER(s.owner) = UPPER('&p_schema'))
    GROUP BY s.owner, s.segment_name
    UNION ALL
    -- LOB sizes
    SELECT 
        l.owner,
        l.table_name AS segment_name,
        0 AS table_mb,
        ROUND(SUM(s.bytes) / 1024 / 1024, 2) AS lob_mb
    FROM dba_segments s
        INNER JOIN dba_lobs l ON (s.segment_name = l.segment_name AND s.owner = l.owner)
    WHERE s.segment_type LIKE 'LOB%'
      AND (UPPER('&p_schema') = 'ALL' AND l.owner NOT IN ('SYS', 'SYSTEM', 'SYSAUX', 'DBSNMP', 'OUTLN', 'PERFSTAT', 'WMSYS', 'XDB', 'CTXSYS', 'ANONYMOUS', 'SYSMAN', 'MGMT_VIEW', 'OLAPSYS')
           OR UPPER(l.owner) = UPPER('&p_schema'))
    GROUP BY l.owner, l.table_name
)
WHERE (UPPER('&p_schema') = 'ALL')
GROUP BY owner
ORDER BY total_mb DESC;

-- Reset settings
CLEAR COLUMNS
CLEAR BREAKS  
CLEAR COMPUTES
TTITLE OFF
SET VERIFY ON
SET FEEDBACK ON

PROMPT
PROMPT Execution completed!
PROMPT ======================================================================