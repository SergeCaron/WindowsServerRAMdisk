##******************************************************************
## Revision date: 2024.05.13
##
## This script installs a RAM disk .
##
##		2023.04.03: Proof of concept / Initial release
##		2023.04.10:	Cleanup ;-)
##		2024.01.14: Multiple bugs found following Windows Server
##					2022 January 2024 Cumulative update (don't ask...)
##		2024.05.13:	iSCSI Virtual Disks are sometimes created OffLine
##
## Usage:
##	CreateCache [-RAMDiskLabel SomeLabel] [-RAMDiskSize Storage] -RAMDiskLetter SingleDriveLetter
##
##	Default Values are
##		-RAMDiskLabel Cache
##		-RAMDiskSize 4GB
##
## On completion, the RAMDiskLabel parameter is used to create a directory in the root of the newly created RAM disk.
## Using the defaults values above, this is P:\ServerSideCache
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

Function CreateCache {
	param (
		# Default parameter values
		[parameter( Mandatory = $false )] [string] $RAMDiskLabel = "Cache",
		[parameter( Mandatory = $false )] [UInt64] $RAMDiskSize = 1GB,
		[parameter( Mandatory = $true )] [string] $RAMDiskLetter
	)

	# --- Step 1: Very basic parameter validation---------------------------------------------------
	#
	Try {
		If ( [string]::IsNullOrWhiteSpace($RAMDiskLabel) -or ($RAMDiskLabel.Length -gt 32) )
		{ Throw "A valid disk label is required!" }

		If ( [string]::IsNullOrWhiteSpace($RAMDiskLetter) -or ($RAMDiskLetter.Length -gt 1) )
		{ Throw "A single drive letter is required!" }

		If ($RAMDiskSize -lt 1GB)
		{ Throw "The minimum disk size is 1GB!" }

		# Get the ID and security principal of the current user account
		$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
		$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)

		# Get the security principal for the administrator role
		$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

		# Check to see if we are currently running as an administrator
		if ($myWindowsPrincipal.IsInRole($adminRole)) {
			$iSCSIServer = Get-WindowsFeature -Name FS-iSCSITarget-Server
			If ($iSCSIServer.InstallState -ne "Installed")
			{ Throw "The iSCSI Target Server role must be installed to create a RAM disk" }
			# It seems that IPv4 APIPA is not supported by the iSCSI Target Server.
			# Error ISDSC_CONNECTION_FAILED (0xEFFF0003) occurs on (almost) all operations and
			# the server console cannot enumerate the local targets. So, use a DHCP server or a
			# static IP configuration for all NICs.
			$PortalEndPoints = (Get-IscsiTargetServerSetting).Portals | Where-Object { $_.Enabled -eq $False -and $_.IPEndpoint.AddressFamily -eq "InterNetwork" }
			If ($PortalEndPoints.Count -gt 0)
			{ Throw "The iSCSI Target Server is not enabled on an active network interface: this will interfere with its operation. APIPA is not supported by the iSCSI Target Server." }
		}
		else { Throw "Administrator privileges are required to create a RAM disk" }
	}
	Catch {
		# Any and all terminating errors ...
		Write-Warning $_
		Pause
		Exit 911
	}

	# --- Step 2: Prepare the target on the local server--------------------------------------------
	#

	Write-Host "Preparing target $RAMDiskLabel ..."

	# Allow local traffic
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\iSCSI Target' -Name AllowLoopBack -Value 1

	# Make sure the target name is all lowercase, otherwise it is reported as invisible (by some ...).
	$RAMDiskLabel = $RAMDiskLabel.ToLower()

	# Create the iSCSI target (if required)
	Try {
		$ServerSideCache = Get-IscsiServerTarget -TargetName $RAMDiskLabel -ErrorAction Stop
	}
	Catch {
		# Assign the iSCSI Quaslified Name (IQN) of this initiator to this target.
		# This is typically
		#   $IQN = ("iqn.1991-05.com.microsoft" + ":" + $env:ComputerName + "." + $env:UserDNSDomain).ToLower()
		# This restricts initiators to this machine (!) without tying the target to a specific IP or MAC address.
		$ServerSideCache = New-IscsiServerTarget -TargetName $RAMDiskLabel -InitiatorIds @("IQN:$( (Get-InitiatorPort).NodeAddress )")
	}

	# Enable the target (Just in case ...)
	$ServerSideCache = $ServerSideCache | Set-IscsiServerTarget -Enable $True -PassThru

	# Create a Virtual RAM Disk if this was not done since the last service restart
	# Note: the target exists independently from the VHD
	$VHD = "ramdisk:$RAMDiskLabel.vhdx"
	Try {
		$ThisVHD = Get-IscsiVirtualDisk -Path $VHD -ErrorAction Stop
		If ($ThisVHD.Size -ne $RAMDiskSize) {
			# Note: the VHD may hold multiple partitions and may be in use!
			# Also: at this point, no error should occur, error handling is set to "Inquire" for debugging purposes only.
			Write-Warning "Cache size change: current cached contents will be destroyed!"
			If ($ServerSideCache.LunMappings.Count -ne 0) {
				Remove-IscsiVirtualDiskTargetMapping -TargetName $ServerSideCache.LunMappings.TargetName -Path $VHD -ErrorAction Inquire
				# LunMappings is a read-only structure and we need to reset our pointer
				$ServerSideCache = Get-IscsiServerTarget -TargetName $RAMDiskLabel -ErrorAction Inquire 
			}
			Remove-IscsiVirtualDisk -Path $VHD -ErrorAction Inquire
			$ThisVHD = New-IscsiVirtualDisk -Path $VHD -Size $RAMDiskSize -ErrorAction Inquire
		}
	}
	Catch {
		$ThisVHD = New-IscsiVirtualDisk -Path $VHD -Size $RAMDiskSize
	}

	# Map the Virtual RAM Disk to the target
	If ( $ServerSideCache.LunMappings.Count -eq 0) {
		Add-IscsiVirtualDiskTargetMapping -TargetName $RAMDiskLabel -DevicePath $VHD
		# At this point, no error should occur, error handling is set to "Inquire" for debugging purposes only.
		$ServerSideCache = Get-IscsiServerTarget -TargetName $RAMDiskLabel -ErrorAction Inquire
	}

	# Assign the iSCSI Quaslified Name (IQN) for this target on this server.
	# This is typically
	#   $IQN = ("iqn.1991-05.com.microsoft" + ":" + $env:ComputerName + "-" + "$RAMDiskLabel" + "-" + "target").ToLower()
	$IQN = $ServerSideCache.TargetIQN

	# Enumerate the local targets : this needs to be done BEFORE you can get at any target on this portal.
	Try {
		$Portal = Get-IscsiTargetPortal -TargetPortalAddress $env:ComputerName -ErrorAction Stop
		# | Update-IscsiTargetPortal -PassThru
	}
	Catch {
		$Portal = New-IscsiTargetPortal -TargetPortalAddress $env:ComputerName -ErrorAction SilentlyContinue
	}
	Finally {
		# This system can be multi-homed / multi protocol : obtain an IP that will allow a connection.
		$PortalEndPoints = (Get-IscsiTargetServerSetting).Portals | Where-Object { $_.Enabled -eq $True -and $_.IPEndpoint.Port -eq $Portal.TargetPortalPortNumber }

		If ($PortalEndPoints.Count -gt 0) {
			# Update the IP and the list of targets
			$Portal = $Portal | Update-IscsiTargetPortal -PassThru
		}
		else {
			Write-Warning "Unabe to connect to myself! Aborting ..."
			Exit 911
		}
	}

	# Connect the client side (Initiator) to the server side (Target) to expose a disk object
	Try {
		$ThisTarget = Connect-IscsiTarget -NodeAddress $IQN -TargetPortalAddress $Portal.TargetPortalAddress -TargetPortalPortNumber $Portal.TargetPortalPortNumber -IsPersistent $False -ErrorAction Stop
	}
	Catch {
		$ThisTarget = Get-IscsiTarget -NodeAddress $IQN -ErrorAction Stop
	}

	# --- Step 3: Prepare the initiator-------------------------------------------------------------
	#

	# Get the Windows Disk Object : there seems to be no way to get the exact disk that was just connected (?!)
	# Get the serial number from the server side
	$ThisDisk = Get-IscsiVirtualDisk -Path $VHD
	# Find the disk object on the client side ( Technically, there can be only one ... but nothing gets formatted yet.)
	$Cache = Get-Disk | Where-Object { ($_.SerialNumber -eq $ThisDisk.SerialNumber) }

	Try {
		# Allow an existing drive letter already assigned to this RAM disk
		If ($Cache.Path -eq $( Get-Disk -Number $((Get-Partition -DriveLetter $RAMDiskLetter -ErrorAction Stop ).DiskNumber) ).Path) {
			Write-Warning "The disk containing partition $RAMDiskLetter will be reformated.: current cached contents will be destroyed!"
			$Cache = $Cache | Clear-Disk -RemoveData -RemoveOEM -PassThru -Confirm:$false -ErrorAction Stop
		}
		else { Throw "Drive letter $RAMDiskLetter is already asigned to another partition." }
	}
	Catch [ Microsoft.PowerShell.Cmdletization.Cim.CimJobException ] {
		Write-Host "The letter $RAMDiskLetter will be assigned to the cache."
	}
	Catch {
		# Any and all terminating errors ...
		Write-Warning $_
		Exit 911
	}

	# --- Step 4: Initialize the disk and format a partition----------------------------------------
	#
	Try {
		If ($Cache -ne $Null) {
			If ($Cache.Count -eq $Null) {
				# Make sure we are clubbering the right thing
				# Note that the PartitionStyle is either RAW if this is a "new" disk or GPT if it was initialized here previously.
				If (($ThisDisk.SerialNumber -eq $Cache.SerialNumber) -and ($Cache.BusType -eq "iSCSI") `
						-and (($Cache.PartitionStyle -eq "RAW") -or ($Cache.PartitionStyle -eq "GPT")) ) {
					# There is exactly one disk object with these attributes.
					Try {
						# The disk may be presented with the "Offline" status: clear this indicator
						$Cache | Set-Disk -IsOffline $False | Out-Null
						# Initialize and format the drive.
						$Cache = $Cache | Initialize-Disk -PartitionStyle GPT -PassThru -ErrorAction Stop `
						| New-Partition -UseMaximumSize -ErrorAction Stop
						$Cache | Format-Volume -FileSystem NTFS -NewFileSystemLabel "$RAMDiskLabel" -Confirm:$false -ErrorAction Stop | Out-Null
						$Cache | Set-Partition -NewDriveLetter $RAMDiskLetter
                                        
						# Create a root folder in this drive
						$ThisRoot = New-Item -Path $("$RAMDiskLetter" + ":\" + "$RAMDiskLabel") -ItemType Directory -ErrorAction SilentlyContinue
					}
					Catch {
						Write-Warning $_
						Write-Warning "Error initializing cache: review the disk configuration." 
					}

				}
				else {
					# Back out before things get real ugly ...
					Throw "Serial number mismatch!"
				}
			}
			else { Throw "Too many raw iSCSI disks found on this system!" }
		}
		else { Write-Warning "-> No iSCSI cache added to this system!" }
	}
	Catch {
		# Any and all terminating errors ...
		Write-Warning $_
		Write-Warning "-> Removing the new virtual disk and backing out!"
		Remove-IscsiVirtualDiskTargetMapping -TargetName $RAMDiskLabel -Path $VHD
		Remove-IscsiServerTarget -TargetName $RAMDiskLabel
		Remove-IscsiVirtualDisk -Path $VHD
		Exit 911
	}

	Write-Host "Done!"
}

