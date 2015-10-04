#####################################################################
# TorrentApi Functions
#####################################################################

#.Synopsis
#Retreives TorrentApi token.
function get-TorrentApiToken($force = $false) {
    #TorrentApi token expires in 15 minutes. We get new one in 13 minutes just to be sure
    if ((Test-Path variable:script:TorrentApiTokenTime) -eq $false -or ((New-TimeSpan -Start $TorrentApiTokenTime -End (Get-Date)).TotalMinutes -gt 13) -or $force) {
        Set-Variable -Name TorrentApiTokenTime -Value (Get-Date) -Scope Script -Visibility Private
        $app_token = "JrthPrivDownloader" # Get-Settings "TorrentApiAppToken"
        $response = (Invoke-WebRequest "https://torrentapi.org/pubapi_v2.php?app_id=$app_token&get_token=get_token").Content
        $token = (ConvertFrom-Json $response).token
        if (Test-Path variable:script:TorrentApiToken) {
            Remove-Variable -Name TorrentApiToken -Scope script -Force
        }
        Set-Variable -Name TorrentApiToken -Value $token -Scope script -Option ReadOnly
    }
    return $TorrentApiToken
}

function Get-TorrentLinks($tvdbid, $season, $episode, $category=41) {
    # category==41 - Series HD
    # category==18 - Series

    $tapi = get-TorrentApiToken
    $episode_filter = "S" + $season.ToString().PadLeft(2, '0') + "E" + $episode.ToString().PadLeft(2, '0');#S00E00

    Start-Sleep -s 2 #the easiest way to avoid api speed limit
    $data = Invoke-RestMethod "https://torrentapi.org/pubapi_v2.php?mode=search&search_tvdb=$tvdbid&search_string=$episode_filter&category=$category&token=$tapi"
    if ($data.error_code -ne $null) {
        Write-Warning $data.error
        return @() #empty array instead of the stupid string
    }
    return $data.torrent_results
    
}

#.Synopsis
#Sent magnet urls to uTorrent via it's admin web-interface
function Out-uTorrent() {
    param(
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [String]$Magnet
    )
    Begin {
        #Gather uTorrent Web-Interface token
        $webHost = Get-Settings "uTorrentHost"
        $webUser = Get-Settings "uTorrentUser"
        $webPass = Get-Settings "uTorrentPass"
        $response = Invoke-WebRequest -Uri "http://$webHost/gui/token.html" -Headers @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($webUser+":"+$webPass ))} -SessionVariable "session"
        Remove-Variable 'webUser', 'webPass'
        if ($response.statusCode -eq 200) {
            $token = $response.ParsedHtml.getElementById("token").innerHtml
        }else {
            Write-Error "Gathering uTorrent token failed"
            $false
            break
        }
    }
    Process {
        try {
            (Invoke-WebRequest "http://$webHost/gui/?token=$token&action=add-url&s=$Magnet" -WebSession $session).StatusCode -eq 200
        }catch {
            $false
        }
    }
}

#.Synopsis
#Search and download episode
#.Parameter Id
#Tv Show id
#.Parameter season
#Season number
#.Parameter episode
#Episode number
function Download-Episode($Id, $season, $episode) {
    #we need an array even if there was no data or just one record
    $links = [array](Get-TorrentLinks $Id $season $episode)
    if ($links.count -ge 1) {
        $1080 = $links | Where-Object { $_.filename -like "*1080*" }
        if ($1080 -ne $null) {
            $result = Out-uTorrent $1080[0].download
        }else {
            $result = Out-uTorrent $links[0].download
        }
    }elseif($links.count -eq 0) {
        #try another one
        $links = Get-TorrentLinks $Id $season $episode 18 #not HD
        if ($links.count -gt 0) {
            $result = Out-uTorrent $links[0].download
        }else {
            Write-Warning "No data for show $Id season $season episode $episode was found"
        }
    }
    if ($result) {
        Set-Watched -Id $Id -Season $season -Episode $episode
    }
}
