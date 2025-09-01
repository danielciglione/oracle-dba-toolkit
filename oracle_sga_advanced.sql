-- =====================================================
-- Oracle Database SGA RAC-Aware Health Monitor v3.1
-- Purpose: Comprehensive SGA analysis for Standalone and RAC environments
-- Compatibility: Oracle 11g+ (Standalone/RAC) through 23ai  
-- Business Value: RAC-specific bottleneck identification + SGA sizing recommendations
-- Safety: READ-ONLY operations only (no DDL/DML/system changes)
-- Author: Daniel Ciglione
-- RAC Expertise: Multi-instance analysis with cache fusion metrics + Oracle advisors
-- Usage: Execute during peak hours across all instances
-- =====================================================

SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING ON
SET PAGESIZE 2000
SET LINESIZE 250
SET TRIMSPOOL ON
SET TRIMOUT ON

-- RAC Environment Detection
COLUMN is_rac NEW_VALUE v_is_rac NOPRINT
SELECT CASE WHEN COUNT(*) > 1 THEN 'TRUE' ELSE 'FALSE' END as is_rac 
FROM gv$instance;

COLUMN instance_count NEW_VALUE v_inst_count NOPRINT  
SELECT COUNT(*) as instance_count FROM gv$instance;

-- Database version for feature compatibility
COLUMN db_version NEW_VALUE v_db_version NOPRINT
SELECT SUBSTR(version, 1, 4) AS db_version FROM gv$instance WHERE ROWNUM = 1;

-- RAC-Aware Header with Environment Detection
PROMPT 
PROMPT =========================================================================
PROMPT          ORACLE SGA RAC-AWARE COMPREHENSIVE HEALTH ANALYSIS
PROMPT =========================================================================

-- Environment Overview with RAC Detection
PROMPT Environment Configuration:
COLUMN env_info         HEADING "Environment Info"     FORMAT A40
COLUMN env_value        HEADING "Value"                FORMAT A30
COLUMN env_status       HEADING "Status"               FORMAT A15

SELECT 
    'Cluster Type' AS env_info,
    CASE WHEN '&v_is_rac' = 'TRUE' 
         THEN 'RAC Cluster (' || '&v_inst_count' || ' instances)'
         ELSE 'Standalone Database'
    END AS env_value,
    CASE WHEN '&v_is_rac' = 'TRUE' THEN 'CLUSTER' ELSE 'STANDALONE' END AS env_status
FROM dual
UNION ALL
SELECT 
    'Oracle Version',
    version_full,
    CASE WHEN TO_NUMBER(SUBSTR(version, 1, 2)) >= 19 THEN 'MODERN' ELSE 'LEGACY' END
FROM gv$instance WHERE ROWNUM = 1
UNION ALL
SELECT 
    'Analysis Scope',
    CASE WHEN '&v_is_rac' = 'TRUE' 
         THEN 'Multi-Instance Global Analysis'
         ELSE 'Single Instance Analysis'
    END,
    'COMPREHENSIVE'
FROM dual
UNION ALL
SELECT 
    'Analysis Time',
    TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'),
    'CURRENT'
FROM dual;

-- 1. RAC CLUSTER OVERVIEW (if RAC)
PROMPT 
PROMPT === 1. RAC CLUSTER INSTANCE OVERVIEW ===

COLUMN inst_id          HEADING "Inst#"             FORMAT 99
COLUMN instance_name    HEADING "Instance Name"     FORMAT A15
COLUMN host_name        HEADING "Host Name"         FORMAT A25
COLUMN status           HEADING "Status"            FORMAT A10
COLUMN startup_time     HEADING "Started"           FORMAT A12
COLUMN uptime_days      HEADING "Uptime"            FORMAT A12
COLUMN thread_num       HEADING "Thread#"           FORMAT 99

