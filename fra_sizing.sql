-- =====================================================
-- Oracle FRA Sizing Analysis
-- =====================================================
-- Corrected calculation issues and exception handling
-- =====================================================
-- Author: Daniel Oliveira - August 2025
-- =====================================================

-- Enable output
SET SERVEROUTPUT ON SIZE UNLIMITED
SET ECHO OFF
SET VERIFY OFF
SET FEEDBACK OFF
SET HEADING ON
SET PAGESIZE 1000
SET LINESIZE 200
SET TRIMSPOOL ON
SET TRIMOUT ON

-- Variables for environment detection
COLUMN is_rac NEW_VALUE v_is_rac NOPRINT
COLUMN instance_count NEW_VALUE v_instance_count NOPRINT
COLUMN archive_mode NEW_VALUE v_archive_mode NOPRINT

-- Detect environment
SELECT 
    CASE WHEN value = 'TRUE' THEN 'Y' ELSE 'N' END AS is_rac,
    (SELECT COUNT(*) FROM gv$instance) AS instance_count,
    (SELECT log_mode FROM v$database) AS archive_mode
FROM v$parameter 
WHERE name = 'cluster_database';

PROMPT 
PROMPT =====================================================
PROMPT    ORACLE FRA SIZING ANALYSIS v2.0
PROMPT =====================================================
PROMPT

-- Database Information
PROMPT *** DATABASE INFORMATION ***
SELECT 
    name AS database_name,
    DECODE('&v_is_rac', 
           'Y', 'RAC (' || &v_instance_count || ' nodes)',
           'Single Instance') AS environment,
    log_mode AS archive_mode,
    flashback_on,
    platform_name
FROM v$database;

PROMPT
PROMPT *** DATABASE SIZE ***
SELECT 
    ROUND(SUM(bytes)/1024/1024/1024, 2) AS total_datafiles_gb,
    ROUND(SUM(bytes)/1024/1024/1024/1024, 2) AS total_datafiles_tb
FROM v$datafile;

PROMPT
PROMPT *** CURRENT FRA CONFIGURATION ***
DECLARE
    v_fra_configured VARCHAR2(10) := 'NO';
    v_fra_location VARCHAR2(500);
    v_fra_size NUMBER;
    v_fra_used NUMBER;
    v_fra_pct NUMBER;
BEGIN
    BEGIN
        SELECT 'YES', name, space_limit, space_used, 
               ROUND((space_used/space_limit)*100, 2)
        INTO v_fra_configured, v_fra_location, v_fra_size, v_fra_used, v_fra_pct
        FROM v$recovery_file_dest
        WHERE ROWNUM = 1;
        
        DBMS_OUTPUT.PUT_LINE('FRA Status:        CONFIGURED');
        DBMS_OUTPUT.PUT_LINE('FRA Location:      ' || v_fra_location);
        DBMS_OUTPUT.PUT_LINE('FRA Size Limit:    ' || ROUND(v_fra_size/1024/1024/1024, 2) || ' GB');
        DBMS_OUTPUT.PUT_LINE('FRA Used:          ' || ROUND(v_fra_used/1024/1024/1024, 2) || ' GB');
        DBMS_OUTPUT.PUT_LINE('FRA Usage %:       ' || v_fra_pct || '%');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('FRA Status:        NOT CONFIGURED');
            DBMS_OUTPUT.PUT_LINE('');
            DBMS_OUTPUT.PUT_LINE('*** FRA is not configured. To configure:');
            DBMS_OUTPUT.PUT_LINE('ALTER SYSTEM SET db_recovery_file_dest_size = 100G;');
            DBMS_OUTPUT.PUT_LINE('ALTER SYSTEM SET db_recovery_file_dest = ''/path/to/fra'';');
    END;
END;
/

PROMPT
PROMPT *** ARCHIVELOG MODE CHECK ***
DECLARE
    v_log_mode VARCHAR2(20);
    v_force_logging VARCHAR2(20);
