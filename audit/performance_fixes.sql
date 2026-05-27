-- Oracle Database Performance Optimization Fixes
-- Addresses recompiling invalid objects, gathering statistics, and undo management
-- Run as: sqlplus / as sysdba @performance_fixes.sql

SET ECHO ON
SET FEEDBACK ON
SET PAGESIZE 50
SET LINESIZE 200
SPOOL performance_fixes.log

PROMPT ================================================================================
PROMPT ORACLE DATABASE PERFORMANCE OPTIMIZATION FIXES
PROMPT Start Time:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

-- =============================================================================
-- PART 1: RECOMPILE INVALID OBJECTS
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 1: RECOMPILE INVALID OBJECTS
PROMPT ================================================================================

DECLARE
  v_count INTEGER := 0;
  v_failed INTEGER := 0;
BEGIN
  FOR obj IN (
    SELECT owner, object_type, object_name
    FROM dba_objects
    WHERE status = 'INVALID'
      AND owner NOT IN ('SYS', 'SYSTEM')
    ORDER BY owner, object_type, object_name
  )
  LOOP
    BEGIN
      DBMS_OUTPUT.PUT_LINE('Compiling ' || obj.object_type || ': ' || obj.owner || '.' || obj.object_name);

      IF obj.object_type = 'PACKAGE' THEN
        EXECUTE IMMEDIATE 'ALTER PACKAGE ' || obj.owner || '.' || obj.object_name || ' COMPILE';
        EXECUTE IMMEDIATE 'ALTER PACKAGE ' || obj.owner || '.' || obj.object_name || ' COMPILE BODY';
      ELSIF obj.object_type = 'FUNCTION' THEN
        EXECUTE IMMEDIATE 'ALTER FUNCTION ' || obj.owner || '.' || obj.object_name || ' COMPILE';
      ELSIF obj.object_type = 'PROCEDURE' THEN
        EXECUTE IMMEDIATE 'ALTER PROCEDURE ' || obj.owner || '.' || obj.object_name || ' COMPILE';
      ELSIF obj.object_type = 'TYPE' THEN
        EXECUTE IMMEDIATE 'ALTER TYPE ' || obj.owner || '.' || obj.object_name || ' COMPILE';
      ELSIF obj.object_type = 'TRIGGER' THEN
        EXECUTE IMMEDIATE 'ALTER TRIGGER ' || obj.owner || '.' || obj.object_name || ' COMPILE';
      END IF;

      v_count := v_count + 1;

    EXCEPTION
      WHEN OTHERS THEN
        v_failed := v_failed + 1;
        DBMS_OUTPUT.PUT_LINE('ERROR compiling ' || obj.owner || '.' || obj.object_name || ': ' || SQLERRM);
    END;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('Recompilation Summary:');
  DBMS_OUTPUT.PUT_LINE('  Successfully compiled: ' || v_count);
  DBMS_OUTPUT.PUT_LINE('  Failed: ' || v_failed);
  DBMS_OUTPUT.PUT_LINE('  Total: ' || (v_count + v_failed));
END;
/

PROMPT Verification: Invalid objects after recompilation...
SELECT COUNT(*) AS remaining_invalid_objects
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS', 'SYSTEM');

-- =============================================================================
-- PART 2: GATHER FRESH STATISTICS
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 2: GATHER FRESH STATISTICS ON ALL OBJECTS
PROMPT ================================================================================

PROMPT This may take several minutes depending on database size...
PROMPT Gathering statistics on SYS schema (required for optimizer)...

BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS(
    ownname          => 'SYS',
    options          => 'GATHER AUTO',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    degree           => DBMS_STATS.DEFAULT_DEGREE,
    granularity      => 'ALL',
    cascade          => TRUE,
    method_opt       => 'FOR ALL COLUMNS SIZE AUTO'
  );
  DBMS_OUTPUT.PUT_LINE('SYS schema statistics gathered successfully.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Warning gathering SYS stats: ' || SQLERRM);
