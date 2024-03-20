# Setup a RAM disk cache on Windows Server
 Setup a RAM disk cache on Windows Server.
 
This function creates a virtual disk in RAM using the iSCSI Target Server role on Microsoft Windows Server.

Usage:
 	CreateCache [-RAMDiskLabel SomeLabel] [-RAMDiskSize Storage] -RAMDiskLetter SingleDriveLetter

Parameter "RAMDiskLetter" is mandatory and the default values are:
-	-RAMDiskLabel Cache
-	-RAMDiskSize 4GB

This function is designed to be integratedd in some other script. Two sample scripts are provided below.

------
>**Caution:**	This script requires **elevated** execution privileges.

Quoting from Microsoft's "about_Execution_Policies" : "PowerShell's
execution policy is a safety feature that controls the conditions
under which PowerShell loads configuration files and runs scripts."

In order to execute this script using a right-click "Run with PowerShell",
the user's session must be able to run unsigned scripts and perform
privilege elevation. Use any configuration that is the equivalent of the
following commnand executed from an elevated PowerShell prompt:

			Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted
------
# Samples

## Simple create cache script

This sample script create a default 4GB drive X:. These defaults can be overriden using the -CacheDirectory and -CacheSize parameters.

The script presumes the "CreateCache" function is located in the same directory.

Thereis no support for privilege elevation and the script must run from an elevated terminal

## Plex Server Start/ReStart

This sample script will inspect a local Plex Media Server and will configure a RAM cache for transcoding videos.

The script supports privilege elevation and can run using a right-click "Run with PowerShell".

This sample script create a default 4GB drive P: labelled "PlexCache". These defaults can be overriden using the -CacheDirectory and -CacheSize parameters.

Despite its name, Plex Server is an application, not a Windows service: by design, this script presume that it is running in a RDP session and will exit to the physical console. It is up to the user to properly configure the account under which Plex Server is running. Presumably, some other account(s) is/are used to connect to the server and run other tasks without disabling Plex Server.

NOTE: Plex Server configuration data is read from the registry key **HKCU:\Software\Plex, Inc.\Plex Media Server**. This script must run under the same user account as the Plex Server.




