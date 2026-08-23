' Runs a command completely hidden (no console flash), waits for it to
' finish, and exits with its real exit code -- used by world.shelleo()
' (code/__HELPERS/shell.dm) as the Windows interpreter in place of a bare
' "cmd /c", which otherwise pops a visible console window on every shelled
' command (the "Trigger Database Backup" / "Sync Deployment Branch" admin
' verbs). wscript.exe is a GUI-subsystem binary -- unlike cmd.exe/cscript.exe,
' it never allocates a console of its own, so launching THIS instead of
' cmd.exe directly is what actually eliminates the flash.
'
' Reassembles all of its own arguments back into one string and hands that
' to a hidden "cmd /c" itself, so redirection (">"/"2>") in the original
' command still gets interpreted by a real cmd.exe exactly as before --
' just one launched with window style 0 (hidden) instead of visibly.
' An argument containing a space MUST be re-quoted on the way back out. The
' shell strips the quotes that held it together as one argument, so joining
' them back with plain spaces would split a path like
' "D:\Git Storage\Aurora-Persistence\data\shelleo_cd_x.bat" into two tokens and
' cmd would fail to find it -- exit 1, no output, which is indistinguishable
' from the command itself having failed. Arguments without spaces are left
' exactly as-is, so a normal multi-token command (e.g. "script.bat silent")
' still reassembles the way it always did.
Set objShell = CreateObject("WScript.Shell")
Dim fullCommand, i, arg
fullCommand = ""
For i = 0 To WScript.Arguments.Count - 1
	If i > 0 Then
		fullCommand = fullCommand & " "
	End If
	arg = WScript.Arguments(i)
	If InStr(arg, " ") > 0 And Left(arg, 1) <> """" Then
		arg = """" & arg & """"
	End If
	fullCommand = fullCommand & arg
Next
WScript.Quit objShell.Run("cmd /c " & fullCommand, 0, True)
