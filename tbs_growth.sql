-- =====================================================================
-- OPTIMIZED TABLESPACE GROWTH ANALYSIS SCRIPT
-- =====================================================================
-- Description: High-performance tablespace growth analysis with corrected syntax
-- Parameters: 
--   &tablespace_name - Tablespace name (or % for all)
--   &days_back - Number of days to analyze (default: 30)
-- Author: Daniel Oliveira
-- Performance: Added indexes hints and optimized CTEs for production use
-- =====================================================================

-- Set formatting parameters
SET PAGESIZE 100
SET LINESIZE 200
SET FEEDBACK OFF
SET VERIFY OFF
SET TIMING ON

-- Define column formatting
COLUMN tablespace_name FORMAT A20 HEADING "Tablespace Name"
COLUMN analysis_date FORMAT A12 HEADING "Date"
COLUMN allocated_gb FORMAT 999,999.99 HEADING "Allocated|GB"
COLUMN used_gb FORMAT 999,999.99 HEADING "Used|GB"
COLUMN free_gb FORMAT 999,999.99 HEADING "Free|GB"
COLUMN usage_pct FORMAT 999.99 HEADING "Usage|%"
COLUMN daily_growth_mb FORMAT 999,999.99 HEADING "Daily Growth|MB"
COLUMN avg_growth_mb FORMAT 999,999.99 HEADING "Avg Growth|MB/Day"
COLUMN max_growth_mb FORMAT 999,999.99 HEADING "Max Growth|MB/Day"
COLUMN min_growth_mb FORMAT 999,999.99 HEADING "Min Growth|MB/Day"
COLUMN growth_trend FORMAT A15 HEADING "Growth Trend"
COLUMN days_analyzed FORMAT 999 HEADING "Days|Analyzed"
COLUMN total_growth_gb FORMAT 999,999.99 HEADING "Total Growth|GB"

-- Accept parameters with defaults
ACCEPT tablespace_name CHAR PROMPT 'Enter Tablespace Name (% for all): ' DEFAULT '%'
ACCEPT days_back NUMBER PROMPT 'Enter number of days to analyze: ' DEFAULT 30

PROMPT
PROMPT =====================================================================
PROMPT                OPTIMIZED TABLESPACE GROWTH ANALYSIS REPORT
PROMPT =====================================================================
PROMPT Analysis Parameters:
PROMPT   Tablespace(s): &tablespace_name
PROMPT   Period: Last &days_back days
PROMPT   Report Date: 
SELECT TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI:SS') AS current_timestamp FROM DUAL;
PROMPT =====================================================================

-- =====================================================================
-- SECTION 1: EXECUTIVE SUMMARY
-- =====================================================================
PROMPT
PROMPT *** EXECUTIVE SUMMARY ***
PROMPT

WITH tablespace_summary AS (
    SELECT /*+ USE_NL(tsu ts sp dt) INDEX(sp, DBA_HIST_SNAPSHOT_N1) */
        ts.tsname AS tablespace_name,
        COUNT(DISTINCT TO_CHAR(sp.begin_interval_time,'YYYY-MM-DD')) AS days_analyzed,
        MIN(ROUND((tsu.tablespace_usedsize * dt.block_size)/(1024*1024*1024),2)) AS min_used_gb,
        MAX(ROUND((tsu.tablespace_usedsize * dt.block_size)/(1024*1024*1024),2)) AS max_used_gb,
        MAX(ROUND((tsu.tablespace_size * dt.block_size)/(1024*1024*1024),2)) AS allocated_gb,
        ROUND(AVG((tsu.tablespace_usedsize * dt.block_size)/(1024*1024*1024)),2) AS avg_used_gb
    FROM 
        DBA_HIST_TBSPC_SPACE_USAGE tsu,
        DBA_HIST_TABLESPACE_STAT ts,
        DBA_HIST_SNAPSHOT sp,
        DBA_TABLESPACES dt
    WHERE 
        tsu.tablespace_id = ts.ts#
        AND tsu.snap_id = sp.snap_id
        AND tsu.dbid = sp.dbid
        AND ts.tsname = dt.tablespace_name
        AND sp.begin_interval_time >= SYSDATE - &days_back
        AND sp.begin_interval_time < SYSDATE
        AND UPPER(dt.tablespace_name) LIKE UPPER('&tablespace_name')
        AND dt.contents NOT IN ('UNDO', 'TEMPORARY')
    GROUP BY ts.tsname
)
SELECT 
    tablespace_name,
    days_analyzed,
    allocated_gb,
    max_used_gb AS current_used_gb,
    (allocated_gb - max_used_gb) AS free_gb,
    ROUND((max_used_gb / NULLIF(allocated_gb, 0)) * 100, 2) AS usage_pct,
    (max_used_gb - min_used_gb) AS total_growth_gb,
    ROUND((max_used_gb - min_used_gb) / NULLIF(days_analyzed, 0), 2) AS avg_growth_gb_day,
    CASE 
        WHEN (max_used_gb - min_used_gb) > 1 THEN 'HIGH GROWTH'
        WHEN (max_used_gb - min_used_gb) > 0.1 THEN 'MODERATE GROWTH'
        WHEN (max_used_gb - min_used_gb) > 0 THEN 'LOW GROWTH'
        ELSE 'NO GROWTH'
    END AS growth_trend
