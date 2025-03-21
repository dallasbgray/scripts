<#
.SYNOPSIS
    Prepends a formatted date to the beginning of image file names
.DESCRIPTION
    Runs Get-ChildItem on the provided path and filters Where-Object file extensions are certain image types. Then attempts to use the Windows Shell COM object to access the Date Taken property that isn't directly accessible through .NET's System.IO classes. If this date is found, it then formats & prepends that to the beginning of the image filename
.PARAMETER FolderPath
    Specifies a path to the folder of images to rename
.PARAMETER Extension
	Singular image file extension to filter by, e.g. '.jpg', '.jpeg', or '.cr2'.
.PARAMETER IncludeVideos
	Searches for and renames video files that match with an image's filename, e.g. a "live" photo that was split into  a .jpeg and .mov file with the same filename
.PARAMETER Revert
	Attempts to revert the changes made previously by the command by matching the beginning of the filename with the formatted prefix & removing it
.EXAMPLE
    PS C:\> Rename-DatedImages -Verbose -FolderPath C:\Path-To-Photos-Here\photos
.NOTES
    Author: Dallas Gray
    Date:   August 8th, 2024
#>
Function Rename-DatedImages {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript(
			{ Test-Path -Path $_ },
			ErrorMessage = "'{0}' is not a valid directory according to '{1}'")
		]
		[string]$FolderPath,

		[string]$Extension,

		[switch]$IncludeVideos,

		[switch]$Revert
	)

	# thread-safe in order to allow the -Parallel option in ForEach-Object in a future implementation
	$threadSafeDictionary = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()
	$threadSafeDictionary.TryAdd("numTotal", 0) > $null # redirect to $null to ignore the return value
	$threadSafeDictionary.TryAdd("numImgModified", 0) > $null
	$threadSafeDictionary.TryAdd("numVidModified", 0) > $null
	$threadSafeDictionary.TryAdd("numSkipped", 0) > $null
	$threadSafeDictionary.TryAdd("numErrored", 0) > $null

	$ImageExtensions = if ($Extension) { $Extension } else { '.jpg', '.jpeg', '.heic', '.cr2' }
	$VideoExtensions = '.mov', '.mp4', '.mkv'

	Write-Host "`n`n	Renaming images with file extensions $ImageExtensions`n" -ForegroundColor DarkBlue
	if ($true)
	{
		Write-Host "	Renaming videos (with same filename as the image) with file extensions $VideoExtensions`n" -ForegroundColor DarkBlue
	}

	Measure-Command {
		Get-ChildItem -Recurse -Depth 3 -Path $FolderPath `
		| Where-Object { $_.Extension -in $ImageExtensions } `
		| ForEach-Object {
			try {
				$threadSafeDictionary["numTotal"]++

				$DateFormat = 'yyyy-MM-dd'
				$DateFormatRegex = '^\d{4}-?\d{2}-?\d{0,2}[-_]?'
				$DateTakenWinApi = 12
				# $DateCreatedWinApi = 4
				$currentImageName = $_.Name
				$currentImageBaseName = $_.BaseName
				$newImageName = ""
					
				if ($Revert) {
					if ($currentImageName -match $DateFormatRegex) {
						# remove prefix if matched
						$newImageName = $currentImageName -replace $DateFormatRegex, ""
					}
				}
				else {
					# attempt to retrieve the Date Taken property
					if ($null -eq $Shell) {
						$Shell = New-Object -ComObject shell.application
					}
					$dir = $Shell.Namespace($_.DirectoryName)
					$DateTakenString = $dir.GetDetailsOf($dir.ParseName($_.Name), $DateTakenWinApi)
					if ($DateTakenString -eq '') {
						# can also use DateCreated as a substitute for DateTaken
						# $DateTakenString = $dir.GetDetailsOf($dir.ParseName($_.Name), $DateCreatedWinApi)
							
						$threadSafeDictionary["numSkipped"]++
						return # continue behaves like break in ForEach-Object, use return intead
					}
					
					# sanitze string
					$DateTakenString = $DateTakenString -replace '[^0-9AaPpMm\.\:\ \/]', ''
					# parse to DateTime
					$DateTaken = Get-Date $DateTakenString
					$FormattedDate = $DateTaken.ToString($DateFormat)

					$newImageName = $FormattedDate + "-" + $_.Name

					if ($IncludeVideos) {
						# search for video files with the same filename as the image (meaning they belong together, like iPhone "live" photos)
						$videoFiles = @(
							Get-ChildItem -Recurse -Depth 3 -Path $FolderPath `
								| Where-Object { $_.Extension -in $VideoExtensions -and $_.BaseName -eq $currentImageBaseName }
						) # get video files as an array

						foreach($video in $videoFiles)
						{
							# rename movie file with the same date as the image file was if found
							$currentVideoName = $video.Name
							$newVideoName = $FormattedDate + "-" + $video.Name
							
							Rename-Item -Path $video.FullName -NewName $newVideoName #-WhatIf -Confirm 
							$threadSafeDictionary["numVidModified"]++
							Write-Verbose "Renamed file $currentVideoName to $newVideoName"
						}
					}
				}
	
				if (![string]::IsNullOrWhiteSpace($newImageName)) {
					Rename-Item -Path $_.FullName -NewName $newImageName #-WhatIf -Confirm
					$threadSafeDictionary["numImgModified"]++
					Write-Verbose "Renamed file $currentImageName to $newImageName"
				}
			}
			catch {
				$threadSafeDictionary["numErrored"]++
				Write-Error "Error: $_"
			}
		}
	} | Select-Object TotalMilliseconds -OutVariable runtimeMillis


	# colored output
	Write-Host "`n`n	Script Finished Successfully`n" -ForegroundColor Green
	Write-Host "Modified " -NoNewline
	Write-Host $threadSafeDictionary["numImgModified"] -ForegroundColor Green -NoNewline
	Write-Host " images and " -NoNewline
	Write-Host $threadSafeDictionary["numVidModified"] -ForegroundColor Green -NoNewline
	Write-Host " videos."
	Write-Host "Skipped " -NoNewLine
	Write-Host $threadSafeDictionary["numSkipped"] -ForegroundColor Yellow -NoNewline
	Write-Host " files missing the DateTaken property, and " -NoNewline
	Write-Host $threadSafeDictionary["numErrored"] -ForegroundColor Red -NoNewline
	Write-Host " files had errors."
	Write-Host "Total image files checked: " -NoNewline
	Write-Host $threadSafeDictionary["numTotal"] -ForegroundColor Blue
	Write-Host "$runtimeMillis"
}


<#
.SYNOPSIS
    Warning: Parallel implementation is very slow, recommended to not use this function! Prepends a formatted date to the beginning of image file names
.DESCRIPTION
    Runs Get-ChildItem on the provided path and filters Where-Object file extensions are certain image types. Then attempts to use the Windows Shell COM object to access the Date Taken property that isn't directly accessible through .NET's System.IO classes. If this date is found, it then formats & prepends that to the beginning of the image filename
.PARAMETER FolderPath
    Specifies a path to the folder of images to rename
.PARAMETER Extension
	singular file extension to filter by, e.g. '.jpg', '.jpeg', or '.cr2'
.EXAMPLE
    PS C:\> Rename-DatedImages -Verbose -FolderPath C:\Path-To-Photos-Here\photos
.NOTES
    Author: Dallas Gray
    Date:   August 29th, 2024
#>
Function Rename-DatedImagesParallel {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript(
			{ Test-Path -Path $_ },
			ErrorMessage = "'{0}' is not a valid directory according to '{1}'")
		]
		[string]$FolderPath,

		[string]$Extension
	)

	# thread-safe in order to allow the -Parallel option in ForEach-Object
	$threadSafeDictionary = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()
	$threadSafeDictionary.TryAdd("numTotal", 0) > $null # redirect to $null to ignore the return value
	$threadSafeDictionary.TryAdd("numModified", 0) > $null
	$threadSafeDictionary.TryAdd("numSkipped", 0) > $null
	$threadSafeDictionary.TryAdd("numErrored", 0) > $null

	$Extensions = if ($Extension) { $Extension } else { '.jpg', '.jpeg', '.cr2' }
	Write-Host "`n`n	Renaming Images with file extensions $Extensions...`n" -ForegroundColor DarkBlue
	Write-Host "Warning: Parallel implementation is very slow, recommended to not use this function" -BackgroundColor Red

	Measure-Command {
		Get-ChildItem -Recurse -Depth 5 -Path $FolderPath `
		| Where-Object { $_.extension -in $Extensions } `
		| ForEach-Object -Parallel {
			try {
				$dict = $using:threadSafeDictionary
				$dict["numTotal"]++ # this worked, but is it atomic?
	
				$DateFormat = 'yyyy-MM-dd'
				$DateTakenWinApi = 12
				# $DateCreatedWinApi = 4
				if ($null -eq $Shell) {
					$Shell = New-Object -ComObject shell.application
				}
				$dir = $Shell.Namespace($_.DirectoryName)
				$DateTakenString = $dir.GetDetailsOf($dir.ParseName($_.Name), $DateTakenWinApi)
				if ($DateTakenString -eq '') {
					# can also use DateCreated as a substitute for DateTaken
					# $DateTakenString = $dir.GetDetailsOf($dir.ParseName($_.Name), $DateCreatedWinApi)
						
					$dict["numSkipped"]++
					return # continue behaves like break in ForEach-Object, use return intead
				}
				
				# sanitze string
				$DateTakenString = $DateTakenString -replace '[^0-9AaPpMm\.\:\ \/]', ''
				# parse to DateTime
				$DateTaken = Get-Date $DateTakenString
	
				$currentFileName = $_.Name
				$newFileName = $DateTaken.ToString($DateFormat) + "-" + $_.Name
				
				Rename-Item -Path $_.FullName -NewName $newFileName #-WhatIf -Confirm
				$dict["numModified"]++
	
				Write-Verbose "Renamed file $currentFileName to $newFileName"
			}
			catch {
				$dict = $using:threadSafeDictionary
				$dict["numErrored"]++
				Write-Error "an error occurred:"
				Write-Error "$_"
			}
		}
	} | Select-Object TotalMilliseconds -OutVariable runtimeMillis

	# colored output
	Write-Host "`n`n	Script Finished Successfully`n" -ForegroundColor Green
	Write-Host "Modified " -NoNewline
	Write-Host $threadSafeDictionary["numModified"] -ForegroundColor Green -NoNewline
	Write-Host " files, skipped " -NoNewline
	Write-Host $threadSafeDictionary["numSkipped"] -ForegroundColor Yellow -NoNewline
	Write-Host " files missing the DateTaken property, and " -NoNewline
	Write-Host $threadSafeDictionary["numErrored"] -ForegroundColor Red -NoNewline
	Write-Host " files had errors. Total: " -NoNewline
	Write-Host $threadSafeDictionary["numTotal"] -ForegroundColor Blue
	Write-Host "$runtimeMillis"
}


<#
.SYNOPSIS
    Displays relevant battery health information
.DESCRIPTION
    Only works on a device with a battery
.NOTES
    Author: Someone online, thanks
    Date Added: 12/16/2024
#>
Function BatteryHealthCheck {
    $Cycles = (Get-WmiObject -Class BatteryCycleCount -Namespace ROOT\WMI).CycleCount
    Write-Host "Charge cycles:`t $Cycles"
    
    $DesignCapacity = (Get-WmiObject -Class BatteryStaticData -Namespace ROOT\WMI).DesignedCapacity
    Write-Host "Design capacity: $DesignCapacity mAh"
    
    $FullCharge = (Get-WmiObject -Class BatteryFullChargedCapacity -Namespace ROOT\WMI).FullChargedCapacity
    Write-Host "Full charge:`t $FullCharge mAh"
    
    $BatteryHealth = ($FullCharge/$DesignCapacity)*100
    $BatteryHealth = [math]::Round($BatteryHealth,2)
    Write-Host "Battery health:`t $BatteryHealth%"
    
    $Discharge = (Get-WmiObject -Class BatteryStatus -Namespace ROOT\WMI).DischargeRate
    Write-Host "Discharge rate:`t $Discharge mA"
    
    $Charging = (Get-WmiObject -Class BatteryStatus -Namespace ROOT\WMI).ChargeRate
    Write-Host "Charging rate:`t $Charging mA"
}
