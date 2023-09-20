IMPORT os
DEFINE m_c base.Channel
MAIN
	DEFINE c base.Channel
	DEFINE l_db STRING
	DEFINE l_file STRING
	LET c = base.Channel.create()
	IF base.Application.getArgumentCount() < 2 THEN
		DISPLAY SFMT("Not enough args!\nfglrun %1 <db> <file>", base.Application.getProgramName())
		EXIT PROGRAM
	END IF
	LET l_db = base.Application.getArgument(1)
	LET l_file = base.Application.getArgument(2)
	IF NOT os.Path.exists(l_file) THEN
		DISPLAY SFMT("File '%1' doesn't exist!", l_file)
		EXIT PROGRAM
	END IF
	LET m_c = base.Channel.create()
	CALL m_c.openFile("tests2.4gl", "w")
	CALL out(SFMT("SCHEMA %1", l_db))
	CALL out("")
	CALL c.openFile(l_file, "r")
	WHILE NOT c.isEof()
		CALL proc(c.readLine())
	END WHILE
	CALL c.close()
	CALL m_c.close()
END MAIN
--------------------------------------------------------------------------------
FUNCTION proc(l_line STRING)
	DEFINE l_st      base.StringTokenizer
	DEFINE l_func    STRING
	DEFINE l_proc    CHAR(1)
	DEFINE l_lines   SMALLINT
	DEFINE l_cntsql  SMALLINT
	DEFINE l_cnttrg  SMALLINT
	DEFINE l_cntfgl  SMALLINT
	DEFINE l_cntfglf SMALLINT
	DEFINE l_params  STRING
	DEFINE l_proto   STRING
	DEFINE l_out     STRING
	DEFINE l_rets, x SMALLINT
	DEFINE l_invars  DYNAMIC ARRAY OF STRING

	IF l_line IS NULL THEN
		RETURN
	END IF

	LET l_st      = base.StringTokenizer.create(l_line, ",")
	LET l_func    = l_st.nextToken()
	LET l_proc    = l_st.nextToken()
	LET l_lines   = l_st.nextToken()
	LET l_cntsql  = l_st.nextToken()
	LET l_cnttrg  = l_st.nextToken()
	LET l_cntfgl  = l_st.nextToken()
	LET l_cntfglf = l_st.nextToken()

	CALL out("--------------------------------------------------------------------------------")
	CALL out(SFMT("-- %1 %2", l_func, IIF(l_proc = "p", "Procedure", "Function")))
	CALL getParams(l_func, l_proc) RETURNING l_params, l_proto, l_rets, l_invars
	DISPLAY SFMT("Invars: %1", l_invars.getLength())
	CALL out(SFMT("{%1}", l_proto))
	CALL out(SFMT("FUNCTION test_%1(%2 ", l_func, l_params))
	CALL out("")
	IF l_proc = "p" THEN
		CALL out(SFMT("  EXECUTE IMMEDIATE \"EXECUTE PROCEDURE %1()\"", l_func))
	ELSE
		LET l_out = SFMT("  PREPARE pre_%1 FROM \"EXECUTE FUNCTION %1(", l_func)
		IF l_invars.getLength() > 0 THEN
			FOR x = 1 TO l_invars.getLength()
				LET l_out = l_out.append("?")
				IF x < l_invars.getLength() THEN
					LET l_out = l_out.append(", ")
				END IF
			END FOR
		END IF
		CALL out(l_out || ")\"")
		CALL out(SFMT("  DECLARE cur_%1 CURSOR FOR pre_%1 ", l_func))
		LET l_out = SFMT("  OPEN cur_%1", l_func)
		IF l_invars.getLength() > 0 THEN
			LET l_out = l_out.append(" USING ")
			FOR x = 1 TO l_invars.getLength()
				LET l_out = l_out.append(l_invars[x])
				IF x < l_invars.getLength() THEN
					LET l_out = l_out.append(", ")
				END IF
			END FOR
		END IF
		CALL out(l_out)
		LET l_out = SFMT("  FETCH cur_%1", l_func)
		IF l_rets > 0 THEN
			LET l_out = l_out.append(" INTO ")
			FOR x = 1 TO l_rets
				LET l_out = l_out.append(SFMT("p%1", x))
				IF x < l_rets THEN
					LET l_out = l_out.append(",")
				END IF
			END FOR
		END IF
		CALL out(l_out)
		CALL out(SFMT("  CLOSE cur_%1", l_func))
	END IF
	CALL out("")
	IF l_rets > 0 THEN
		LET l_out = "  RETURN "
		FOR x = 1 TO l_rets
			LET l_out = l_out.append(SFMT("p%1", x))
			IF x < l_rets THEN
				LET l_out = l_out.append(",")
			END IF
		END FOR
		CALL out(l_out)
	END IF
	CALL out("END FUNCTION")

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION getParams(l_func STRING, l_pf CHAR(1)) RETURNS(STRING, STRING, SMALLINT, DYNAMIC ARRAY OF STRING)
	DEFINE c              base.Channel
	DEFINE l_line         STRING
	DEFINE l_proto        base.StringBuffer
	DEFINE l_params       base.StringBuffer
	DEFINE b, bc, x, y, z SMALLINT
	DEFINE l_start        BOOLEAN = FALSE
	DEFINE l_rets         base.StringBuffer
	DEFINE l_rcnt         SMALLINT = 0
	DEFINE l_bcnt         SMALLINT -- bracket counter
	DEFINE l_in           base.StringBuffer
	DEFINE l_in_s         STRING
	DEFINE l_type         STRING
	DEFINE l_invars       DYNAMIC ARRAY OF STRING
	DEFINE l_invars_t     DYNAMIC ARRAY OF STRING
	DEFINE l_outvars_t    DYNAMIC ARRAY OF STRING
	LET c = base.Channel.create()
	CALL c.openFile(os.Path.join("sqls", SFMT("%1.sql", l_func)), "r")
	LET l_params = base.StringBuffer.create()
	LET l_proto  = base.StringBuffer.create()
	LET l_rets   = base.StringBuffer.create()
	WHILE NOT c.isEof()
		LET l_line = c.readLine()