FROM tablespace_summary
WHERE days_analyzed > 0
ORDER BY total_growth_gb DESC;

-- =====================================================================
-- SECTION 2: DAILY GROWTH ANALYSIS
-- =====================================================================
PROMPT
PROMPT *** DAILY GROWTH DETAILS (Last 15 Days) ***
PROMPT

WITH daily_usage AS (
    SELECT /*+ PARALLEL(4) */
        TO_CHAR(sp.begin_interval_time,'YYYY-MM-DD') AS analysis_date,
        ts.tsname AS tablespace_name,
        MAX(ROUND((tsu.tablespace_size * dt.block_size)/(1024*1024*1024),2)) AS allocated_gb,
        MAX(ROUND((tsu.tablespace_usedsize * dt.block_size)/(1024*1024*1024),2)) AS used_gb
    FROM 
        DBA_HIST_TBSPC_SPACE_USAGE tsu,
        DBA_HIST_TABLESPACE_STAT ts,
        DBA_HIST_SNAPSHOT sp,
        DBA_TABLESPACES dt
    WHERE 
        tsu.tablespace_id = ts.ts#
        AND tsu.snap_id = sp.snap_id
        AND tsu.dbid = sp.dbid
        AND ts.tsname = dt.tablespace_name
        AND sp.begin_interval_time >= SYSDATE - LEAST(&days_back, 15)  -- Limit to 15 days for performance
        AND sp.begin_interval_time < SYSDATE
        AND UPPER(dt.tablespace_name) LIKE UPPER('&tablespace_name')
        AND dt.contents NOT IN ('UNDO', 'TEMPORARY')
    GROUP BY TO_CHAR(sp.begin_interval_time,'YYYY-MM-DD'), ts.tsname
),
growth_analysis AS (
    SELECT 
        analysis_date,
        tablespace_name,
        allocated_gb,
        used_gb,
        (allocated_gb - used_gb) AS free_gb,
        ROUND((used_gb / NULLIF(allocated_gb, 0)) * 100, 2) AS usage_pct,
        ROUND((used_gb - LAG(used_gb, 1) OVER (PARTITION BY tablespace_name ORDER BY analysis_date)) * 1024, 2) AS daily_growth_mb,
        ROW_NUMBER() OVER (PARTITION BY tablespace_name ORDER BY analysis_date) AS day_seq
    FROM daily_usage
)
SELECT 
    tablespace_name,
    analysis_date,
    allocated_gb,
    used_gb,
    free_gb,
    usage_pct,
    CASE 
        WHEN day_seq = 1 THEN 0
        WHEN daily_growth_mb IS NULL THEN 0
        ELSE daily_growth_mb 
    END AS daily_growth_mb,
    CASE 
        WHEN day_seq = 1 THEN 'BASELINE'
        WHEN daily_growth_mb > 500 THEN 'HIGH'
        WHEN daily_growth_mb > 100 THEN 'MODERATE'
        WHEN daily_growth_mb > 0 THEN 'LOW'
        WHEN daily_growth_mb = 0 THEN 'NONE'
        WHEN daily_growth_mb IS NULL THEN 'NO DATA'
        ELSE 'REDUCED'
    END AS growth_level
FROM growth_analysis
ORDER BY tablespace_name, analysis_date DESC;

-- =====================================================================
-- SECTION 3: GROWTH STATISTICS
-- =====================================================================
PROMPT
PROMPT *** GROWTH STATISTICS ***
PROMPT

