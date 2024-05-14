
##******************************************************************
## Revision date: 2024.05.13
##
## This script installs a RAM disk .
##
##		2023.04.11: Proof of concept / Initial release
##		2023.05.01: Cleanup and exit to console if started from RDP
##		2023.05.02: Add Privilege elevation
##		2023.05.03: Pause before switching to the server's console
##		2024.03.18: Revision
##		2024.05.10: Location of InstallFolder
##
## Usage:
##	This script is invoked without any parameter
##	It will create a 4GB RAM cache on partition P if the script CreateCache
##	is found in the same directory.
##
## Copyright (c) 2023-2024 PC-Évolution enr.
## This code is licensed under the GNU General Public License (GPL).
##
## THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
## ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
## IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
## PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
##
##******************************************************************

param (
	# Default parameter values
	[parameter( Mandatory = $false )] [string] $CacheDirectory = "P:\PLEXCache",
	[parameter( Mandatory = $false )] [UInt64] $CacheSize = 4GB
)

# --- Step 0: Is PLEX installed ? ---------------------------------------------------
#

# Set defaults and exit if PLEX binary is not found.
#
Try {

	$PLEXInstallFolder = $(Get-ItemProperty -Path "HKCU:\Software\Plex, Inc.\Plex Media Server" `
			-Name InstallFolder  -ErrorAction SilentlyContinue).InstallFolder
	# Sometime after Version 1.31.3, this was moved to HKLM
	If ($Null -eq $PLEXInstallFolder) { $PLEXInstallFolder = $(Get-ItemProperty -Path "HKLM:\Software\Plex, Inc.\Plex Media Server" `
			-Name InstallFolder  -ErrorAction Stop).InstallFolder }

	$PLEXServer = "Plex Media Server"
	# Presume that it is coincidental that the Registry Key and the PLEX server binary have the same name
	$PLEXServerBinary = "$PLEXInstallFolder\$PLEXServer.exe"

	If (-not $(Test-Path -Path "$PLEXServerBinary" -PathType Leaf))
	{ Throw [System.Management.Automation.PSArgumentException] "File not found: $PLEXServerBinary" }

	$CurrentPLEXCache = $(Get-ItemProperty -Path "HKCU:\Software\Plex, Inc.\Plex Media Server" `
			-Name TranscoderTempDirectory  -ErrorAction Stop).TranscoderTempDirectory

}
Catch [System.Management.Automation.ItemNotFoundException], [System.Management.Automation.PSArgumentException] {
	Write-Warning $_
	Write-Warning "Plex Media Server not properly initialized in this user account."
	Exit 911
}
Catch {
	Write-Warning $_ | Format-List * -Force | Out-String
	Exit 911
}

# --- Step 1: Privilege validation / elevation ---------------------------------------------------
#

#
# We can test under the default "Bypass" PowerShell execution policy (right click Execute with Powershell)
# We need to run under the Unrestricted execution policy to do any usefull work.
# Consult about_Execution_Policies: https://go.microsoft.com/fwlink/?LinkID=135170
#
$Policy = [String]$env:PSExecutionPolicyPreference
If ($Policy -eq "Bypass") {
 # Presume this is the initial invocation : recursive invocations do not inherit this policy.

	# Privilege Elevation Source Code: https://stackoverflow.com/questions/7690994/running-a-command-as-administrator-using-powershell

	# Get the ID and security principal of the current user account
	$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
	$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)

	# Get the security principal for the administrator role
	$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

	# Check to see if we are currently running as an administrator
	if ($myWindowsPrincipal.IsInRole($adminRole)) {
		# We are running as an administrator, so change the title and background colour to indicate this
		$Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + "(Elevated)"
		$Host.UI.RawUI.BackgroundColor = "DarkBlue"
		Clear-Host
	}
	else {
		# We are not running as an administrator, so relaunch as administrator

		# Create a new process object that starts PowerShell
		$newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"

		# Specify the current script path and name as a parameter with added scope and support for scripts with spaces in it's path
		$newProcess.Arguments = "& '" + $script:MyInvocation.MyCommand.Path + "'"

		# Indicate that the process should be elevated
		$newProcess.Verb = "runas"

		# Start the new process
		[System.Diagnostics.Process]::Start($newProcess)

		# Exit from the current, unelevated, process
		Exit
	}

	# Run your code that needs to be elevated here...

}

$Policy = [String] (Get-ExecutionPolicy -Scope LocalMachine)
If ($Policy -ne "Unrestricted") {
	Write-Host "PowerShell Execution Policy must be set to Unrestricted before executing this script."
	Write-Host ""
	Write-Host "Start Windows PowerShell in Administrator mode and issue the command 'Set-ExecutionPolicy Unrestricted'."
	Write-Host "See about_Execution_Policies at https://go.microsoft.com/fwlink/?LinkID=135170 for more information."
	Write-Host ""
	Write-Host "Do not forget to restore the execution policy to '$Policy' once done."
	Read-Host "Press ENTER to exit"
	Exit 911
}

# --- Step 2: Stop current instance of PLEX ---------------------------------------------------
#

Write-Host "$PLEXServer (re)start..."
if (-not [string]::IsNullOrWhiteSpace($CurrentPLEXCache)) { Write-Host "Current transcoder cache is $CurrentPLEXCache" }

# Stop running instaces of PLEX
#
Try {
	Get-Process -Name "$PLEXServer" -ErrorAction Stop | Stop-Process -PassThru | Wait-Process
	Write-Host "$PLEXServer is now stopped."
}
Catch {
	Write-Host "$PLEXServer is not running."
}

# --- Step 3: Setup the transcoder cache, start PLEX and exit to console ---------------------------------------------------
#

Try {
	# Note : { Test-Path -Path "$CacheDirectory" -IsValid } is useless here beause it returns false if the root
	#        partition does not exist, wich is the typical use case.
	$Cache = [System.IO.DirectoryInfo]$CacheDirectory
	If ( ($Cache.Root -imatch "[A-Z]:\\") `
			-and ([string]::IsNullOrWhiteSpace($Cache.Parent)) `
			-and -not ([string]::IsNullOrWhiteSpace($Cache.Name)) ) {
		# [Optional] Create a RAM cache
		#
		$MyDir = Split-Path -Parent $script:MyInvocation.MyCommand.Path
		If (Test-Path -Path "$MyDir\CreateCache.ps1" -PathType Leaf) {
			. "$MyDir\CreateCache.ps1"
			CreateCache -RAMDiskLabel $Cache.Name -RAMDiskSize $CacheSize -RAMDiskLetter $([String]$Cache.Root)[0]
		}
		else {
			Write-Warning "No RAM cache was (re)initialized for PLEX."
			Write-Warning "If this is required, script CreateCache.ps1 must be installed in $MyDir"
		}
	}

	# TranscoderTempDirectory
	Set-ItemProperty -Path "HKCU:\Software\Plex, Inc.\Plex Media Server" `
		-Name TranscoderTempDirectory  -Value "$CacheDirectory" -ErrorAction Stop

	# Start PLEX
	#
	Write-Host "Starting $PLEXServer."
	& $PLEXServerBinary

	# Query Remote Desktop Services sessions and extract this session conveniently marked with a marker (">")
	If ( $(qwinsta | Where-Object { $_.StartsWith(">") }) -match "^.*$env:UserName\s*([0-9]*).*$" ) {
		# Powershell extracts the entire line in $Matches[0] and extracts the session ID in $Matches[1]
		If ( ! $Matches[0].StartsWith(">console")) {
			# Switch this session to the server's console
			Read-Host "Press ENTER to exit to the server's console (this will disconnect your Remote Desktop Connection)"
			tscon $Matches[1] /Dest:console 
		}
		Write-Host ""
		Write-Host "You are logged on the server's console: do NOT disconnect the session otherwise PLEX will exit."
	}
	else { Write-Warning "Cannot find this desktop session!!!" }

	Read-Host "Press return to exit."
}
Catch {
	Write-Warning $_
	Pause
	Exit 911
}