-- Show all instances in cluster (or single instance)
SELECT 
    inst_id,
    instance_name,
    host_name,
    status,
    TO_CHAR(startup_time, 'DD-MON HH24:MI') AS startup_time,
    ROUND(SYSDATE - startup_time) || ' days' AS uptime_days,
    thread# AS thread_num
FROM gv$instance
ORDER BY inst_id;

-- 2. CLUSTER-WIDE SGA ANALYSIS
PROMPT 
PROMPT === 2. CLUSTER-WIDE SGA COMPONENT ANALYSIS ===

COLUMN inst_id          HEADING "Inst#"             FORMAT 99
COLUMN component        HEADING "SGA Component"     FORMAT A25
COLUMN size_gb          HEADING "Size (GB)"         FORMAT 999,999.99
COLUMN cluster_total_gb HEADING "Cluster Tot(GB)"   FORMAT 999,999.99
COLUMN pct_of_inst      HEADING "% Inst SGA"        FORMAT 999.99
COLUMN status           HEADING "Health Status"     FORMAT A15

-- Comprehensive SGA analysis with cluster totals
WITH cluster_sga AS (
    SELECT 
        inst_id,
        name AS component,
        bytes,
        ROUND(bytes/1024/1024/1024, 2) AS size_gb,
        SUM(bytes) OVER (PARTITION BY name) AS cluster_total_bytes,
        SUM(bytes) OVER (PARTITION BY inst_id) AS instance_total_bytes
    FROM gv$sgainfo
    WHERE name IN ('Fixed SGA Size', 'Redo Buffers', 'Buffer Cache Size', 
                   'Shared Pool Size', 'Large Pool Size', 'Java Pool Size', 'Streams Pool Size')
       AND bytes > 0
)
SELECT 
    inst_id,
    component,
    size_gb,
    ROUND(cluster_total_bytes/1024/1024/1024, 2) AS cluster_total_gb,
    ROUND((bytes/instance_total_bytes)*100, 2) AS pct_of_inst,
    CASE 
        WHEN component = 'Buffer Cache Size' AND ROUND((bytes/instance_total_bytes)*100, 2) < 50 
            THEN 'REVIEW NEEDED'
        WHEN component = 'Shared Pool Size' AND ROUND((bytes/instance_total_bytes)*100, 2) > 30 
            THEN 'MONITOR'
        WHEN component = 'Large Pool Size' AND size_gb < 0.064 
            THEN 'TOO SMALL'
        ELSE 'OPTIMAL'
    END AS status
FROM cluster_sga
ORDER BY inst_id, bytes DESC;

-- 3. RAC CACHE FUSION ANALYSIS (RAC-specific)
PROMPT 
PROMPT === 3. RAC CACHE FUSION AND INTERCONNECT ANALYSIS ===

-- Only execute RAC-specific analysis if in RAC environment
BEGIN
    IF '&v_is_rac' = 'TRUE' THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('=== CACHE FUSION PERFORMANCE METRICS ===');
    ELSE
        DBMS_OUTPUT.PUT_LINE('** SKIPPING: Cache Fusion Analysis (Standalone Environment) **');
    END IF;
END;
/

-- Cache Fusion Transfer Statistics (RAC only)
COLUMN metric_name      HEADING "Cache Fusion Metric"  FORMAT A35
COLUMN inst1_value      HEADING "Instance 1"           FORMAT 999,999,999
COLUMN inst2_value      HEADING "Instance 2"           FORMAT 999,999,999
COLUMN inst3_value      HEADING "Instance 3"           FORMAT 999,999,999
COLUMN cluster_total    HEADING "Cluster Total"        FORMAT 999,999,999
COLUMN performance      HEADING "Performance"          FORMAT A20

