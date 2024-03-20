
##******************************************************************
## Revision date: 2024.03.18
##
## This script installs a RAM disk .
##
##		2024.01.14: Create this test module following Windows Server
##					2022 January 2024 Cumulative update (don't ask...)
##
## Usage:
##	This script is invoked without any parameter
##	It will create a 4GB RAM cache on partition X if the script CreateCache
##	is found in the same directory.
##
## Copyright (c) 2024 PC-Évolution enr.
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
	[parameter( Mandatory = $false )] [string] $CacheDirectory = "X:\TestCache",
	[parameter( Mandatory = $false )] [UInt64] $CacheSize = 4GB
)

# Note : { Test-Path -Path "$CacheDirectory" -IsValid } is useless here beause it returns false if the root
#        partition does not exist, wich is the typical use case.
$Cache = [System.IO.DirectoryInfo]$CacheDirectory
If ( ($Cache.Root -imatch "[A-Z]:\\") `
		-and ([string]::IsNullOrWhiteSpace($Cache.Parent)) `
		-and -not ([string]::IsNullOrWhiteSpace($Cache.Name)) ) {
	$MyDir = Split-Path -Parent $script:MyInvocation.MyCommand.Path
	If (Test-Path -Path "$MyDir\CreateCache.ps1" -PathType Leaf) {
		. "$MyDir\CreateCache.ps1"
		CreateCache -RAMDiskLabel $Cache.Name -RAMDiskSize $CacheSize -RAMDiskLetter $([String]$Cache.Root)[0]
	}
}

Read-Host "Press return to exit."