BEGIN
    SELECT log_mode, force_logging 
    INTO v_log_mode, v_force_logging
    FROM v$database;
    
    DBMS_OUTPUT.PUT_LINE('Archive Mode:      ' || v_log_mode);
    DBMS_OUTPUT.PUT_LINE('Force Logging:     ' || v_force_logging);
    
    IF v_log_mode = 'NOARCHIVELOG' THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('WARNING: Database is in NOARCHIVELOG mode!');
        DBMS_OUTPUT.PUT_LINE('Archive logs will not be generated.');
        DBMS_OUTPUT.PUT_LINE('To enable: ');
        DBMS_OUTPUT.PUT_LINE('  SHUTDOWN IMMEDIATE;');
        DBMS_OUTPUT.PUT_LINE('  STARTUP MOUNT;');
        DBMS_OUTPUT.PUT_LINE('  ALTER DATABASE ARCHIVELOG;');
        DBMS_OUTPUT.PUT_LINE('  ALTER DATABASE OPEN;');
    END IF;
END;
/

PROMPT
PROMPT *** ONLINE REDO LOGS ANALYSIS ***
DECLARE
    v_total_groups NUMBER;
    v_total_members NUMBER;
    v_total_size_gb NUMBER;
    v_avg_size_mb NUMBER;
    v_threads NUMBER;
    v_env VARCHAR2(10) := '&v_is_rac';