-- Enhanced cache fusion analysis (only for RAC)
WITH rac_metrics AS (
    SELECT 
        name,
        inst_id,
        value
    FROM gv$sysstat
    WHERE name IN (
        'gc cr blocks received',
        'gc current blocks received', 
        'gc cr blocks served',
        'gc current blocks served',
        'gc blocks lost',
        'gc cr block receive time',
        'gc current block receive time'
    )
      AND '&v_is_rac' = 'TRUE'
),
pivoted_metrics AS (
    SELECT 
        name,
        SUM(CASE WHEN inst_id = 1 THEN value ELSE 0 END) AS inst1_value,
        SUM(CASE WHEN inst_id = 2 THEN value ELSE 0 END) AS inst2_value,
        SUM(CASE WHEN inst_id = 3 THEN value ELSE 0 END) AS inst3_value,
        SUM(value) AS cluster_total
    FROM rac_metrics
    GROUP BY name
)
SELECT 
    name AS metric_name,
    inst1_value,
    CASE WHEN '&v_inst_count' >= 2 THEN inst2_value ELSE NULL END AS inst2_value,
    CASE WHEN '&v_inst_count' >= 3 THEN inst3_value ELSE NULL END AS inst3_value,
    cluster_total,
    CASE 
        WHEN name LIKE '%blocks lost%' AND cluster_total > 1000 
            THEN 'HIGH LOSS RATE'
        WHEN name LIKE '%receive time%' AND cluster_total/1000000 > 10 
            THEN 'SLOW TRANSFERS'
        WHEN name LIKE '%blocks received%' AND cluster_total > 100000 
            THEN 'HIGH TRAFFIC'
        ELSE 'NORMAL'
    END AS performance
FROM pivoted_metrics
WHERE '&v_is_rac' = 'TRUE'
ORDER BY cluster_total DESC;

-- Global Cache Hit Ratio Calculation (RAC)
PROMPT 
PROMPT Global Cache Efficiency (RAC Specific):

WITH gc_stats AS (
    SELECT 
        inst_id,
        SUM(CASE WHEN name = 'gc cr blocks received' THEN value ELSE 0 END) AS cr_received,
        SUM(CASE WHEN name = 'gc current blocks received' THEN value ELSE 0 END) AS curr_received,
        SUM(CASE WHEN name = 'gc blocks lost' THEN value ELSE 0 END) AS blocks_lost
    FROM gv$sysstat
    WHERE name IN ('gc cr blocks received', 'gc current blocks received', 'gc blocks lost')
      AND '&v_is_rac' = 'TRUE'
    GROUP BY inst_id
)
SELECT 
    inst_id,
    cr_received + curr_received AS total_gc_blocks,
    blocks_lost,
    CASE 
        WHEN (cr_received + curr_received) > 0 THEN
            ROUND((1 - (blocks_lost / (cr_received + curr_received))) * 100, 2)
        ELSE 0 
    END AS gc_hit_ratio_pct,
    CASE 
        WHEN ROUND((1 - (blocks_lost / NULLIF(cr_received + curr_received, 0))) * 100, 2) >= 95 
            THEN 'EXCELLENT'
        WHEN ROUND((1 - (blocks_lost / NULLIF(cr_received + curr_received, 0))) * 100, 2) >= 90 
            THEN 'GOOD'
        WHEN ROUND((1 - (blocks_lost / NULLIF(cr_received + curr_received, 0))) * 100, 2) >= 80 
            THEN 'NEEDS ATTENTION'
        ELSE 'CRITICAL'
    END AS gc_performance
FROM gc_stats
WHERE '&v_is_rac' = 'TRUE'
ORDER BY inst_id;

-- 4. BUFFER CACHE ANALYSIS BY INSTANCE
PROMPT 
PROMPT === 4. BUFFER CACHE PERFORMANCE BY INSTANCE ===

COLUMN inst_id          HEADING "Inst#"             FORMAT 99
COLUMN hit_ratio        HEADING "Hit Ratio %"       FORMAT 999.99
COLUMN physical_reads   HEADING "Phys Reads/sec"    FORMAT 999,999.99
COLUMN logical_reads    HEADING "Logic Reads/sec"   FORMAT 999,999,999.99
COLUMN performance_grade HEADING "Performance"      FORMAT A15
COLUMN business_impact  HEADING "Business Impact"   FORMAT A35