--		DISPLAY SFMT("l_line:'%1'", l_line)
		LET l_line = l_line.trim()
		IF l_line.getLength() < 1 THEN
			EXIT WHILE
		END IF
		LET l_line = fixReturning(l_line)
		DISPLAY SFMT("l_line:'%1'", l_line)
		LET x = 1
		IF NOT l_start THEN
			LET x = l_line.getIndexOf("(", 1) + 1
		END IF
		IF x > 1 THEN
			LET l_start = TRUE
		END IF
		CALL l_proto.append(l_line)
		IF l_line.getIndexOf("--", 1) > 0 THEN
			CALL l_proto.append("\n ")
		ELSE
			CALL l_proto.append(" ")
		END IF
		IF NOT l_start AND x < 2 THEN
			CONTINUE WHILE
		END IF
		LET z = l_line.getIndexOf(";", 1) - 1
-- try and find if we have a close bracket for the function/procedures to handle if we no ; at the end of the line
		IF l_start THEN
			LET b      = 1
			LET l_bcnt = 0
			WHILE b > 0
				LET b = l_proto.getIndexOf("(", b + 1)
				IF b > 0 THEN
					LET l_bcnt = l_bcnt + 1
				END IF
--				DISPLAY SFMT("( l_proto: %1 b: %2 l_bcnt: %3", l_proto.toString(), b, l_bcnt)
			END WHILE
			LET b = 1
			WHILE b > 0
				LET b = l_proto.getIndexOf(")", b + 1)
				IF b > 0 THEN
					LET l_bcnt = l_bcnt - 1
--					DISPLAY SFMT(") l_proto: %1 b: %2 l_bcnt: %3  bc: %4", l_proto.toString(), b, l_bcnt, bc)
					IF l_bcnt = 0 THEN
						LET bc = b -- save close bracket position
						EXIT WHILE
					END IF
				END IF
			END WHILE