END;
/

PROMPT Gathering statistics on SYSTEM schema...

BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS(
    ownname          => 'SYSTEM',
    options          => 'GATHER AUTO',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    degree           => DBMS_STATS.DEFAULT_DEGREE,
    granularity      => 'ALL',
    cascade          => TRUE,
    method_opt       => 'FOR ALL COLUMNS SIZE AUTO'
  );
  DBMS_OUTPUT.PUT_LINE('SYSTEM schema statistics gathered successfully.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Warning gathering SYSTEM stats: ' || SQLERRM);
END;
/

PROMPT Gathering statistics on user schemas...

DECLARE
  v_count INTEGER := 0;
BEGIN
  FOR schema IN (
    SELECT DISTINCT owner
    FROM dba_tables
    WHERE owner NOT IN ('SYS', 'SYSTEM', 'UNDO')
    ORDER BY owner
  )
  LOOP
    BEGIN
      DBMS_OUTPUT.PUT_LINE('Gathering statistics for schema: ' || schema.owner);
      DBMS_STATS.GATHER_SCHEMA_STATS(
        ownname          => schema.owner,
        options          => 'GATHER AUTO',
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        degree           => DBMS_STATS.DEFAULT_DEGREE,
        granularity      => 'ALL',
        cascade          => TRUE,
        method_opt       => 'FOR ALL COLUMNS SIZE AUTO'
      );
      v_count := v_count + 1;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Warning for ' || schema.owner || ': ' || SQLERRM);
    END;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('Statistics gathering complete for ' || v_count || ' schemas.');
END;
/

