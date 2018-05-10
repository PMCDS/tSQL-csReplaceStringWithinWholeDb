/*******************************************************************************
** File:	  csReplaceStringWithinWholeDb.sql 
**
** Name:	  csReplaceStringWithinWholeDb
**
** Target:  SQL Server 2012+
**
** Desc:	  This script looks through entire DB - all DB tables and columns or
              throught the columns and tables we exclude/include and replaces
              a string value of our choice.
**
** Auth:	  Copyleft, Milan Polak (2018 - Now)
** Ref:	  (https://www.copyleft.org/)
**
** Sample Usage: Provide the target DB name into the USE statement.
                 Skip to the 'Settings' area. Change the settings to
                 match your business case and execute.
**
** Change History:
**
** Version	 Date		 Author     Description 
** -------	 --------	-------     ------------------------------------
** 1.001    2018-04-01    Mpo       Initial Version
**
*********************************************************************************/

      USE [MyDB]; -- tet target DB

      -- =========================
  

      DECLARE @excludedTableNamesContaining AS TABLE (exTblConts VARCHAR(50))

      DECLARE @includeTableNamesContaining AS TABLE (exTblConts VARCHAR(50))

      DECLARE @excludeColumnNamesContaining AS TABLE (exTblConts VARCHAR(50))

      DECLARE @includeColumnNamesContaining AS TABLE (exTblConts VARCHAR(50))

      DECLARE @allowedDataTypes AS TABLE (alwdDTs VARCHAR(50))

      DECLARE @schema AS VARCHAR(100)

      DECLARE @oldValue AS VARCHAR(100)

      DECLARE @newValue AS VARCHAR(100)

      DECLARE @loopCnt INT;

      DECLARE @intCountO INT;

      DECLARE @curentTable AS VARCHAR(100);

      DECLARE @curentColumn AS VARCHAR(100);

      DECLARE @sql AS NVARCHAR(1000);

      DECLARE @sqlUpdateValue AS NVARCHAR(1000);

      DECLARE @sqlToggleTrigger AS NVARCHAR(1000);

      SET @intCountO = 0;



      -- cleanup just in case and create depends.

      IF OBJECT_ID('tempdb.dbo.#report', 'U') IS NOT NULL  DROP TABLE #report;

      IF OBJECT_ID('tempdb.dbo.#objIds', 'U') IS NOT NULL  DROP TABLE #objIds;

      CREATE TABLE #report (bef VARCHAR(max), aft VARCHAR(MAX));

      CREATE TABLE #objIds (tblName VARCHAR(100), colName VARCHAR(100), id INT, oid INT);



      /* ***********************************************************************************************

      **************************************************************************************************



                                          SETTINGS

                                          --------

      */



      -- !DON'T FORGET THE 'USE DB' STATEMENT ON THE TOP! --



      -- THE VALUE WE WANT TO CHANGE (FROM -> TO) --

      SET @oldValue = 'oldstring'

      SET @newValue = 'newstring'   



      -- DB SCHEMA IT AFFECTS --         

      SET @schema = 'dbo'



      -- NAMES OR PARTIALS OF THE TABLES WE SHOULD EXCLUDE FROM THE REPLACE --

      INSERT INTO @excludedTableNamesContaining VALUES ('%mytable1%'), ('mytable2%'), ('mytable3')



      -- NAMES OR PARTIALS OF THE TABLES WE EXPLICITLY WANT TO BE INCLUDED --

      INSERT INTO @includeTableNamesContaining VALUES ('%mycolumn1%'), ('mycolumn2%'), ('mycolumn3%')



      -- NAMES OR PARTIALS OF THE COLUMNS WE SHOULD EXCLUDE FROM THE REPLACE --

      INSERT INTO @excludeColumnNamesContaining VALUES ('%mytable4%'), ('mytable5%'), ('mytable6')



      -- NAMES OR PARTIALS OF THE COLUMNS WE EXPLICITLY WANT TO BE INCLUDED --

      INSERT INTO @includeColumnNamesContaining VALUES ('%mycolumn4%'), ('mycolumn5%'), ('mycolumn6')



      -- KEPP AS IS (Other datatypes may work but could fail on implicit conversions (included in ToDo list)

      INSERT INTO @allowedDataTypes VALUES ('char'), ('varchar')



      /* ***********************************************************************************************

      *********************************************************************************************** */



      -- Populate the temp table

      -- ========================

      INSERT INTO #objIds



      SELECT DISTINCT

            [isc].TABLE_NAME,

            [isc].COLUMN_NAME,

            0,

            Object_id

      FROM sys.objects AS [tso]

      INNER JOIN information_schema.COLUMNS AS [isc]

            ON [tso].NAME = [isc].TABLE_NAME

            AND [isc].DATA_TYPE IN (SELECT * FROM @allowedDataTypes)

            AND Object_id NOT IN(

                              SELECT Object_id FROM sys.objects AS [_tso]

                              INNER JOIN @excludedTableNamesContaining AS [_tsc]

                              ON [_tso].[NAME] LIKE [_tsc].[exTblConts])



            AND Object_id IN(

                              SELECT Object_id FROM sys.objects AS [_tso]

                              INNER JOIN @includeTableNamesContaining AS [_tsc]

                              ON [_tso].[NAME] LIKE [_tsc].[exTblConts])



            AND [isc].COLUMN_NAME NOT IN(

                              SELECT [_isc].[COLUMN_NAME] FROM information_schema.COLUMNS AS [_isc]

                              INNER JOIN @excludeColumnNamesContaining AS [_csc]

                              ON [_isc].[COLUMN_NAME] LIKE [_csc].[exTblConts])



            AND [isc].COLUMN_NAME IN(

                              SELECT [_isc].[COLUMN_NAME] FROM information_schema.COLUMNS AS [_isc]

                              INNER JOIN @includeColumnNamesContaining AS [_csc]

                              ON [_isc].[COLUMN_NAME] LIKE [_csc].[exTblConts])



            WHERE [tso].[type] = 'U'

                  AND [isc].DOMAIN_SCHEMA = @schema

            ORDER BY [isc].TABLE_NAME ASC;





      -- Give each record an order Id for further processing

      -- ===================================================

      ;WITH cte_numberIt(rowId, id)

      AS

      (

            SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) as rowId, id

            FROM #objIds

      )

      UPDATE cte_numberIt

      SET id = rowId

      OPTION (MAXDOP 1, MAXRECURSION 1000) -- one core, 1,000 row limit



      SELECT * FROM #objIds





      -- Loop throug all selected columns and changed the value

      -- =================================================================

      SET @loopCnt = (SELECT COUNT(id) FROM #objIds);



            WHILE @loopCnt <> 0

                  BEGIN

                        SELECT @curentTable = [name],

                              @curentColumn =

                        (

                              SELECT colName

                              FROM #objIds

                              WHERE id = @loopCnt

                        )

                        FROM sys.objects

                        WHERE object_id =

                        (

                              SELECT oid

                              FROM #objIds

                              WHERE id = @loopCnt

                        );



                        -- Check weather there is anything to replace in the selected table

                        -- ================================================================

                        SET @sql = 'SET @intCount = (SELECT COUNT(*) FROM ['+@curentTable+'] WHERE ['+@curentColumn+'] LIKE ''' + @oldValue + ''')'    

                        EXEC sp_executesql @sql, N'@intCount INT OUT', @intCount = @intCountO OUTPUT;



                        IF @intCountO > 0

                              BEGIN

                                    -- Disable triggers on the table which is being updated

                                    SET @sqlToggleTrigger = 'ALTER TABLE [' + @curentTable + '] DISABLE TRIGGER all'

                                    EXEC sp_executesql @sqlToggleTrigger;

                        

                                    INSERT INTO #report VALUES(@curentTable, @curentColumn);



                                    SET @sqlUpdateValue =  

                                    'UPDATE [dbo].['+@curentTable+'] SET ['+@curentColumn+'] = '''+@newValue+'''

                                    OUTPUT DELETED.'+ @curentColumn +', INSERTED.'+@curentColumn +' INTO #report (bef, aft)

                                    WHERE ['+@curentColumn+'] = '''+@oldValue+'''';



                                    EXEC sp_executesql @sqlUpdateValue;



                                    -- Re-enable triggers on the table which is being updated

                                    SET @sqlToggleTrigger = 'ALTER TABLE [' + @curentTable + '] ENABLE TRIGGER all'

                                    EXEC sp_executesql @sqlToggleTrigger;



                              END

      

                        SET @loopCnt = @loopCnt - 1;

                  END;



      -- Show the applied changes and finish

      -- ===================================

      SELECT bef as 'Before', aft as 'After' FROM  #report

      IF OBJECT_ID('tempdb.dbo.#report', 'U') IS NOT NULL  DROP TABLE #report;

      IF OBJECT_ID('tempdb.dbo.#objIds', 'U') IS NOT NULL  DROP TABLE #objIds;

      PRINT 'Script completed!'

      GO