--			DISPLAY SFMT("l_proto: %1 z: %2 b: %3 bc: %4 l_bcnt: %5", l_proto.toString(), z, b, bc, l_bcnt)
			IF z = -1 AND l_bcnt = 0 AND l_pf = "p" THEN -- if no ; and we found last ) for function then add a ;
				IF l_proto.getIndexOf(" returns ",1) = 0 THEN
					CALL l_proto.append(";")
				END IF
			END IF
		END IF
		LET z = l_line.getIndexOf(";", 1) - 1
		IF z > -1 THEN
			EXIT WHILE
		END IF
	END WHILE
	LET l_line = l_proto.toString()
	LET b      = l_line.getIndexOf("(", 1)
	LET z      = l_line.getIndexOf(";", 1)
	LET x      = l_line.getIndexOf(" returns ", 1)
	IF x > 0 THEN
		LET bc = x - 1
	END IF

	DISPLAY SFMT("l_line:\n'%1'", l_line)
	DISPLAY " 123456789 123456789 123456789 123456789 1234567890"
	DISPLAY SFMT("b=%1  z=%2  x=%3  bc=%4", b, z, x, bc)
	LET l_in = base.StringBuffer.create()
	CALL l_in.append(l_line.subString(b + 1, bc - 1))
	LET l_in_s = l_in.toString().trim()
	LET y      = 1
	LET x      = 1
	WHILE TRUE
		DISPLAY SFMT("'%1'",l_in_s)
		DISPLAY " 123456789 123456789 123456789 123456789 1234567890"
		DISPLAY SFMT("y: %1 charY: '%2' ", y, l_in_s.getCharAt(y))
		LET x = l_in_s.getIndexOf(" ", y)
		IF x = 0 THEN
			EXIT WHILE
		END IF
		LET l_invars[l_invars.getLength() + 1] = l_in_s.subString(y, x - 1)
		LET z = l_in_s.getIndexOf("\n",x) -1
		IF z < 1 THEN
			LET z = l_in_s.getIndexOf(",", x) - 1
		END IF
		IF z < 1 THEN
			LET z = l_in_s.getLength()
		END IF
		LET l_type = l_in_s.subString(x + 1, z)
		IF l_type.subString(1, 8).toLowerCase() = "decimal(" THEN
			DISPLAY "Found decimal("
			LET z = l_in_s.getIndexOf(")", x + 1)
			WHILE TRUE
				LET z = z + 1
				IF l_in_s.subString(z,z+1) = "--" THEN
					WHILE TRUE
						LET z = z + 1
						IF z > l_in_s.getLength() THEN EXIT WHILE END IF
						IF l_in_s.getCharAt(z) = "\n" THEN EXIT WHILE END IF
						LET l_type = l_type.append( l_in_s.getCharAt(z) )
					END WHILE
				END IF
				IF z > l_in_s.getLength() THEN EXIT WHILE END IF
				IF l_in_s.getCharAt(z) = "," THEN EXIT WHILE END IF
				LET l_type = l_type.append( l_in_s.getCharAt(z) )
			END WHILE
		END IF
		IF l_type.getIndexOf("--",3) > 0 THEN
			IF l_in_s.getIndexOf("\n",x) > 0 THEN
				DISPLAY "Found comment with newline"
				LET z = l_in_s.getIndexOf("\n",x)
			ELSE
				DISPLAY "Found comment without newline"
			END IF
		END IF
		LET l_invars_t[l_invars_t.getLength() + 1] = l_type
		DISPLAY SFMT("y: %1 x: %2 z: %3 Var: %4 Type: %5", y, x, z, l_in_s.subString(y, x - 1), l_type)
		LET y = z + 1
		WHILE (l_in_s.getCharAt(y) = " " OR l_in_s.getCharAt(y) = "," OR l_in_s.getCharAt(y) = "\n")
			LET y = y + 1
		END WHILE
		IF y >= l_in_s.getLength() THEN
			EXIT WHILE
		END IF
	END WHILE
	DISPLAY SFMT("Found: %1", l_invars.getLength())
	FOR x = 1 TO l_invars.getLength()
		DISPLAY SFMT("%1 is %2", l_invars[x], l_invars_t[x])
	END FOR

	--CALL out(SFMT("-- In: %1", l_in.toString() ) )
	CALL l_params.append(l_in_s)
--	LET z = l_line.getLength()
--	CALL l_params.append(l_line.subString(bc, z))
	--CALL out(SFMT("-- Out: %1", l_line.subString(bc+9, z-1)))
	CALL l_params.append(") ")