WITH daily_growth AS (
    SELECT 
        ts.tsname AS tablespace_name,
        TO_CHAR(sp.begin_interval_time,'YYYY-MM-DD') AS analysis_date,
        MAX(ROUND((tsu.tablespace_usedsize * dt.block_size)/(1024*1024),2)) AS used_mb
    FROM 
        DBA_HIST_TBSPC_SPACE_USAGE tsu,
        DBA_HIST_TABLESPACE_STAT ts,
        DBA_HIST_SNAPSHOT sp,
        DBA_TABLESPACES dt
    WHERE 
        tsu.tablespace_id = ts.ts#
        AND tsu.snap_id = sp.snap_id
        AND tsu.dbid = sp.dbid
        AND ts.tsname = dt.tablespace_name
        AND sp.begin_interval_time >= SYSDATE - &days_back
        AND sp.begin_interval_time < SYSDATE
        AND UPPER(dt.tablespace_name) LIKE UPPER('&tablespace_name')
        AND dt.contents NOT IN ('UNDO', 'TEMPORARY')
    GROUP BY TO_CHAR(sp.begin_interval_time,'YYYY-MM-DD'), ts.tsname
),
growth_calc AS (
    SELECT 
        tablespace_name,
        analysis_date,
        used_mb,
        used_mb - LAG(used_mb, 1) OVER (PARTITION BY tablespace_name ORDER BY analysis_date) AS daily_growth_mb
    FROM daily_growth
)
SELECT 
    tablespace_name,
    COUNT(*) - 1 AS days_with_data,
    ROUND(AVG(daily_growth_mb), 2) AS avg_growth_mb,
    ROUND(MAX(daily_growth_mb), 2) AS max_growth_mb,
    ROUND(MIN(daily_growth_mb), 2) AS min_growth_mb,
    ROUND(STDDEV(daily_growth_mb), 2) AS stddev_growth_mb,
    COUNT(CASE WHEN daily_growth_mb > 0 THEN 1 END) AS days_with_growth,
    COUNT(CASE WHEN daily_growth_mb = 0 THEN 1 END) AS days_no_growth,
    COUNT(CASE WHEN daily_growth_mb < 0 THEN 1 END) AS days_with_reduction,
    ROUND((COUNT(CASE WHEN daily_growth_mb > 0 THEN 1 END) / NULLIF(COUNT(*) - 1, 0)) * 100, 2) AS growth_frequency_pct
FROM growth_calc
WHERE daily_growth_mb IS NOT NULL
GROUP BY tablespace_name
HAVING COUNT(*) > 1
ORDER BY avg_growth_mb DESC;

-- =====================================================================
-- SECTION 4: GROWTH PROJECTION
-- =====================================================================
PROMPT
PROMPT *** GROWTH PROJECTION (Next 30 Days) ***
PROMPT

