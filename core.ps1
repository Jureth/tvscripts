#####################################################################
# Service Functions
#####################################################################

#.Synopsis
# Creates and configures a Webclient for accessing web resources
#.Parameter encoding
# Encoding to read web content.
Function Get-Webclient ($encoding = [System.Text.Encoding]::UTF8) {
    #$proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    #$proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials 
    
    $request = New-Object System.Net.WebCLient
    $request.UseDefaultCredentials = $true ## Proxy credentials only
    $request.encoding = $encoding
    $request.Proxy.Credentials = $request.Credentials
    return $request
}

#.Synopsis
# Returns path to configuration directory
Function Get-TvDbDataPath($suffix = '') {
    if ((Test-Path "$env:LOCALAPPDATA\tvParser") -eq $false) {
        New-Item "$env:LOCALAPPDATA\tvParser" -ItemType Directory
    }
    return "$env:LOCALAPPDATA\tvParser\$suffix"
}

Function Get-Settings($name) {
    if ((Test-Path "HKCU:\Software\Jureth\tvParser") -eq $false) {
        New-Item "HKCU:\Software\Jureth" -ItemType Directory
        New-Item "HKCU:\Software\Jureth\tvParser" -ItemType Directory
    }
    (Get-ItemProperty -Path "HKCU:\Software\Jureth\tvParser").$name
}

Function Set-Settings($name, $value) {
    if ((Test-Path "HKCU:\Software\Jureth\tvParser") -eq $false) {
        New-Item "HKCU:\Software\Jureth" -ItemType Directory
        New-Item "HKCU:\Software\Jureth\tvParser" -ItemType Directory
    }
    Set-ItemProperty -Path "HKCU:\Software\Jureth\tvParser" -Name $name -Value $value
}

#####################################################################
# Initialization
#####################################################################
. ($PSScriptRoot + "/tvdb.ps1")
. ($PSScriptRoot + "/torrentapi.ps1")
Get-TvDbDatabase
