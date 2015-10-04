#.Synopsis
# Creates a scheduled task to synch tvdb data with local storage
function Create-UpdateJob() {
    $script = {
        $api_key = Get-TvDbApiKey
        try {
            #avoid some stupid DateTime default parsing behavior
            $last = [DateTime]::ParseExact((Get-Settings "LastUpdate"), "dd/MM/yyyy HH:mm:ss", $null)
        }catch{
            $last = [DateTime]::MinValue
        }

        $diff = New-TimeSpan -Start $last
        if ($diff.TotalDays > 7) {
            #$file = "updates_all.xml" #it doesn't have episodes data
            Update-TvShowsAll
            Set-Settings "LastUpdate" ([DateTime]::Now)
            return
        } elseif ($diff.TotalDays > 7) {
            $file = "updates_month.xml"
        } elseif ($diff.TotalDays > 1) {
            $file = "updates_week.xml"
        } else {
            $file = "updates_day.xml"
        }

        [xml]$response = Download-TvDb "$api_key/updates/$file"
        if ($response.Data.Episode.Count -gt 0) {
            $response.Data.Episode | ForEach-Object {
                if((Test-Path tvdb:\Series\$_.Series) -eq $true) {
                    Store-TvDbEpisode (Get-TvDbEpisode $_.id).Data.Episode
                }
            }
            Set-Settings "LastUpdate" ([DateTime]::Now)
        }
    }

    Register-ScheduledJob `
        -Name UpdateEpisodes `
        -Trigger (New-JobTrigger -Once -At (Get-Date -Hour 11 -Minute 0 -Second 0 -Millisecond 0) -RepeatIndefinitely -RepetitionInterval (New-TimeSpan -Hours 12)) `
        -ScriptBlock $script `
        -ScheduledJobOption (New-ScheduledJobOption -WakeToRun -MultipleInstancePolicy StopExisting) `
        -InitializationScript ([scriptblock]::Create(". $PSScriptRoot\core.ps1")) #add some spaghetti to preresolve $PSScriptRoot variable
}

#.Synopsis
#Creates a scheduled task to download new episodes
function Create-DownloadJob() {
    $script = {
        Get-ChildItem tvdb:\Episodes -filter "watched<>1" | 
        Where-Object { $_.FirstAired -ne "" -and [DateTime]::Now.CompareTo(([DateTime]$_.FirstAired).AddDays(1)) -ge 0 } | 
        ForEach-Object { Download-Episode -Id $_.seriesid -Season $_.SeasonNumber -Episode $_.EpisodeNumber }
    }
    Register-ScheduledJob `
        -Name DownloadEpisodes `
        -Trigger (New-JobTrigger -Daily -At (Get-Date -Hour 13 -Minute 0 -Second 0 -Millisecond 0)) `
        -ScriptBlock $script `
        -ScheduledJobOption (New-ScheduledJobOption -WakeToRun -MultipleInstancePolicy Queue) `
        -InitializationScript ([scriptblock]::Create(". $PSScriptRoot\core.ps1"))
}