WITH daily_data AS (
    SELECT 
        ts.tsname AS tablespace_name,
        TO_CHAR(sp.begin_interval_time,'YYYY-MM-DD') AS analysis_date,
        MAX(ROUND((tsu.tablespace_size * dt.block_size)/(1024*1024*1024),2)) AS allocated_gb,
        MAX(ROUND((tsu.tablespace_usedsize * dt.block_size)/(1024*1024*1024),2)) AS used_gb
    FROM 
        DBA_HIST_TBSPC_SPACE_USAGE tsu,
        DBA_HIST_TABLESPACE_STAT ts,
        DBA_HIST_SNAPSHOT sp,
        DBA_TABLESPACES dt
    WHERE 
        tsu.tablespace_id = ts.ts#
        AND tsu.snap_id = sp.snap_id
        AND tsu.dbid = sp.dbid
        AND ts.tsname = dt.tablespace_name
        AND sp.begin_interval_time >= SYSDATE - LEAST(&days_back, 14)  -- Use last 14 days for projection
        AND sp.begin_interval_time < SYSDATE
        AND UPPER(dt.tablespace_name) LIKE UPPER('&tablespace_name')
        AND dt.contents NOT IN ('UNDO', 'TEMPORARY')
    GROUP BY TO_CHAR(sp.begin_interval_time,'YYYY-MM-DD'), ts.tsname
),
growth_data AS (
    SELECT 
        tablespace_name,
        analysis_date,
        allocated_gb,
        used_gb,
        used_gb - LAG(used_gb, 1) OVER (PARTITION BY tablespace_name ORDER BY analysis_date) AS daily_growth_gb
    FROM daily_data
),
recent_growth AS (
    SELECT 
        tablespace_name,
        MAX(allocated_gb) AS current_allocated_gb,
        MAX(used_gb) AS current_used_gb,
        ROUND(AVG(daily_growth_gb), 3) AS avg_daily_growth_gb
    FROM growth_data
    WHERE daily_growth_gb IS NOT NULL
    GROUP BY tablespace_name
)
SELECT 
    tablespace_name,
    current_allocated_gb,
    current_used_gb,
    (current_allocated_gb - current_used_gb) AS current_free_gb,
    ROUND((current_used_gb / NULLIF(current_allocated_gb, 0)) * 100, 2) AS current_usage_pct,
    CASE 
        WHEN avg_daily_growth_gb IS NULL OR avg_daily_growth_gb <= 0 THEN 0
        ELSE ROUND(avg_daily_growth_gb * 30, 2)
    END AS projected_30day_growth_gb,
    CASE 
        WHEN avg_daily_growth_gb IS NULL OR avg_daily_growth_gb <= 0 THEN current_used_gb
        ELSE ROUND(current_used_gb + (avg_daily_growth_gb * 30), 2)
    END AS projected_used_gb,
    CASE 
        WHEN avg_daily_growth_gb IS NULL OR avg_daily_growth_gb <= 0 THEN 
            ROUND((current_used_gb / NULLIF(current_allocated_gb, 0)) * 100, 2)
        ELSE 
            ROUND(((current_used_gb + (avg_daily_growth_gb * 30)) / NULLIF(current_allocated_gb, 0)) * 100, 2)
    END AS projected_usage_pct,
    CASE 
        WHEN avg_daily_growth_gb IS NULL OR avg_daily_growth_gb <= 0 THEN 'NO GROWTH TREND'
        WHEN ((current_used_gb + (avg_daily_growth_gb * 30)) / NULLIF(current_allocated_gb, 0)) > 0.90 THEN 'CRITICAL - ACTION NEEDED'
        WHEN ((current_used_gb + (avg_daily_growth_gb * 30)) / NULLIF(current_allocated_gb, 0)) > 0.80 THEN 'WARNING - MONITOR CLOSELY'
        WHEN ((current_used_gb + (avg_daily_growth_gb * 30)) / NULLIF(current_allocated_gb, 0)) > 0.70 THEN 'CAUTION - PLAN EXPANSION'
        ELSE 'NORMAL'
    END AS risk_assessment
FROM recent_growth
ORDER BY projected_usage_pct DESC;

-- =====================================================================
-- SECTION 5: SPACE ALLOCATION RECOMMENDATIONS
-- =====================================================================
PROMPT
PROMPT *** SPACE ALLOCATION RECOMMENDATIONS ***
PROMPT