PROMPT
PROMPT Statistics Summary:
SELECT
    object_type,
    COUNT(*) AS total_objects,
    SUM(CASE WHEN last_analyzed IS NULL THEN 1 ELSE 0 END) AS never_analyzed,
    SUM(CASE WHEN last_analyzed IS NOT NULL THEN 1 ELSE 0 END) AS analyzed,
    ROUND(100 * SUM(CASE WHEN last_analyzed IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_analyzed
FROM dba_objects
WHERE owner NOT IN ('SYS', 'SYSTEM')
GROUP BY object_type
ORDER BY pct_analyzed ASC;

-- =============================================================================
-- PART 3: UNDO TABLESPACE MANAGEMENT
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 3: OPTIMIZE UNDO TABLESPACE CONFIGURATION
PROMPT ================================================================================

PROMPT Current Undo Configuration:
SELECT name, value
FROM v$parameter
WHERE name IN ('undo_tablespace', 'undo_retention', 'undo_management')
ORDER BY name;

PROMPT
PROMPT Undo Tablespace Usage:
SELECT
    tablespace_name,
    status,
    ROUND(SUM(bytes) / 1024 / 1024, 2) AS size_mb,
    COUNT(*) AS num_extents
FROM dba_undo_extents
GROUP BY tablespace_name, status
ORDER BY tablespace_name, status;

PROMPT Setting optimal UNDO_RETENTION (900 seconds = 15 minutes minimum)...
BEGIN
  EXECUTE IMMEDIATE 'ALTER SYSTEM SET undo_retention=900 SCOPE=BOTH';
  DBMS_OUTPUT.PUT_LINE('UNDO_RETENTION set to 900 seconds (15 minutes).');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Warning setting UNDO_RETENTION: ' || SQLERRM);
END;
/

PROMPT Configuring UNDO auto-shrink (if available)...
BEGIN
  EXECUTE IMMEDIATE 'ALTER SYSTEM SET undo_management=AUTO SCOPE=BOTH';
  DBMS_OUTPUT.PUT_LINE('UNDO_MANAGEMENT set to AUTO.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: UNDO_MANAGEMENT configuration attempted.');
END;
/

-- =============================================================================
-- PART 4: REBUILD FRAGMENTED INDEXES
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 4: IDENTIFY AND REBUILD FRAGMENTED INDEXES
PROMPT ================================================================================

PROMPT Analyzing index fragmentation...
DECLARE
  v_count INTEGER := 0;
BEGIN
  FOR idx IN (
    SELECT
        owner,
        index_name,
        table_name,
        ROUND((lf_blks * 100) / (lf_blks + br_blks + DECODE(del_lf_blks, NULL, 0, del_lf_blks)), 2) AS pct_used
    FROM index_stats
    WHERE (lf_blks * 100) / (lf_blks + br_blks + DECODE(del_lf_blks, NULL, 0, del_lf_blks)) < 50
      AND owner NOT IN ('SYS', 'SYSTEM')
  )
  LOOP
    DBMS_OUTPUT.PUT_LINE('Fragmented index: ' || idx.owner || '.' || idx.index_name ||
                         ' on table ' || idx.table_name ||
                         ' (Space utilized: ' || idx.pct_used || '%)');
    v_count := v_count + 1;
  END LOOP;

  IF v_count = 0 THEN
    DBMS_OUTPUT.PUT_LINE('No fragmented indexes found requiring rebuilding.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('NOTE: Review and rebuild fragmented indexes separately:');
    DBMS_OUTPUT.PUT_LINE('ALTER INDEX index_name REBUILD ONLINE;');
  END IF;
END;
/

-- =============================================================================
-- PART 5: SHRINK UNDO TABLESPACE (IF NEEDED)
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 5: SHRINK UNDO EXTENTS (OPTIONAL)
PROMPT ================================================================================

PROMPT Attempting to shrink undo tablespace (if space permits)...
DECLARE
  v_undo_ts VARCHAR2(30);
BEGIN
  SELECT tablespace_name INTO v_undo_ts
  FROM v$parameter
  WHERE name = 'undo_tablespace';

  BEGIN
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET events=''10514 trace name context forever, level 2'' SCOPE=BOTH';
    DBMS_OUTPUT.PUT_LINE('Undo shrink event set.');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Note: Undo shrink may require manual intervention.');
  END;

  DBMS_OUTPUT.PUT_LINE('Undo tablespace: ' || v_undo_ts);

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Unable to determine undo tablespace: ' || SQLERRM);
END;
/

-- =============================================================================
-- PART 6: VERIFY OPTIMIZATIONS
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 6: VERIFICATION AND SUMMARY
PROMPT ================================================================================

PROMPT Remaining Invalid Objects:
SELECT COUNT(*) AS invalid_object_count
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS', 'SYSTEM');

PROMPT
PROMPT Objects with Current Statistics:
SELECT
    object_type,
    COUNT(*) AS with_stats,
    ROUND(100 * COUNT(*) / (SELECT COUNT(*)
                            FROM dba_objects
                            WHERE owner NOT IN ('SYS', 'SYSTEM')
                            AND object_type = dba_objects.object_type), 2) AS pct
FROM dba_objects
WHERE owner NOT IN ('SYS', 'SYSTEM')
  AND last_analyzed >= SYSDATE - 1
GROUP BY object_type
ORDER BY object_type;

PROMPT
PROMPT Undo Configuration After Changes:
SELECT name, value
FROM v$parameter
WHERE name IN ('undo_tablespace', 'undo_retention', 'undo_management')
ORDER BY name;

PROMPT
PROMPT ================================================================================
PROMPT PERFORMANCE OPTIMIZATION COMPLETE
PROMPT ================================================================================
PROMPT End Time:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

SPOOL OFF

PROMPT
PROMPT Performance optimization complete. Check performance_fixes.log for details.
PROMPT
PROMPT RECOMMENDED FOLLOW-UP ACTIONS:
PROMPT 1. Review performance_fixes.log for any warnings or errors
PROMPT 2. Verify statistics are fresh with: SELECT COUNT(*) FROM dba_objects WHERE last_analyzed IS NULL
PROMPT 3. Monitor performance improvements over next 24-48 hours
PROMPT 4. Check for any fragmented indexes requiring rebuilds
PROMPT 5. Validate that no critical errors occurred during compilation
