
function Get-NextEpisodes() {
    Get-ChildItem tvdb:\Episodes |
    #We add 1 day to FirstAired because of the 12 and more hours difference between OMST and US time zones
    Where-Object { try {[DateTime]::Now.CompareTo(([DateTime]$_.FirstAired).AddDays(1)) -lt 0} catch { $false }  } |
    Select-Object -Property `
        @{Name="Date"; Expression={ ([DateTime]$_.FirstAired).AddDays(1) } }, `
        @{Name="Series"; Expression={ (Get-Item ("tvdb:\Series\" + $_.seriesid)).title } }, `
        @{Name="Episode"; Expression={ "S" + $_.SeasonNumber.ToString().PadLeft(2, '0') + "E" + $_.EpisodeNumber.ToString().PadLeft(2, '0')  } }, `
        title,`
        watched
}

function Get-NotWatched() {
    Get-ChildItem tvdb:\Episodes -filter "watched<>1" |
    Where-Object { try {[DateTime]::Now.CompareTo(([DateTime]$_.FirstAired).AddDays(1)) -ge 0} catch { $false } } |
    Select-Object -Property `
        seriesid,
        @{Name="Date"; Expression={ ([DateTime]$_.FirstAired).AddDays(1) } }, `
        @{Name="Series"; Expression={ (Get-Item ("tvdb:\Series\" + $_.seriesid)).title } }, `
        @{Name="Episode"; Expression={ "S" + $_.SeasonNumber.ToString().PadLeft(2, '0') + "E" + $_.EpisodeNumber.ToString().PadLeft(2, '0')  } }, `
        title
}

function Get-ShowEpisodes($title, $additionalFilter = "") {
    try {
        Get-ChildItem tvdb:\Episodes -filter ("seriesid=" + ((Search-TvShow $title).id) + $additionalFilter)
    }catch {
    }
}