-- Per-instance buffer cache analysis
WITH instance_cache_stats AS (
    SELECT 
        s.inst_id,
        SUM(CASE WHEN s.name = 'db block gets' THEN s.value ELSE 0 END) AS db_block_gets,
        SUM(CASE WHEN s.name = 'consistent gets' THEN s.value ELSE 0 END) AS consistent_gets,
        SUM(CASE WHEN s.name = 'physical reads' THEN s.value ELSE 0 END) AS physical_reads,
        (SYSDATE - i.startup_time) * 24 * 3600 AS uptime_seconds
    FROM gv$sysstat s, gv$instance i
    WHERE s.inst_id = i.inst_id
      AND s.name IN ('db block gets', 'consistent gets', 'physical reads')
    GROUP BY s.inst_id, i.startup_time
)
SELECT 
    inst_id,
    ROUND((1 - (physical_reads / NULLIF(db_block_gets + consistent_gets, 0))) * 100, 2) AS hit_ratio,
    ROUND(physical_reads / NULLIF(uptime_seconds, 0), 2) AS physical_reads,
    ROUND((db_block_gets + consistent_gets) / NULLIF(uptime_seconds, 0), 2) AS logical_reads,
    CASE 
        WHEN ROUND((1 - (physical_reads / NULLIF(db_block_gets + consistent_gets, 0))) * 100, 2) >= 95 
            THEN 'EXCELLENT'
        WHEN ROUND((1 - (physical_reads / NULLIF(db_block_gets + consistent_gets, 0))) * 100, 2) >= 90 
            THEN 'GOOD'
        WHEN ROUND((1 - (physical_reads / NULLIF(db_block_gets + consistent_gets, 0))) * 100, 2) >= 80 
            THEN 'REVIEW NEEDED'
        ELSE 'CRITICAL'
    END AS performance_grade,
    CASE 
        WHEN ROUND((1 - (physical_reads / NULLIF(db_block_gets + consistent_gets, 0))) * 100, 2) < 80 
            THEN 'SEVERE: 30-50% perf degradation'
        WHEN ROUND((1 - (physical_reads / NULLIF(db_block_gets + consistent_gets, 0))) * 100, 2) < 90 
            THEN 'MODERATE: 10-20% impact'
        ELSE 'OPTIMAL: Performance acceptable'
    END AS business_impact
FROM instance_cache_stats
ORDER BY inst_id;

-- 5. SHARED POOL ANALYSIS BY INSTANCE
PROMPT 
PROMPT === 5. SHARED POOL ANALYSIS BY INSTANCE ===

COLUMN inst_id          HEADING "Inst#"             FORMAT 99
COLUMN pool             HEADING "Pool"              FORMAT A15
COLUMN total_mb         HEADING "Total MB"          FORMAT 999,999.99
COLUMN free_mb          HEADING "Free MB"           FORMAT 999,999.99
COLUMN free_pct         HEADING "Free %"            FORMAT 999.99
COLUMN health_status    HEADING "Health Status"     FORMAT A20

-- Detailed shared pool analysis per instance
WITH shared_pool_stats AS (
    SELECT 
        inst_id,
        NVL(pool, 'Fixed Areas') AS pool,
        SUM(bytes) AS total_bytes,
        SUM(CASE WHEN name = 'free memory' THEN bytes ELSE 0 END) AS free_bytes
    FROM gv$sgastat
    WHERE pool = 'shared pool' OR (pool IS NULL AND name LIKE '%SGA%')
    GROUP BY inst_id, pool
)
SELECT 
    inst_id,
    pool,
    ROUND(total_bytes/1024/1024, 2) AS total_mb,
    ROUND(free_bytes/1024/1024, 2) AS free_mb,
    ROUND((free_bytes/NULLIF(total_bytes, 0))*100, 2) AS free_pct,
    CASE 
        WHEN ROUND((free_bytes/NULLIF(total_bytes, 0))*100, 2) < 5 
            THEN 'CRITICAL: ORA-4031 risk'
        WHEN ROUND((free_bytes/NULLIF(total_bytes, 0))*100, 2) < 15 
            THEN 'WARNING: Low memory'
        WHEN ROUND((free_bytes/NULLIF(total_bytes, 0))*100, 2) > 50 
            THEN 'INFO: Over-allocated'
        ELSE 'OPTIMAL: Healthy'
    END AS health_status