BEGIN
    IF v_env = 'Y' THEN
        -- RAC environment
        SELECT COUNT(*), SUM(members), 
               ROUND(SUM(bytes)/1024/1024/1024, 2),
               ROUND(AVG(bytes)/1024/1024, 2),
               COUNT(DISTINCT thread#)
        INTO v_total_groups, v_total_members, v_total_size_gb, 
             v_avg_size_mb, v_threads
        FROM gv$log;
    ELSE
        -- Single Instance
        SELECT COUNT(*), SUM(members), 
               ROUND(SUM(bytes)/1024/1024/1024, 2),
               ROUND(AVG(bytes)/1024/1024, 2),
               1
        INTO v_total_groups, v_total_members, v_total_size_gb, 
             v_avg_size_mb, v_threads
        FROM v$log;
    END IF;
    
    DBMS_OUTPUT.PUT_LINE('Redo Log Configuration:');
    DBMS_OUTPUT.PUT_LINE('  Threads:         ' || v_threads);
    DBMS_OUTPUT.PUT_LINE('  Total Groups:    ' || v_total_groups);
    DBMS_OUTPUT.PUT_LINE('  Total Members:   ' || v_total_members);
    DBMS_OUTPUT.PUT_LINE('  Total Size:      ' || v_total_size_gb || ' GB');
    DBMS_OUTPUT.PUT_LINE('  Avg Size/Group:  ' || v_avg_size_mb || ' MB');
END;
/

PROMPT
PROMPT *** REDO LOG DETAILS ***
COL thread# FOR 999
COL group# FOR 999
COL status FOR A10
COL mb FOR 9999
SELECT thread#, group#, status, bytes/1024/1024 AS mb, members
FROM v$log
ORDER BY thread#, group#;

PROMPT
PROMPT *** ARCHIVED LOG GENERATION ANALYSIS ***
DECLARE
    v_archive_count NUMBER;
    v_total_size_gb NUMBER;
    v_avg_daily_gb NUMBER;
    v_max_daily_gb NUMBER;
    v_days_analyzed NUMBER;
BEGIN
    -- Check if there are any archived logs
    SELECT COUNT(*) INTO v_archive_count
    FROM v$archived_log
    WHERE first_time >= SYSDATE - 30
      AND standby_dest = 'NO';
    
    IF v_archive_count > 0 THEN
        -- Get statistics
        SELECT 
            COUNT(DISTINCT TO_CHAR(first_time, 'YYYY-MM-DD')),
            ROUND(SUM(blocks * block_size)/1024/1024/1024, 2)
        INTO v_days_analyzed, v_total_size_gb
        FROM v$archived_log
        WHERE first_time >= SYSDATE - 30
          AND first_time < TRUNC(SYSDATE)
          AND standby_dest = 'NO';
        
        -- Daily average
        SELECT 
            ROUND(AVG(daily_gb), 2),
            ROUND(MAX(daily_gb), 2)
        INTO v_avg_daily_gb, v_max_daily_gb
        FROM (
            SELECT SUM(blocks * block_size)/1024/1024/1024 AS daily_gb
            FROM v$archived_log
            WHERE first_time >= SYSDATE - 30
              AND first_time < TRUNC(SYSDATE)
              AND standby_dest = 'NO'
            GROUP BY TO_CHAR(first_time, 'YYYY-MM-DD')
        );
        
        DBMS_OUTPUT.PUT_LINE('Archive Log Statistics (30 days):');
        DBMS_OUTPUT.PUT_LINE('  Archives Found:  ' || v_archive_count);
        DBMS_OUTPUT.PUT_LINE('  Days Analyzed:   ' || v_days_analyzed);
        DBMS_OUTPUT.PUT_LINE('  Total Size:      ' || v_total_size_gb || ' GB');
        DBMS_OUTPUT.PUT_LINE('  Avg Daily:       ' || NVL(v_avg_daily_gb, 0) || ' GB');
        DBMS_OUTPUT.PUT_LINE('  Max Daily:       ' || NVL(v_max_daily_gb, 0) || ' GB');
        DBMS_OUTPUT.PUT_LINE('  Projected Weekly:' || NVL(v_avg_daily_gb * 7, 0) || ' GB');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Archive Log Statistics:');
        DBMS_OUTPUT.PUT_LINE('  No archived logs found in the last 30 days.');
        
        IF '&v_archive_mode' = 'NOARCHIVELOG' THEN
            DBMS_OUTPUT.PUT_LINE('  Reason: Database is in NOARCHIVELOG mode');
        ELSE
            DBMS_OUTPUT.PUT_LINE('  Possible reasons:');
            DBMS_OUTPUT.PUT_LINE('  - Database recently created/cloned');
            DBMS_OUTPUT.PUT_LINE('  - Archives deleted or moved');
            DBMS_OUTPUT.PUT_LINE('  - FRA not configured for archiving');
        END IF;
    END IF;
END;
/

PROMPT
PROMPT *** FLASHBACK DATABASE STATUS ***
DECLARE
    v_flashback VARCHAR2(10);
    v_flashback_size NUMBER := 0;
    v_retention NUMBER;
BEGIN
    SELECT flashback_on INTO v_flashback FROM v$database;
    
    DBMS_OUTPUT.PUT_LINE('Flashback Status:  ' || v_flashback);
    
    IF v_flashback = 'YES' THEN
        BEGIN
            SELECT ROUND(SUM(bytes)/1024/1024/1024, 2)
            INTO v_flashback_size
            FROM v$flashback_database_logfile;
            
            SELECT value INTO v_retention
            FROM v$parameter
            WHERE name = 'db_flashback_retention_target';
            
            DBMS_OUTPUT.PUT_LINE('  Current Size:    ' || NVL(v_flashback_size, 0) || ' GB');
            DBMS_OUTPUT.PUT_LINE('  Retention Target:' || v_retention || ' minutes');
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('  Unable to retrieve flashback details');
        END;
    END IF;
END;
/

PROMPT
PROMPT *** RMAN BACKUP HISTORY ***
DECLARE
    v_backup_count NUMBER;
    v_avg_size NUMBER;
    v_last_backup DATE;
BEGIN
    SELECT COUNT(*) INTO v_backup_count
    FROM v$backup_set_details
    WHERE start_time >= SYSDATE - 30;
    
    IF v_backup_count > 0 THEN
        SELECT 
            ROUND(AVG(output_bytes)/1024/1024/1024, 2),
            MAX(start_time)
        INTO v_avg_size, v_last_backup
        FROM v$backup_set_details
        WHERE start_time >= SYSDATE - 30;
        
        DBMS_OUTPUT.PUT_LINE('RMAN Backup Statistics (30 days):');
        DBMS_OUTPUT.PUT_LINE('  Backup Sets:     ' || v_backup_count);
        DBMS_OUTPUT.PUT_LINE('  Avg Size:        ' || v_avg_size || ' GB');
        DBMS_OUTPUT.PUT_LINE('  Last Backup:     ' || TO_CHAR(v_last_backup, 'DD-MON-YYYY HH24:MI'));
    ELSE
        DBMS_OUTPUT.PUT_LINE('RMAN Backup Statistics:');
        DBMS_OUTPUT.PUT_LINE('  No RMAN backups found in the last 30 days.');
    END IF;
END;
/

PROMPT
PROMPT =====================================================
PROMPT    FRA SIZING RECOMMENDATIONS
PROMPT =====================================================
DECLARE
    -- Component variables
    v_redo_gb NUMBER := 0;
    v_archive_gb NUMBER := 0;
    v_flashback_gb NUMBER := 0;
    v_backup_gb NUMBER := 0;
    v_control_gb NUMBER := 2;
    v_buffer_gb NUMBER;
    
    -- Calculation variables
    v_total_gb NUMBER;
    v_env_type VARCHAR2(10) := '&v_is_rac';
    v_log_mode VARCHAR2(20) := '&v_archive_mode';
    v_multiplier NUMBER;
    
    -- Database size for estimation
    v_db_size_gb NUMBER;
    
    -- Variables for backup calculation
    v_backup_count NUMBER;
    v_avg_backup_gb NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== COMPONENT CALCULATION ===');
    
    -- Get database size
    SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) 
    INTO v_db_size_gb 
    FROM v$datafile;
    
    -- Set multipliers based on environment
    IF v_env_type = 'Y' THEN
        v_multiplier := 1.3;  -- 30% extra for RAC
        v_buffer_gb := 15;    -- More buffer for RAC
    ELSE
        v_multiplier := 1.2;  -- 20% extra for SI
        v_buffer_gb := 10;    -- Standard buffer
    END IF;
    
    -- 1. Online Redo Logs
    IF v_env_type = 'Y' THEN
        SELECT NVL(ROUND(SUM(bytes)/1024/1024/1024, 2), 2) 
        INTO v_redo_gb FROM gv$log;
    ELSE
        SELECT NVL(ROUND(SUM(bytes)/1024/1024/1024, 2), 1) 
        INTO v_redo_gb FROM v$log;
    END IF;
    DBMS_OUTPUT.PUT_LINE('1. Online Redo Logs:      ' || LPAD(TO_CHAR(v_redo_gb, '999.99'), 8) || ' GB');
    
    -- 2. Archived Logs (7 days retention)
    IF v_log_mode = 'ARCHIVELOG' THEN
        -- Try to get actual data
        BEGIN
            SELECT ROUND(AVG(daily_gb) * 7 * v_multiplier, 2)
            INTO v_archive_gb
            FROM (
                SELECT SUM(blocks * block_size)/1024/1024/1024 AS daily_gb
                FROM v$archived_log
                WHERE standby_dest = 'NO'
                  AND first_time >= SYSDATE - 30
                  AND first_time < TRUNC(SYSDATE)
                GROUP BY TO_CHAR(first_time, 'YYYY-MM-DD')
            );
            
            -- If null, use estimation
            IF v_archive_gb IS NULL THEN
                v_archive_gb := ROUND(v_db_size_gb * 0.01 * 7 * v_multiplier, 2);
                IF v_archive_gb < 10 THEN
                    v_archive_gb := 10; -- Minimum 10GB
                END IF;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                -- Estimate based on database size (1% daily change)
                v_archive_gb := ROUND(v_db_size_gb * 0.01 * 7 * v_multiplier, 2);
                IF v_archive_gb < 10 THEN
                    v_archive_gb := 10; -- Minimum 10GB
                END IF;
        END;
        DBMS_OUTPUT.PUT_LINE('2. Archived Logs (7d):    ' || LPAD(TO_CHAR(v_archive_gb, '999.99'), 8) || ' GB');
    ELSE
        v_archive_gb := 0;
        DBMS_OUTPUT.PUT_LINE('2. Archived Logs (7d):    ' || LPAD('0', 8) || ' GB (NOARCHIVELOG mode)');
    END IF;
    
    -- 3. Flashback Logs
    SELECT CASE 
        WHEN flashback_on = 'YES' THEN
            GREATEST(
                NVL((SELECT ROUND(SUM(bytes)/1024/1024/1024 * 1.5, 2)
                     FROM v$flashback_database_logfile), 0),
                ROUND(v_db_size_gb * 0.05, 2), -- At least 5% of DB size
                10  -- Minimum 10GB if enabled
            )
        ELSE 0
    END INTO v_flashback_gb
    FROM v$database;
    DBMS_OUTPUT.PUT_LINE('3. Flashback Logs:        ' || LPAD(TO_CHAR(v_flashback_gb, '999.99'), 8) || ' GB');
    
    -- 4. RMAN Backups (2 full backup sets)
    BEGIN
        -- Check if there are any backups
        SELECT COUNT(*) INTO v_backup_count
        FROM v$backup_set_details
        WHERE start_time >= SYSDATE - 30;
        
        IF v_backup_count > 0 THEN
            -- Use actual backup data
            SELECT ROUND(AVG(daily_backup_gb) * 2, 2)
            INTO v_backup_gb
            FROM (
                SELECT SUM(output_bytes)/1024/1024/1024 AS daily_backup_gb
                FROM v$backup_set_details
                WHERE start_time >= SYSDATE - 30
                GROUP BY TO_CHAR(start_time, 'YYYY-MM-DD')
            );
        ELSE
            -- Estimate: compressed backup = 30% of database size
            v_backup_gb := ROUND(v_db_size_gb * 0.3 * 2, 2);
        END IF;
        
        -- Ensure minimum value
        IF v_backup_gb < 20 OR v_backup_gb IS NULL THEN
            v_backup_gb := 20; -- Minimum 20GB
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            -- If any error, use estimation
            v_backup_gb := GREATEST(ROUND(v_db_size_gb * 0.3 * 2, 2), 20);
    END;
    DBMS_OUTPUT.PUT_LINE('4. RMAN Backups (2 sets): ' || LPAD(TO_CHAR(v_backup_gb, '999.99'), 8) || ' GB');
    
    -- 5. Control files
    DBMS_OUTPUT.PUT_LINE('5. Control Files:         ' || LPAD(TO_CHAR(v_control_gb, '999.99'), 8) || ' GB');
    
    -- 6. Safety buffer
    DBMS_OUTPUT.PUT_LINE('6. Safety Buffer:         ' || LPAD(TO_CHAR(v_buffer_gb, '999.99'), 8) || ' GB');
    
    -- Calculate totals
    v_total_gb := v_redo_gb + v_archive_gb + v_flashback_gb + 
                  v_backup_gb + v_control_gb + v_buffer_gb;
    
    DBMS_OUTPUT.PUT_LINE('------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('Base Calculation:         ' || LPAD(TO_CHAR(ROUND(v_total_gb), '999'), 8) || ' GB');
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== FINAL RECOMMENDATIONS ===');
    DBMS_OUTPUT.PUT_LINE('Minimum Size:             ' || LPAD(TO_CHAR(ROUND(v_total_gb), '999'), 8) || ' GB');
    DBMS_OUTPUT.PUT_LINE('Recommended Size:         ' || LPAD(TO_CHAR(ROUND(v_total_gb * 1.3), '999'), 8) || ' GB');
    DBMS_OUTPUT.PUT_LINE('Conservative Size:        ' || LPAD(TO_CHAR(ROUND(v_total_gb * 1.5), '999'), 8) || ' GB');
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== NOTES ===');
    IF v_env_type = 'Y' THEN
        DBMS_OUTPUT.PUT_LINE('- RAC environment: includes multi-instance overhead');
    END IF;
    IF v_log_mode = 'NOARCHIVELOG' THEN
        DBMS_OUTPUT.PUT_LINE('- NOARCHIVELOG mode: archive space not included');
    END IF;
    IF v_backup_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('- Backup size ESTIMATED (no RMAN history found)');
    END IF;
    
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Database Size: ' || v_db_size_gb || ' GB (for reference)');
    
    -- Print actual ALTER commands with calculated values
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== READY-TO-USE COMMANDS ===');
    DBMS_OUTPUT.PUT_LINE('-- Configure FRA with recommended size:');
    DBMS_OUTPUT.PUT_LINE('ALTER SYSTEM SET db_recovery_file_dest_size = ' || 
                         ROUND(v_total_gb * 1.3) || 'G SCOPE=BOTH;');
    DBMS_OUTPUT.PUT_LINE('ALTER SYSTEM SET db_recovery_file_dest = ''/u01/app/oracle/fra'' SCOPE=BOTH;');
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('ERROR in calculation: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Please run the minimal version of the script instead.');
END;
/

PROMPT
PROMPT =====================================================
PROMPT    IMPLEMENTATION STEPS
PROMPT =====================================================
PROMPT
PROMPT 1. Review the recommendations above
PROMPT 2. Execute the ALTER commands provided
PROMPT 3. Monitor FRA usage regularly:
PROMPT    SELECT * FROM v$recovery_file_dest;
PROMPT
PROMPT =====================================================
PROMPT    END OF FRA SIZING ANALYSIS
PROMPT =====================================================

-- Reset
SET SERVEROUTPUT OFF
SET PAGESIZE 14
SET LINESIZE 80