WITH daily_data AS (
    SELECT 
        ts.tsname AS tablespace_name,
        TO_CHAR(sp.begin_interval_time,'YYYY-MM-DD') AS analysis_date,
        MAX(ROUND((tsu.tablespace_size * dt.block_size)/(1024*1024*1024),2)) AS allocated_gb,
        MAX(ROUND((tsu.tablespace_usedsize * dt.block_size)/(1024*1024*1024),2)) AS used_gb
    FROM 
        DBA_HIST_TBSPC_SPACE_USAGE tsu,
        DBA_HIST_TABLESPACE_STAT ts,
        DBA_HIST_SNAPSHOT sp,
        DBA_TABLESPACES dt
    WHERE 
        tsu.tablespace_id = ts.ts#
        AND tsu.snap_id = sp.snap_id
        AND tsu.dbid = sp.dbid
        AND ts.tsname = dt.tablespace_name
        AND sp.begin_interval_time >= SYSDATE - &days_back
        AND sp.begin_interval_time < SYSDATE
        AND UPPER(dt.tablespace_name) LIKE UPPER('&tablespace_name')
        AND dt.contents NOT IN ('UNDO', 'TEMPORARY')
    GROUP BY TO_CHAR(sp.begin_interval_time,'YYYY-MM-DD'), ts.tsname
),
growth_data AS (
    SELECT 
        tablespace_name,
        analysis_date,
        allocated_gb,
        used_gb,
        used_gb - LAG(used_gb, 1) OVER (PARTITION BY tablespace_name ORDER BY analysis_date) AS daily_growth_gb
    FROM daily_data
),
current_status AS (
    SELECT 
        tablespace_name,
        MAX(allocated_gb) AS current_allocated_gb,
        MAX(used_gb) AS current_used_gb,
        AVG(daily_growth_gb) AS avg_daily_growth_gb
    FROM growth_data
    WHERE daily_growth_gb IS NOT NULL
    GROUP BY tablespace_name
)
SELECT 
    tablespace_name,
    current_allocated_gb,
    current_used_gb,
    ROUND((current_used_gb / NULLIF(current_allocated_gb, 0)) * 100, 2) AS current_usage_pct,
    CASE 
        WHEN (current_used_gb / NULLIF(current_allocated_gb, 0)) > 0.85 THEN 
            ROUND(current_allocated_gb * 0.5, 2)  -- Add 50% if usage > 85%
        WHEN (current_used_gb / NULLIF(current_allocated_gb, 0)) > 0.70 THEN 
            ROUND(current_allocated_gb * 0.3, 2)  -- Add 30% if usage > 70%
        WHEN NVL(avg_daily_growth_gb, 0) > 0.1 THEN 
            ROUND(avg_daily_growth_gb * 90, 2)    -- Add 90 days worth of growth
        ELSE 0
    END AS recommended_addition_gb,
    CASE 
        WHEN (current_used_gb / NULLIF(current_allocated_gb, 0)) > 0.85 THEN 'IMMEDIATE'
        WHEN (current_used_gb / NULLIF(current_allocated_gb, 0)) > 0.70 THEN 'WITHIN 30 DAYS'
        WHEN NVL(avg_daily_growth_gb, 0) > 0.1 THEN 'WITHIN 60 DAYS'
        ELSE 'NO ACTION NEEDED'
    END AS urgency,
    CASE 
        WHEN (current_used_gb / NULLIF(current_allocated_gb, 0)) > 0.85 THEN 'High usage detected'
        WHEN (current_used_gb / NULLIF(current_allocated_gb, 0)) > 0.70 THEN 'Moderate usage, plan expansion'
        WHEN NVL(avg_daily_growth_gb, 0) > 0.1 THEN 'Consistent growth pattern'
        ELSE 'Tablespace stable'
    END AS reason
FROM current_status
ORDER BY current_usage_pct DESC;

-- =====================================================================
-- SECTION 6: QUICK DISK SPACE CHECK
-- =====================================================================
PROMPT
PROMPT *** CURRENT DISK SPACE STATUS ***
PROMPT

SELECT 
    df.tablespace_name,
    ROUND(SUM(df.bytes)/(1024*1024*1024), 2) AS allocated_gb,
    ROUND(SUM(CASE WHEN df.autoextensible = 'YES' 
                   THEN df.maxbytes 
                   ELSE df.bytes END)/(1024*1024*1024), 2) AS max_possible_gb,
    ROUND((SUM(df.bytes) - NVL(fs.free_bytes, 0))/(1024*1024*1024), 2) AS used_gb,
    ROUND(NVL(fs.free_bytes, 0)/(1024*1024*1024), 2) AS free_gb,
    ROUND((SUM(df.bytes) - NVL(fs.free_bytes, 0))/SUM(df.bytes) * 100, 2) AS usage_pct,
    COUNT(df.file_id) AS datafiles
FROM 
    dba_data_files df,
    (SELECT 
         tablespace_name, 
         SUM(bytes) AS free_bytes 
     FROM dba_free_space 
     GROUP BY tablespace_name) fs
WHERE 
    df.tablespace_name = fs.tablespace_name(+)
    AND UPPER(df.tablespace_name) LIKE UPPER('&tablespace_name')
GROUP BY 
    df.tablespace_name, fs.free_bytes
ORDER BY 
    usage_pct DESC;

PROMPT
PROMPT =====================================================================
PROMPT                          END OF REPORT
PROMPT =====================================================================
PROMPT
PROMPT Performance Notes:
PROMPT - Script optimized for production environments
PROMPT - Added parallel processing hints where appropriate
PROMPT - Limited daily analysis to 15 days for performance
PROMPT - Fixed window function nesting issues
PROMPT - Added proper NULL handling throughout
PROMPT
PROMPT Next Steps:
PROMPT 1. Review tablespaces with HIGH GROWTH trend
PROMPT 2. Address any CRITICAL or WARNING risk assessments
PROMPT 3. Schedule proactive expansions based on recommendations
PROMPT 4. Monitor daily for sudden growth spikes
PROMPT

-- Reset formatting
SET PAGESIZE 14
SET LINESIZE 80
SET FEEDBACK ON
SET VERIFY ON
SET TIMING OFF