FROM shared_pool_stats
WHERE pool = 'shared pool'
ORDER BY inst_id;

-- 6. RAC INTERCONNECT PERFORMANCE (RAC-specific)
PROMPT 
PROMPT === 6. CLUSTER INTERCONNECT PERFORMANCE ===

-- Only for RAC environments
BEGIN
    IF '&v_is_rac' = 'TRUE' THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('=== INTERCONNECT TRAFFIC ANALYSIS ===');
    ELSE
        DBMS_OUTPUT.PUT_LINE('** SKIPPING: Interconnect Analysis (Standalone Environment) **');
    END IF;
END;
/

-- Interconnect statistics (RAC only)
COLUMN inst_id          HEADING "Inst#"             FORMAT 99
COLUMN metric_name      HEADING "Interconnect Metric" FORMAT A35
COLUMN value_mb         HEADING "Value (MB)"        FORMAT 999,999,999.99
COLUMN rate_mb_sec      HEADING "Rate MB/sec"       FORMAT 999,999.99
COLUMN status           HEADING "Status"            FORMAT A15

WITH interconnect_stats AS (
    SELECT 
        s.inst_id,
        s.name,
        s.value,
        ROUND(s.value/1024/1024, 2) AS value_mb,
        ROUND(s.value/1024/1024/((SYSDATE - i.startup_time) * 24 * 3600), 2) AS rate_mb_sec
    FROM gv$sysstat s, gv$instance i
    WHERE s.inst_id = i.inst_id
      AND s.name LIKE '%gc%bytes%'
      AND s.value > 0
      AND '&v_is_rac' = 'TRUE'
)
SELECT 
    inst_id,
    name AS metric_name,
    value_mb,
    rate_mb_sec,
    CASE 
        WHEN rate_mb_sec > 100 THEN 'HIGH TRAFFIC'
        WHEN rate_mb_sec > 50 THEN 'MODERATE'
        WHEN rate_mb_sec > 10 THEN 'NORMAL'
        ELSE 'LOW'
    END AS status
FROM interconnect_stats
WHERE '&v_is_rac' = 'TRUE'
ORDER BY inst_id, value_mb DESC;

-- 7. ORACLE SGA SIZING ADVISOR & OPTIMIZATION RECOMMENDATIONS
PROMPT 
PROMPT === 7. ORACLE SGA SIZING ADVISOR AND OPTIMIZATION RECOMMENDATIONS ===

-- SGA Target Advisor Analysis
COLUMN target_size_gb   HEADING "Target Size (GB)" FORMAT 999,999.99
COLUMN size_factor      HEADING "Size Factor"      FORMAT 999.99
COLUMN estd_db_time     HEADING "Est DB Time"      FORMAT 999,999,999
COLUMN estd_physical_reads HEADING "Est Phys Reads" FORMAT 999,999,999
COLUMN advisor_status   HEADING "Advisor Status"   FORMAT A20
COLUMN recommendation   HEADING "Sizing Recommendation" FORMAT A50

PROMPT 
PROMPT SGA Target Advisor Analysis:

