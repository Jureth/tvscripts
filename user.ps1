
function Get-NextEpisodes() {
    #It's yesterday in EST
    Execute-SqliteQuery `
        "SELECT e.*, s.title as Series  FROM episodes as e LEFT JOIN series as s ON e.seriesid = s.id WHERE CAST(strftime('%s', FirstAired) AS INTEGER) > @border" `
        @{border=(Get-UnixTime ([DateTime]::Now.AddDays(-1)))} `
    | Select-Object -Property `
        @{Name="Date"; Expression={ ([DateTime]$_.FirstAired).AddDays(1) } }, `
        Series, `
        @{Name="Episode"; Expression={ "S" + $_.SeasonNumber.ToString().PadLeft(2, '0') + "E" + $_.EpisodeNumber.ToString().PadLeft(2, '0')  } }, `
        title,`
        watched
}

function Get-NotWatched() {
    Execute-SqliteQuery `
        "SELECT e.*, s.title as Series  FROM episodes as e LEFT JOIN series as s ON e.seriesid = s.id WHERE watched<>1 AND CAST(strftime('%s', FirstAired) AS INTEGER) <= @border" `
        @{border=(Get-UnixTime ([DateTime]::Now.AddDays(-1)))} `
    | Select-Object -Property `
        seriesid,
        @{Name="Date"; Expression={ ([DateTime]$_.FirstAired).AddDays(1) } }, `
        Series,
        @{Name="Episode"; Expression={ "S" + $_.SeasonNumber.ToString().PadLeft(2, '0') + "E" + $_.EpisodeNumber.ToString().PadLeft(2, '0')  } }, `
        title
}

function Get-ShowEpisodes($title) {
    try {
        Get-TvShowEpisodes (Search-TvShow $title).id
    }catch {
    }
}
