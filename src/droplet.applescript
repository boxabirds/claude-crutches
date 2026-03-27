-- Claude Crutches - Excel to CSV Droplet
-- Drop Excel files or folders to convert each sheet to a separate CSV

on open droppedItems
	set appPath to (path to me as text)
	set bundlePosix to POSIX path of appPath
	set pythonScript to bundlePosix & "Contents/Resources/excel_to_csv.py"
	set vendorDir to bundlePosix & "Contents/Resources/vendor"

	-- Check Python 3 is available
	try
		do shell script "/usr/bin/python3 --version"
	on error
		display dialog "Python 3 is required but not found." & return & return & ¬
			"Install Xcode Command Line Tools:" & return & ¬
			"  xcode-select --install" with title "Claude Crutches" buttons {"OK"} default button "OK" with icon stop
		return
	end try

	-- Collect all Excel files from dropped items
	set excelFiles to {}
	repeat with anItem in droppedItems
		set itemPosix to POSIX path of (anItem as text)
		set excelFiles to excelFiles & findExcelFiles(itemPosix)
	end repeat

	if (count of excelFiles) is 0 then
		display dialog "No Excel files (.xlsx, .xls) found in the dropped items." with title "Claude Crutches" buttons {"OK"} default button "OK" with icon caution
		return
	end if

	-- Process each Excel file
	set converted to {}
	set skipped to {}
	set errored to {}

	repeat with excelFile in excelFiles
		set outputDir to excelFile & "-csv"

		-- Check if output already exists
		try
			do shell script "test -d " & quoted form of outputDir
			set end of skipped to excelFile as text
		on error
			-- Output doesn't exist, convert
			try
				set envPrefix to "PYTHONPATH=" & quoted form of vendorDir
				do shell script envPrefix & " /usr/bin/python3 " & quoted form of pythonScript & " " & quoted form of (excelFile as text)
				set end of converted to excelFile as text
			on error errMsg
				set end of errored to (excelFile as text) & ": " & errMsg
			end try
		end try
	end repeat

	-- Build summary
	set summary to ""

	if (count of converted) > 0 then
		set summary to summary & "Converted (" & (count of converted) & "):" & return
		repeat with f in converted
			set summary to summary & "  ✓ " & shortName(f as text) & return
		end repeat
	end if

	if (count of skipped) > 0 then
		if summary is not "" then set summary to summary & return
		set summary to summary & "Skipped (already exist) (" & (count of skipped) & "):" & return
		repeat with f in skipped
			set summary to summary & "  – " & shortName(f as text) & return
		end repeat
	end if

	if (count of errored) > 0 then
		if summary is not "" then set summary to summary & return
		set summary to summary & "Errors (" & (count of errored) & "):" & return
		repeat with e in errored
			set summary to summary & "  ✗ " & (e as text) & return
		end repeat
	end if

	display dialog summary with title "Claude Crutches" buttons {"OK"} default button "OK"
end open

-- Recursively find Excel files in a path
on findExcelFiles(posixPath)
	set results to {}

	-- Check if it's a directory
	try
		set fileType to do shell script "file -b " & quoted form of posixPath
		if fileType contains "directory" then
			-- Find all Excel files recursively
			set foundFiles to do shell script "find " & quoted form of posixPath & " -type f \\( -name '*.xlsx' -o -name '*.xls' \\) -not -name '~$*' -not -name '.*' 2>/dev/null || true"
			if foundFiles is not "" then
				set oldDelims to AppleScript's text item delimiters
				set AppleScript's text item delimiters to {return}
				set fileList to text items of foundFiles
				set AppleScript's text item delimiters to oldDelims
				repeat with f in fileList
					if f as text is not "" then
						set end of results to f as text
					end if
				end repeat
			end if
		else
			-- Single file - check extension
			if posixPath ends with ".xlsx" or posixPath ends with ".xls" then
				set end of results to posixPath
			end if
		end if
	end try

	return results
end findExcelFiles

-- Extract filename from path
on shortName(posixPath)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "/"
	set parts to text items of posixPath
	set AppleScript's text item delimiters to oldDelims
	return last item of parts
end shortName
