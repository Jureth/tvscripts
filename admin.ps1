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
                if((Test-TvShowExists $_.Series) -eq $true) {
                    Store-TvDbEpisode (Get-TvDbEpisode $_.id).Data.Episode
                }
            }
            Set-Settings "LastUpdate" ([DateTime]::Now)
        }
    }

    Register-ScheduledJob `
        -Name UpdateEpisodes `
        -Trigger (
            New-JobTrigger `
                -Once `
                -At (Get-Date -Hour 11 -Minute 0 -Second 0 -Millisecond 0) `
                -RepeatIndefinitely `
                -RepetitionInterval (New-TimeSpan -Hours 12) `
            ) `
        -ScriptBlock $script `
        -ScheduledJobOption (New-ScheduledJobOption -WakeToRun -MultipleInstancePolicy StopExisting) `
        -InitializationScript ([scriptblock]::Create(". $PSScriptRoot\core.ps1")) #add some spaghetti to preresolve $PSScriptRoot variable
}

#.Synopsis
#Creates a scheduled task to download new episodes
function Create-DownloadJob() {
    $script = {
        Execute-SqliteCommand `
            "SELECT * FROM episodes WHERE watched<>1 AND CAST(strftime('%s', FirstAired) AS INTEGER) <= @border" `
            @{ border=(Get-UnixTime ([DateTime]::Now.AddDays(-1))) } `
        | Download-Episode
    }
    Register-ScheduledJob `
        -Name DownloadEpisodes `
        -Trigger (
            New-JobTrigger `
                -Daily `
                -At (Get-Date -Hour 13 -Minute 0 -Second 0 -Millisecond 0) `
            ) `
        -ScriptBlock $script `
        -ScheduledJobOption (New-ScheduledJobOption -WakeToRun -MultipleInstancePolicy Queue) `
        -InitializationScript ([scriptblock]::Create(". $PSScriptRoot\core.ps1"))
}


#.Synopsis
# Re-initialize database structure. Destroys all current data
Function New-TvDbStruct() {
    return
    #todo rewrite to sqlite create
    Get-TvDbDatabase
    New-Item tvdb:/Series `
        -id integer primary key `
        -title text `
        -status text `
        -watching boolean

    New-Item tvdb:/Episodes `
        -id integer primary key `
        -seriesid integer `
        -title text `
        -SeasonNumber integer `
        -EpisodeNumber integer `
        -FirstAired text `
        -watched boolean
}