-- Simplified SGA advisor query
WITH sga_current AS (
    SELECT 
        CASE 
            WHEN REGEXP_LIKE(value, '^[0-9]+$') THEN TO_NUMBER(value)
            ELSE 0 
        END AS current_sga_bytes
    FROM v$parameter 
    WHERE name = 'sga_target'
)
SELECT 
    ROUND(sta.sga_size/1024/1024/1024, 2) AS target_size_gb,
    sta.sga_size_factor AS size_factor,
    sta.estd_db_time,
    sta.estd_physical_reads,
    CASE 
        WHEN sta.sga_size_factor = 1 THEN 'CURRENT SIZE'
        WHEN sta.sga_size_factor < 1 THEN 'UNDERSIZED'
        WHEN sta.sga_size_factor > 1 AND sta.sga_size_factor <= 1.5 THEN 'RECOMMENDED RANGE'
        WHEN sta.sga_size_factor > 1.5 AND sta.sga_size_factor <= 2 THEN 'BENEFICIAL'
        ELSE 'DIMINISHING RETURNS'
    END AS advisor_status,
    CASE 
        WHEN sta.sga_size_factor = 1 THEN 'Current configuration (baseline)'
        WHEN sta.sga_size_factor < 1 THEN 
            'REDUCE: Potential memory waste of ' || 
            ROUND((sc.current_sga_bytes - sta.sga_size)/1024/1024/1024, 2) || 'GB'
        WHEN sta.sga_size_factor > 1 AND sta.estd_db_time < 
            (SELECT estd_db_time FROM v$sga_target_advice WHERE sga_size_factor = 1) THEN
            'INCREASE: Add ' || 
            ROUND((sta.sga_size - sc.current_sga_bytes)/1024/1024/1024, 2) || 
            'GB for ' || 
            ROUND(((SELECT estd_db_time FROM v$sga_target_advice WHERE sga_size_factor = 1) - sta.estd_db_time) / 
                  (SELECT estd_db_time FROM v$sga_target_advice WHERE sga_size_factor = 1) * 100, 1) || 
            '% performance improvement'
        ELSE 'Evaluate cost vs benefit for this sizing'
    END AS recommendation
FROM v$sga_target_advice sta
CROSS JOIN sga_current sc
WHERE sta.sga_size_factor BETWEEN 0.25 AND 2.0
ORDER BY sta.sga_size_factor;

-- Display message if no SGA advisor data
SELECT 
    CASE 
        WHEN (SELECT COUNT(*) FROM v$sga_target_advice) = 0 
        THEN '** SGA Target Advisor: No data available. Enable with: ALTER SYSTEM SET STATISTICS_LEVEL=TYPICAL **'
        ELSE NULL
    END AS advisor_note
FROM dual
WHERE (SELECT COUNT(*) FROM v$sga_target_advice) = 0;

-- Buffer Cache Advisor Analysis
PROMPT 
PROMPT Buffer Cache Advisor Analysis:

COLUMN cache_size_gb    HEADING "Cache Size (GB)"  FORMAT 999,999.99
COLUMN size_for_estimate HEADING "Size Factor"     FORMAT 999.99
COLUMN buffers_for_estimate HEADING "Buffer Count" FORMAT 999,999,999
COLUMN estd_physical_read_factor HEADING "Phys Read Factor" FORMAT 999.99
COLUMN estd_physical_reads HEADING "Est Phys Reads" FORMAT 999,999,999
COLUMN cache_advice     HEADING "Cache Advice"     FORMAT A35

