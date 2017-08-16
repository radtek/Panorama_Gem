module PanoramaSampler::PackagePanoramaSamplerAsh
  # PL/SQL-Package for snapshot creation
  def panorama_sampler_ash_spec
    "
CREATE OR REPLACE Package panorama.Panorama_Sampler_ASH AS
  -- Compiled at COMPILE_TIME_BY_PANORAMA_ENSURES_CHANGE_OF_LAST_DDL_TIME


  PROCEDURE Run_Sampler_Daemon(p_Snapshot_Cycle_Seconds IN NUMBER, p_Instance_Number IN NUMBER, p_Con_ID IN NUMBER, p_Next_Snapshot_Start_Seconds IN NUMBER);

END Panorama_Sampler_ASH;
    "
  end

  def panorama_sampler_ash_body
    "
-- Package for use by Panorama-Sampler
CREATE OR REPLACE PACKAGE BODY panorama.Panorama_Sampler_ASH AS
  -- Compiled at COMPILE_TIME_BY_PANORAMA_ENSURES_CHANGE_OF_LAST_DDL_TIME
  TYPE AshType IS RECORD (
    Sample_ID                 NUMBER,
    Sample_Time               TIMESTAMP(3),
    Session_ID                NUMBER,
    SESSION_SERIAL#           NUMBER,
    Session_Type              VARCHAR2(10),
    Flags                     NUMBER,
    User_ID                   NUMBER,
    SQL_ID                    VARCHAR2(13),
    Is_SQLID_Current          VARCHAR2(1),
    SQL_CHILD_NUMBER          NUMBER,
    SQL_OPCODE                NUMBER,
    SQL_OpName                VARCHAR2(64),
    FORCE_MATCHING_SIGNATURE  NUMBER,
    TOP_LEVEL_SQL_ID          VARCHAR2(13),
    TOP_LEVEL_SQL_OPCODE      NUMBER,
    SQL_PLAN_HASH_VALUE       NUMBER,
    SQL_PLAN_LINE_ID          NUMBER,
    SQL_PLAN_OPERATION        VARCHAR2(64),
    SQL_PLAN_OPTIONS          VARCHAR2(64),
    SQL_EXEC_ID               NUMBER,
    SQL_EXEC_START            DATE,
    PLSQL_ENTRY_OBJECT_ID     NUMBER,
    PLSQL_ENTRY_SUBPROGRAM_ID NUMBER,
    PLSQL_OBJECT_ID           NUMBER,
    PLSQL_SUBPROGRAM_ID       NUMBER,
    QC_INSTANCE_ID            NUMBER,
    QC_SESSION_ID             NUMBER,
    QC_SESSION_SERIAL#        NUMBER,
    PX_FLAGS                  NUMBER,
    EVENT                     VARCHAR2(64),
    EVENT_ID                  NUMBER,
    SEQ#                      NUMBER,
    P1TEXT                    VARCHAR2(64),
    P1                        NUMBER,
    P2TEXT                    VARCHAR2(64),
    P2                        NUMBER,
    P3TEXT                    VARCHAR2(64),
    P3                        NUMBER,
    WAIT_CLASS                VARCHAR2(64),
    Wait_Class_ID             NUMBER,
    Wait_Time                 NUMBER,
    SESSION_STATE             VARCHAR2(7),
    TIME_WAITED               NUMBER,
    BLOCKING_SESSION_STATUS   VARCHAR2(11),
    BLOCKING_SESSION          NUMBER,
    BLOCKING_SESSION_SERIAL#  NUMBER,
    BLOCKING_INST_ID          NUMBER,
    BLOCKING_HANGCHAIN_INFO   VARCHAR2(1),
    CURRENT_OBJ#              NUMBER,
    CURRENT_FILE#             NUMBER,
    CURRENT_Block#            NUMBER,
    CURRENT_Row#              NUMBER,
    TOP_LEVEL_CALL#           NUMBER
  );
  TYPE AshTableType IS TABLE OF AshType INDEX BY BINARY_INTEGER;
  AshTable                AshTableType;
  AshTable4Select         AshTableType;


  PROCEDURE CreateSample(
    p_Instance_Number IN NUMBER,
    p_Con_ID          IN NUMBER,
    p_Bulk_Size       IN INTEGER,
    p_Counter         IN OUT NUMBER,
    p_Sample_ID       IN OUT NUMBER
  ) IS
    BEGIN
      p_Sample_ID := p_Sample_ID + 1;
      AshTable4Select.DELETE;
      SELECT p_Sample_ID,
             SYSTIMESTAMP,
             s.SID,
             s.Serial#,
             s.Type,
             NULL,                -- Flags
             s.User#,
             s.SQL_ID,
             'Y',                 -- TODO: Is_SQLID_Current ermitteln
             s.SQL_Child_Number,
             s.Command,           -- SQL_OpCode
             c.Command_Name,      -- SQL_OpName
             sql.FORCE_MATCHING_SIGNATURE,
             NULL,                -- TODO: TOP_LEVEL_SQL_ID ermitteln
             NULL,                -- TODO: TOP_LEVEL_SQL_OPCODE ermitteln
             sql.PLAN_HASH_VALUE,
             NULL,                -- TODO: SQL_PLAN_LINE_ID ermitteln
             NULL,                -- TODO: SQL_PLAN_OPERATION ermitteln
             NULL,                -- TODO SQL_PLAN_OPTIONS ermitteln
             s.SQL_EXEC_ID,
             s.SQL_EXEC_START,
             s.PLSQL_ENTRY_OBJECT_ID,
             s.PLSQL_ENTRY_SUBPROGRAM_ID,
             s.PLSQL_OBJECT_ID,
             s.PLSQL_SUBPROGRAM_ID,
             pxs.QCInst_ID,
             pxs.QCSID,
             pxs.QCSerial#,
             NULL,                -- TODO: PX_FLAGS ermitteln
             s.Event,
             s.Event#,
             s.SEQ#,
             s.P1TEXT,
             s.P1,
             s.P2TEXT,
             s.P2,
             s.P3TEXT,
             s.P3,
             s.Wait_Class,
             s.Wait_Class_ID,
             DECODE(s.State, 'WAITING', 0, s.Wait_Time_Micro),    -- Wait_Time: Time waited on last wait event in ON CPU, 0 currently waiting
             DECODE(s.State, 'WAITING', 'WAITING', 'ON CPU'),     -- Session_State
             DECODE(s.State, 'WAITING', s.Wait_Time_Micro, 0),    -- Time_waited: Current wait time if in wait, 0 if ON CPU
             s.BLOCKING_SESSION_STATUS,
             s.BLOCKING_SESSION,
             CASE WHEN Blocking_Session_Status = 'VALID' THEN (SELECT Serial# FROM gv$Session bs WHERE bs.Inst_ID=s.Blocking_Instance AND bs.SID=s.Blocking_Session)
             END BLOCKING_SESSION_SERIAL#,
             s.Blocking_Instance,
             'N',                 -- BLOCKING_HANGCHAIN_INFO
             s.Row_Wait_Obj#,     -- Current_Obj#
             s.Row_Wait_File#,    -- Current_File#
             s.Row_Wait_Block#,   -- Current_Block#
             s.Row_Wait_Row#,     -- Current_Row#
             #{PanoramaConnection.db_version >= '11.2' ?  "s.TOP_LEVEL_CALL#" : "NULL"  } -- Top_Level_Call#
      BULK COLLECT INTO AshTable4Select
      FROM   v$Session s
      LEFT OUTER JOIN v$SQLCommand c ON c.Command_Type = s.Command #{"AND c.Con_ID = s.Con_ID" if PanoramaConnection.db_version >= '12.1'}
      LEFT OUTER JOIN v$SQL sql ON sql.SQL_ID = s.SQL_ID AND sql.Child_Number = s.SQL_Child_Number #{"AND sql.Con_ID = s.Con_ID" if PanoramaConnection.db_version >= '12.1'}
      LEFT OUTER JOIN v$PX_Session pxs ON pxs.SID = s.SID AND pxs.Serial#=s.Serial#
      WHERE  s.Status = 'ACTIVE'
      AND    s.Wait_Class != 'Idle'
      AND    s.SID        != USERENV('SID')  -- dont record the own session that assumes always active this way
      #{"AND s.Con_ID = p_Con_ID" if PanoramaConnection.db_version >= '12.1'}
      ;

      FOR Idx IN 1 .. AshTable4Select.COUNT LOOP
        AshTable(AshTable.COUNT+1) := AshTable4Select(Idx);
      END LOOP;

      p_Counter := p_Counter + 1;
      IF p_Counter >= p_Bulk_Size-1 THEN
        p_Counter := 0;

        FORALL Idx IN 1 .. AshTable.COUNT
        INSERT INTO Internal_V$Active_Sess_History (
          Instance_Number, Sample_ID, Sample_Time, Is_AWR_Sample, Session_ID, Session_Serial#,
          Session_Type, Flags, User_ID, SQL_ID, Is_SQLID_Current, SQL_Child_Number,
          SQL_OpCode, SQL_OpName, FORCE_MATCHING_SIGNATURE, TOP_LEVEL_SQL_ID, TOP_LEVEL_SQL_OPCODE,
          SQL_PLAN_HASH_VALUE, SQL_PLAN_LINE_ID, SQL_PLAN_OPERATION, SQL_PLAN_OPTIONS,
          SQL_EXEC_ID, SQL_EXEC_START,
          PLSQL_ENTRY_OBJECT_ID, PLSQL_ENTRY_SUBPROGRAM_ID, PLSQL_OBJECT_ID, PLSQL_SUBPROGRAM_ID,
          QC_INSTANCE_ID, QC_SESSION_ID, QC_SESSION_SERIAL#, PX_FLAGS, Event, Event_ID,
          SEQ#, P1TEXT, P1, P2TEXT, P2, P3TEXT, P3, Wait_Class, Wait_Class_ID, Wait_Time,
          Session_State, Time_Waited, BLOCKING_SESSION_STATUS, BLOCKING_SESSION, BLOCKING_SESSION_SERIAL#,
          BLOCKING_INST_ID, BLOCKING_HANGCHAIN_INFO,
          Current_Obj#, Current_File#, Current_Block#, Current_Row#,
          Top_Level_Call#,
          Con_ID
        ) VALUES (
          p_Instance_Number, AshTable(Idx).Sample_ID, AshTable(Idx).Sample_Time, 'N', AshTable(Idx).Session_ID, AshTable(Idx).Session_Serial#,
          AshTable(Idx).Session_Type, AshTable(Idx).Flags, AshTable(Idx).User_ID, AshTable(Idx).SQL_ID, AshTable(Idx).Is_SQLID_Current, AshTable(Idx).SQL_Child_Number,
          AshTable(Idx).SQL_OpCode, AshTable(Idx).SQL_OpName, AshTable(Idx).FORCE_MATCHING_SIGNATURE, AshTable(Idx).TOP_LEVEL_SQL_ID, AshTable(Idx).TOP_LEVEL_SQL_OPCODE,
          AshTable(Idx).SQL_PLAN_HASH_VALUE, AshTable(Idx).SQL_PLAN_LINE_ID, AshTable(Idx).SQL_PLAN_OPERATION, AshTable(Idx).SQL_PLAN_OPTIONS,
          AshTable(Idx).SQL_EXEC_ID, AshTable(Idx).SQL_EXEC_START,
          AshTable(Idx).PLSQL_ENTRY_OBJECT_ID, AshTable(Idx).PLSQL_ENTRY_SUBPROGRAM_ID, AshTable(Idx).PLSQL_OBJECT_ID, AshTable(Idx).PLSQL_SUBPROGRAM_ID,
          AshTable(Idx).QC_INSTANCE_ID, AshTable(Idx).QC_SESSION_ID, AshTable(Idx).QC_SESSION_SERIAL#, AshTable(Idx).PX_FLAGS, AshTable(Idx).Event, AshTable(Idx).Event_ID,
          AshTable(Idx).SEQ#, AshTable(Idx).P1TEXT, AshTable(Idx).P1, AshTable(Idx).P2TEXT, AshTable(Idx).P2, AshTable(Idx).P3TEXT, AshTable(Idx).P3, AshTable(Idx).Wait_Class, AshTable(Idx).Wait_Class_ID, AshTable(Idx).Wait_Time,
          AshTable(Idx).Session_State, AshTable(Idx).Time_Waited, AshTable(Idx).BLOCKING_SESSION_STATUS, AshTable(Idx).BLOCKING_SESSION, AshTable(Idx).BLOCKING_SESSION_SERIAL#,
          AshTable(Idx).BLOCKING_INST_ID, AshTable(Idx).BLOCKING_HANGCHAIN_INFO,
          AshTable(Idx).Current_Obj#, AshTable(Idx).Current_File#, AshTable(Idx).Current_Block#, AshTable(Idx).Current_Row#,
          AshTable(Idx).Top_Level_Call#,
          p_Con_ID
        );
        COMMIT;
        AshTable.DELETE;
      END IF;
    END CreateSample;


  PROCEDURE Run_Sampler_Daemon(
    p_Snapshot_Cycle_Seconds IN NUMBER,
    p_Instance_Number IN NUMBER,
    p_Con_ID IN NUMBER,
    p_Next_Snapshot_Start_Seconds IN NUMBER
  ) IS
    v_Counter         INTEGER;
    v_Sample_ID       INTEGER;
    v_LastSampleTime  DATE;
    v_Bulk_Size       INTEGER;
    v_Seconds_Run     INTEGER := 0;
    BEGIN
      v_Counter := 0;
      -- Ensure that local database time controls end of PL/SQL-execution (allows different time zones and some seconds delay between Panorama and DB)
      -- but assumes that PL/SQL-Job is started at the exact second
      v_LastSampleTime := SYSDATE + p_Snapshot_Cycle_Seconds/86400 - 1/86400;
      SELECT NVL(MAX(Sample_ID), 0) INTO v_Sample_ID FROM Internal_V$Active_Sess_History;

      LOOP
        v_Bulk_Size := 10; -- Number of seconds between persists/commits
        -- Reduce Bulk_Size before end of snapshot so last records are so commited that they are visible for snapshot creation and don't fall into the next snapshot
        IF v_Seconds_Run > p_Next_Snapshot_Start_Seconds - v_Bulk_Size THEN   -- less than v_Bulk_Size seconds until next snapshot
          v_Bulk_Size := p_Next_Snapshot_Start_Seconds - v_Seconds_Run;       -- reduce bulk size
          IF v_Bulk_Size < 1 THEN
            v_Bulk_Size := 1;
          END IF;
        END IF;

        CreateSample(p_Instance_Number, p_Con_ID, v_Bulk_Size, v_Counter, v_Sample_ID);
        EXIT WHEN SYSDATE >= v_LastSampleTime;

        -- Wait until current second ends
        DBMS_LOCK.SLEEP(1-MOD(EXTRACT(SECOND FROM SYSTIMESTAMP), 1));
        v_Seconds_Run := v_Seconds_Run + 1;

      END LOOP;

      EXCEPTION
        WHEN OTHERS THEN
          RAISE;
    END Run_Sampler_Daemon;

END Panorama_Sampler_ASH;
    "
  end


end