-- handle RETURNS
	DISPLAY "*** RETURNS Handling ***"
	LET x = l_line.getIndexOf(" returns ", 1)
	IF x > 1 THEN
		LET l_line = l_line.subString(x + 8, l_line.getLength())
		LET l_line = l_line.trim()
		LET x      = 1
		WHILE TRUE
			DISPLAY l_line
			DISPLAY "1234567890123456789012345678901234567890"
			LET z = l_line.getIndexOf(",", x) - 1
			IF z < 1 THEN
				LET z = l_line.getIndexOf(";", x) - 1
				IF z < 1 THEN
					LET z = l_line.getLength()
				END IF
			END IF
			LET l_in_s = l_line.subString(x, z)
			IF l_in_s.subString(1, 8).toLowerCase() = "decimal(" THEN
				LET z = l_line.getIndexOf(")", x + 1)
				LET l_in_s = l_line.subString(x, z)
			END IF
			IF l_in_s.getIndexOf("--",1) > 0 THEN
				LET z = l_line.getIndexOf("\n", x)
				LET l_in_s = l_line.subString(x, z-1)
			END IF
			DISPLAY SFMT("x: %1 z: %2 Type: '%3'", x, z, l_in_s)
			IF x > z THEN EXIT WHILE END IF
			IF l_in_s.subString(1,2) = "--" THEN
--				LET l_outvars_t[l_outvars_t.getLength()] = l_outvars_t[l_outvars_t.getLength()].append( l_in_s )
			ELSE
				IF l_in_s.getIndexOf(" as ",1) > 0 THEN
					LET l_in_s = removeAs( l_in_s )
				END IF
				LET l_outvars_t[l_outvars_t.getLength() + 1] = l_in_s
			END IF
			LET x = z + 1
			WHILE (l_line.getCharAt(x) = " " OR l_line.getCharAt(x) = "," OR l_line.getCharAt(x) = "\n")
				LET x = x + 1
			END WHILE
			IF x >= l_line.getLength() THEN
				EXIT WHILE
			END IF
		END WHILE
		DISPLAY SFMT("Found: %1", l_outvars_t.getLength())
		CALL l_params.append(" RETURNS ( ")
		FOR x = 1 TO l_outvars_t.getLength()
			CALL l_params.append( l_outvars_t[x] )
			CALL l_rets.append(SFMT("\n  DEFINE p%1 %2", x, l_outvars_t[x].toUpperCase()))
			IF x < l_outvars_t.getLength() THEN
				CALL l_params.append( "\n,\t" )
			END IF
		END FOR
		IF l_outvars_t.getLength() > 1 THEN
				CALL l_params.append( "\t\n" )
		END IF
		CALL l_params.append(" )")
		CALL l_params.append(l_rets.toString())
	END IF

	CALL c.close()
	CALL l_params.replace(";", "", 0)
	RETURN l_params.toString(), l_proto.toString(), l_outvars_t.getLength(), l_invars
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION fixReturning(l_str STRING) RETURNS STRING
	DEFINE sb base.StringBuffer
	LET sb = base.StringBuffer.create()
	CALL sb.append( " " )
	CALL sb.append( l_str )
	CALL sb.append( " " )
	CALL sb.replace("\t", " ", 0)  -- replace tabs
	CALL sb.replace(";returning ", " returns ", 1) -- fix issue with procedures that return!
	CALL sb.replace(")returning ", ") returns ", 1) -- fix issue with procedures that return!
	CALL sb.replace(" returning ", " returns ", 1)  -- handle that some functions say returns instead of returning!
	CALL sb.replace(" RETURNING ", " returns ", 1)  -- handle that some functions say returns instead of returning!
	CALL sb.replace(" RETURNS ", " returns ", 1)  -- handle upper case
	CALL sb.replace(" nchar", " CHAR", 0)       -- Genero doesn't support nchar
	CALL sb.replace(" nvarchar", " VARCHAR", 0) -- Genero doesn't support nvarchar
	CALL sb.replace(" lvarchar", " VARCHAR", 0) -- Genero doesn't support lvarchar
	RETURN sb.toString().trim()
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION removeAs(l_str STRING) RETURNS STRING
	DEFINE x, y SMALLINT
	DEFINE l_ret STRING
	LET y = l_str.getIndexOf(" as ",1)
	LET l_ret = l_str.subString(1,y)
	LET l_ret = l_ret.append( "{ as " )
	FOR x = y+5 TO l_str.getLength()
		LET l_ret = l_ret.append( l_str.getCharAt(x) )
		IF l_str.getCharAt(x) = " " THEN
			LET l_ret = l_ret.append( l_str.subString( x+1, l_str.getLength() ) )
			EXIT FOR
		END IF
	END FOR
	LET l_ret = l_ret.append( "}" )
	RETURN l_ret
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION out(l_str STRING)
	DISPLAY l_str
	CALL m_c.writeLine(l_str.trimRight())
END FUNCTION