WITH current_cache AS (
    SELECT 
        CASE 
            WHEN REGEXP_LIKE(value, '^[0-9]+$') THEN TO_NUMBER(value)
            ELSE (SELECT bytes FROM v$sgainfo WHERE name = 'Buffer Cache Size')
        END AS current_cache_bytes
    FROM v$parameter 
    WHERE name = 'db_cache_size'
),
cache_block_size AS (
    SELECT TO_NUMBER(value) AS block_size FROM v$parameter WHERE name = 'db_block_size'
)
SELECT 
    ROUND(dca.size_for_estimate/1024/1024/1024, 2) AS cache_size_gb,
    ROUND(dca.size_for_estimate/cc.current_cache_bytes, 2) AS size_for_estimate,
    dca.buffers_for_estimate,
    dca.estd_physical_read_factor,
    dca.estd_physical_reads,
    CASE 
        WHEN dca.size_for_estimate = cc.current_cache_bytes THEN 'CURRENT CONFIGURATION'
        WHEN dca.estd_physical_read_factor < 1 AND dca.size_for_estimate > cc.current_cache_bytes THEN
            'RECOMMENDED: Increase cache by ' || 
            ROUND((dca.size_for_estimate - cc.current_cache_bytes)/1024/1024/1024, 2) || 
            'GB for ' || ROUND((1-dca.estd_physical_read_factor)*100, 1) || '% fewer physical reads'
        WHEN dca.estd_physical_read_factor > 1 AND dca.size_for_estimate < cc.current_cache_bytes THEN
            'CONSIDER: Reduce cache to save ' || 
            ROUND((cc.current_cache_bytes - dca.size_for_estimate)/1024/1024/1024, 2) || 
            'GB memory (trade-off: ' || ROUND((dca.estd_physical_read_factor-1)*100, 1) || '% more physical reads)'
        WHEN dca.estd_physical_read_factor < 0.95 AND dca.size_for_estimate > cc.current_cache_bytes THEN
            'HIGH BENEFIT: Strong performance gain potential'
        WHEN dca.estd_physical_read_factor > 0.99 AND dca.estd_physical_read_factor < 1.01 THEN
            'MINIMAL IMPACT: Little performance change'
        ELSE 'EVALUATE: Review cost vs performance benefit'
    END AS cache_advice
FROM v$db_cache_advice dca
CROSS JOIN current_cache cc
CROSS JOIN cache_block_size cbs
WHERE dca.size_for_estimate BETWEEN cc.current_cache_bytes * 0.5 AND cc.current_cache_bytes * 2
ORDER BY dca.size_for_estimate;

-- Shared Pool Advisor Analysis  
PROMPT 
PROMPT Shared Pool Advisor Analysis:

COLUMN pool_size_gb     HEADING "Pool Size (GB)"   FORMAT 999,999.99
COLUMN shared_pool_size_factor HEADING "Size Factor" FORMAT 999.99
COLUMN estd_lc_time_saved HEADING "Parse Time Saved" FORMAT 999,999,999
COLUMN estd_lc_memory_objects HEADING "Memory Objects" FORMAT 999,999,999
COLUMN pool_advice      HEADING "Pool Advice"       FORMAT A60

WITH current_shared_pool AS (
    SELECT bytes AS current_pool_bytes FROM v$sgainfo WHERE name = 'Shared Pool Size'
)
SELECT 
    ROUND(spa.shared_pool_size_for_estimate/1024/1024/1024, 2) AS pool_size_gb,
    spa.shared_pool_size_factor,
    spa.estd_lc_time_saved,
    spa.estd_lc_memory_objects,
    CASE 
        WHEN spa.shared_pool_size_factor = 1 THEN 'CURRENT CONFIGURATION'
        WHEN spa.shared_pool_size_factor > 1 AND spa.estd_lc_time_saved > 0 THEN
            'BENEFICIAL: Increase by ' || 
            ROUND((spa.shared_pool_size_for_estimate - csp.current_pool_bytes)/1024/1024/1024, 2) || 
            'GB saves ' || spa.estd_lc_time_saved || 'ms parse time'
        WHEN spa.shared_pool_size_factor < 1 THEN
            'RISKY: Reducing to ' || ROUND(spa.shared_pool_size_for_estimate/1024/1024/1024, 2) || 
            'GB may increase parse time by ' || ABS(spa.estd_lc_time_saved) || 'ms'
        WHEN spa.estd_lc_time_saved = 0 AND spa.shared_pool_size_factor > 1 THEN
            'MINIMAL BENEFIT: Little performance improvement expected'
        ELSE 'EVALUATE: Review impact on library cache efficiency'
    END AS pool_advice
