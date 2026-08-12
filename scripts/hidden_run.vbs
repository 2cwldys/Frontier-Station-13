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
Set objShell = CreateObject("WScript.Shell")
Dim fullCommand, i
fullCommand = ""
For i = 0 To WScript.Arguments.Count - 1
	If i > 0 Then
		fullCommand = fullCommand & " "
	End If
	fullCommand = fullCommand & WScript.Arguments(i)
Next
WScript.Quit objShell.Run("cmd /c " & fullCommand, 0, True)
