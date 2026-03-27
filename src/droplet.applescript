-- Claude Crutches - Multi-format file converter droplet
-- Drop Excel files, PDFs, or folders to convert them for Claude upload

on open droppedItems
	set appPath to (path to me as text)
	set bundlePosix to POSIX path of appPath
	set excelScript to bundlePosix & "Contents/Resources/excel_to_csv.py"
	set pdfTool to bundlePosix & "Contents/Resources/pdf-to-files"
	set vendorDir to bundlePosix & "Contents/Resources/vendor"

	-- Collect all convertible files from dropped items
	set excelFiles to {}
	set pdfFiles to {}
	repeat with anItem in droppedItems
		set itemPosix to POSIX path of (anItem as text)
		set {foundExcel, foundPdf} to findConvertibleFiles(itemPosix)
		set excelFiles to excelFiles & foundExcel
		set pdfFiles to pdfFiles & foundPdf
	end repeat

	if (count of excelFiles) is 0 and (count of pdfFiles) is 0 then
		display dialog "No convertible files found." & return & return & ¬
			"Supported: .xlsx, .xls, .pdf" with title "Claude Crutches" buttons {"OK"} default button "OK" with icon caution
		return
	end if

	-- Check Python 3 for Excel files
	if (count of excelFiles) > 0 then
		try
			do shell script "/usr/bin/python3 --version"
		on error
			display dialog "Python 3 is required for Excel conversion but not found." & return & return & ¬
				"Install Xcode Command Line Tools:" & return & ¬
				"  xcode-select --install" with title "Claude Crutches" buttons {"OK"} default button "OK" with icon stop
			return
		end try
	end if

	set converted to {}
	set skipped to {}
	set errored to {}

	-- Process Excel files
	repeat with excelFile in excelFiles
		set outputDir to excelFile & "-csv"
		try
			do shell script "test -d " & quoted form of outputDir
			set end of skipped to excelFile as text
		on error
			try
				set envPrefix to "PYTHONPATH=" & quoted form of vendorDir
				do shell script envPrefix & " /usr/bin/python3 " & quoted form of excelScript & " " & quoted form of (excelFile as text)
				set end of converted to excelFile as text
			on error errMsg
				set end of errored to (excelFile as text) & ": " & errMsg
			end try
		end try
	end repeat

	-- Process PDF files
	repeat with pdfFile in pdfFiles
		set outputDir to pdfFile & "-files"
		try
			do shell script "test -d " & quoted form of outputDir
			set end of skipped to pdfFile as text
		on error
			try
				do shell script quoted form of pdfTool & " " & quoted form of (pdfFile as text)
				set end of converted to pdfFile as text
			on error errMsg
				set end of errored to (pdfFile as text) & ": " & errMsg
			end try
		end try
	end repeat

	-- Build summary
	set summary to ""

	if (count of converted) > 0 then
		set summary to summary & "Converted (" & (count of converted) & "):" & return
		repeat with f in converted
			set summary to summary & "  " & shortName(f as text) & return
		end repeat
	end if

	if (count of skipped) > 0 then
		if summary is not "" then set summary to summary & return
		set summary to summary & "Skipped (already exist) (" & (count of skipped) & "):" & return
		repeat with f in skipped
			set summary to summary & "  " & shortName(f as text) & return
		end repeat
	end if

	if (count of errored) > 0 then
		if summary is not "" then set summary to summary & return
		set summary to summary & "Errors (" & (count of errored) & "):" & return
		repeat with e in errored
			set summary to summary & "  " & (e as text) & return
		end repeat
	end if

	display dialog summary with title "Claude Crutches" buttons {"OK"} default button "OK"
end open

-- Recursively find convertible files, returning {excelList, pdfList}
on findConvertibleFiles(posixPath)
	set excelResults to {}
	set pdfResults to {}

	try
		set fileType to do shell script "file -b " & quoted form of posixPath
		if fileType contains "directory" then
			set foundFiles to do shell script "find " & quoted form of posixPath & " -type f \\( -name '*.xlsx' -o -name '*.xls' -o -name '*.pdf' \\) -not -name '~$*' -not -name '.*' 2>/dev/null || true"
			if foundFiles is not "" then
				set oldDelims to AppleScript's text item delimiters
				set AppleScript's text item delimiters to {return}
				set fileList to text items of foundFiles
				set AppleScript's text item delimiters to oldDelims
				repeat with f in fileList
					set fText to f as text
					if fText is not "" then
						if fText ends with ".xlsx" or fText ends with ".xls" then
							set end of excelResults to fText
						else if fText ends with ".pdf" then
							set end of pdfResults to fText
						end if
					end if
				end repeat
			end if
		else
			if posixPath ends with ".xlsx" or posixPath ends with ".xls" then
				set end of excelResults to posixPath
			else if posixPath ends with ".pdf" then
				set end of pdfResults to posixPath
			end if
		end if
	end try

	return {excelResults, pdfResults}
end findConvertibleFiles

on shortName(posixPath)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "/"
	set parts to text items of posixPath
	set AppleScript's text item delimiters to oldDelims
	return last item of parts
end shortName