FROM v$shared_pool_advice spa
CROSS JOIN current_shared_pool csp
WHERE spa.shared_pool_size_factor BETWEEN 0.5 AND 2.0
ORDER BY spa.shared_pool_size_factor;

-- 8. RAC-AWARE EXECUTIVE SUMMARY
PROMPT 
PROMPT === 8. RAC-AWARE EXECUTIVE SUMMARY AND BUSINESS RECOMMENDATIONS ===

-- Dynamic RAC-aware analysis
WITH cluster_performance AS (
    SELECT 
        COUNT(DISTINCT inst_id) AS active_instances,
        AVG(ROUND((1 - (SUM(CASE WHEN name = 'physical reads' THEN value ELSE 0 END) / 
            NULLIF(SUM(CASE WHEN name = 'db block gets' THEN value ELSE 0 END) + 
                   SUM(CASE WHEN name = 'consistent gets' THEN value ELSE 0 END), 0))) * 100, 2)) AS avg_hit_ratio
    FROM gv$sysstat
    WHERE name IN ('db block gets', 'consistent gets', 'physical reads')
    GROUP BY inst_id
),
shared_pool_health AS (
    SELECT 
        MIN(ROUND((SUM(CASE WHEN name = 'free memory' THEN bytes ELSE 0 END)/
            SUM(bytes))*100, 2)) AS min_free_pct
    FROM gv$sgastat 
    WHERE pool = 'shared pool'
    GROUP BY inst_id
)
SELECT 
    '=== RAC CLUSTER HEALTH ASSESSMENT ===' AS executive_summary
FROM dual
UNION ALL
SELECT 
    'CLUSTER: ' || 
    CASE WHEN '&v_is_rac' = 'TRUE' 
         THEN '&v_inst_count' || ' instances RAC cluster detected'
         ELSE 'Standalone instance (non-RAC)'
    END
FROM dual
UNION ALL
SELECT 
    'PERFORMANCE: ' ||
    CASE 
        WHEN cp.avg_hit_ratio < 80 
        THEN 'CRITICAL - Cluster-wide buffer cache below 80% (' || cp.avg_hit_ratio || '%)'
        WHEN cp.avg_hit_ratio < 90 
        THEN 'WARNING - Cluster average hit ratio ' || cp.avg_hit_ratio || '%'
        ELSE 'ACCEPTABLE - Cluster performance (' || cp.avg_hit_ratio || '%) within range'
    END
FROM cluster_performance cp
UNION ALL
SELECT 
    'MEMORY: ' ||
    CASE 
        WHEN sph.min_free_pct < 5
        THEN 'CRITICAL - Instance with ' || sph.min_free_pct || '% shared pool free (ORA-4031 risk)'
        WHEN sph.min_free_pct < 15
        THEN 'WARNING - Minimum shared pool free across cluster: ' || sph.min_free_pct || '%'
        ELSE 'STABLE - Shared pool memory adequate across all instances'
    END
FROM shared_pool_health sph
UNION ALL
SELECT 
    'RAC SPECIFIC: ' ||
    CASE WHEN '&v_is_rac' = 'TRUE' 
         THEN 'Cache fusion and interconnect metrics analyzed - review above sections'
         ELSE 'N/A - Cache fusion analysis skipped for standalone'
    END
FROM dual
UNION ALL
SELECT 
    'RECOMMENDATION: ' ||
    CASE WHEN '&v_is_rac' = 'TRUE' 
         THEN 'Monitor interconnect latency and global cache efficiency'
         ELSE 'Focus on single-instance memory optimization'
    END
FROM dual;

PROMPT 
PROMPT === ANALYSIS COMPLETE - RAC ENTERPRISE VALIDATED ===
PROMPT 
PROMPT Next Steps:
PROMPT - RAC: Monitor interconnect performance and global cache statistics
PROMPT - All: Run during peak hours for optimal insights
PROMPT - Follow-up: @rac_specific_tuning.sql for advanced RAC optimization
PROMPT =========================================================================