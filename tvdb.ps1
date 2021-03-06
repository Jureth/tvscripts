﻿#####################################################################
# TvDb Functions
#####################################################################

#.Synopsis
# Retreives tvdbapi key setting
Function Get-TvDbApiKey() {
    Get-Settings "TvDbApiKey"
}

#.Synopsis
#Update tvdbapi key setting
#.Parameter key
#New key value
Function Set-TvDbApiKey($key) {
    Set-Settings -name "TvDbApiKey" -Value $key
}

#.Synopsis
# Returns string response from given url
Function Download-TvDb($url){
    $client = Get-Webclient;
    $url = 'http://thetvdb.com/api/' + $url
    return $client.DownloadString($url)
}

#.Synopsis
# Searches TV series by title
function Search-TvDbSeries($title) {
    [xml]$response=Download-TvDb('GetSeries.php?seriesname=' + $title)
    if ($response.Data.GetType().Name -eq 'XmlElement') {
        $response.Data.Series;
    }else{
        Write-Warning 'No Result';
    }
}


#.Synopsis
# Retreives available languages from TvDb server
function Get-TvDbLanguages() {
    $api_key = Get-TvDbApiKey
    [xml]$response = Download-TvDb ($api_key + '/languages.xml')
    return $response.Languages.SelectNodes('Language')
}

#.Synopsis
#Adds series/show to the watchlist
Function Add-TvDbSeries() {
    param(
        [parameter(Mandatory=$true, ParameterSetName="ById", HelpMessage="IMDB id of the show")]
        [String]$Id, 
        [parameter(Mandatory=$true, ParameterSetName="ByTitle", HelpMessage="Title of the show")]
        [String]$Title
    )
    if ($Title -ne '') {
        $possibilities = Search-TvDbSeries $title
        if ($possibilities -eq $null) {
            Write-Warning 'TV Show not found'
            return
        }elseif($possibilities.GetType().IsArray -eq $true) {
            Write-Warning 'Multiple Definitions found. Use Id to add instead'
            return
        }else{
            $Id = $possibilities.id
        }
    }
    $data = Get-TvDbSeries -Id $Id  -WithEpisodes $true
    if ($data -ne $null) {
        #Store the show
        $data.Series `
        | Where-Object {
            (Test-TvShowExists $_.id) -eq $false
        } `
        | Select-Object `
            "id", `
            "status", `
            @{
                Name="title";
                Expression={ $_.SeriesName }
            }, `
            @{
                Name="watching";
                Expression={ $true }
            } `
        | New-SqliteRow "series" `
        | Out-Null

        #store episodes
        $data.Episode | Store-TvDbEpisode
    }
    
}

#.Synopsis
# Writes episode data to the database
Function Store-TvDbEpisode() {
    param(
        [parameter(Mandatory=$true, ValueFromPipeline=$true, HelpMessage="Episode object")]
        [PSCustomObject[]]
        $episode
    )
    Process {
        $data = @{
            id = $episode.id;
            seriesid = $episode.seriesid;
            SeasonNumber = $episode.SeasonNumber;
            title = $episode.EpisodeName;
            EpisodeNumber = $episode.EpisodeNumber;
            FirstAired = [string]$episode.FirstAired
        }
        if ((Test-TvShowEpisodeExists $episode.id) -eq $false) {
            $data.watched = $false
            New-SqliteRow "episodes" $data | Out-Null
        } else {
            Set-SqliteRow "episodes" $data @{id=$episode.id} |Out-Null
        }
    }
}

#.Synopsis
#Set watched flag for given episodes
function Set-Watched() {
    param(
        [parameter(Mandatory=$true, ParameterSetName="ById", HelpMessage="Imdb id of the series/TvShow")]
        [String]$Id,
        [parameter(Mandatory=$true, ParameterSetName="ByTitle", Position=0, HelpMessage="Title of the series/show")]
        [String]$Title,
        [parameter(Mandatory=$false, Position=1, HelpMessage="Season number. If not specified all seasons will be processed")]
        [int]$Season = -1,
        [parameter(Mandatory=$false, Position=2, HelpMessage="Episode number. If not specified all episodes will be processed")]
        [int]$Episode = -1,
        [parameter(Mandatory=$false, HelpMessage="Flag value. Default is TRUE")]
        [bool]$Value = $true
    )

    if ($Id -eq '') {
        $Id = (Search-TvShow $Title).id
    }
    if ($Id -eq '') {
        Write-Warning "Show not found"
        return
    }
    $filter = @{ seriesid =$Id }
    if ($Season -gt -1) {
        $filter.SeasonNumber = $Season
    }
    if ($Episode -gt -1) {
        $filter.EpisodeNumber = $Episode
    }
    Set-SqliteRow "episodes" @{ watched=$Value } $filter
}

#.Synopsis
# Retreives the TvDb entry (series, episode) from the server
#.Parameter EntryType
# Type of the entry. Can be "series", "episode" or "seriesWithEpisodes" to get both.
#.Parameter Id
# The TvDb Id of the entry to retreive. For getting series with episodes must be id of the series.
#.Parameter Language
# Language of the entry to retreive
function Get-TvDbEntry() {
    param(
        [parameter(Mandatory=$true, Position=0)]
        [ValidateSet("episode", "series", "seriesWithEpisodes")]
        [string]$EntryType,
        [parameter(Mandatory=$true, Position=1)]
        [int]$Id, 
        [parameter(Mandatory=$false, Position=2)]
        $Language = 'en'
    )
    $api_key = Get-TvDbApiKey
    switch ($EntryType) {
        'episode' { 
            $url = "http://thetvdb.com/api/$api_key/episodes/$id/$language.xml"
        }
        'series' {
            $url = "http://thetvdb.com/api/$api_key/series/$id/$language.xml"
        }
        'seriesWithEpisodes' {
            $url = "http://thetvdb.com/api/$api_key/series/$id/all/$language.zip"
            $extract = $true
        }
        default {
            Throw "Wrong Entry Type"
        }
            
    }

    try {
        $client = Get-Webclient
        $outfilename = [System.IO.Path]::GetTempFileName()
        try {
            $client.downloadFile($url, $outfilename)
            if ($extract -eq $true) {
                try {
                    Add-Type -assembly "system.io.compression.filesystem"
                    $zip = [io.compression.zipfile]::OpenRead($outfilename)
                    $xml= New-Object xml
                    $stream = $zip.GetEntry($language + '.xml').Open()
                    $xml.Load($stream);
                    Write-Output $xml.Data #result is here
                }catch [Exception] {
                    Write-Error $_.Exception.Message
                }finally{
                    $stream.Close()
                    $zip.Dispose()
                }
            }else{
                Write-Output ([xml](Get-Content $outfilename))
            }
        }catch [Exception] {
            Write-Error ("Attempt to load $url threw an exception " + $_.Exception.Message)
        }
        Remove-Item $outfilename
    }catch [Exception] {
        Write-Error $_.Exception.Message
    }
}

#.Synopsis 
# Retreives series information from the server
function Get-TvDbSeries($Id, $Language = 'en', $WithEpisodes = $false) {
    Get-TvDbEntry `
        -EntryType @{$true='seriesWithEpisodes'; $false='series'}[$WithEpisodes] `
        -Id $Id `
        -Language $Language
}

#.Synopsis
# Retreives episode information from the server
function Get-TvDbEpisode($Id, $Language = 'en') {
    Get-TvDbEntry -EntryType 'episode' -Id $Id -Language $Language
}

#.Synopsis
#Synchronizes local database with thetvdb.com database
function Update-TvDbSeries() {
    param(
        [parameter(Mandatory=$false, HelpMessage="Updates period")]
        [ValidateSet("day", "week", "month")]
        [String]
        $period = "month"
    )

    $api_key = Get-TvDbApiKey
    [xml]$response = Download-TvDb "$api_key/updates/updates_$period.xml"
    $response.Data.Episode `
    | ForEach-Object `
        -Begin {
            $count = $response.Data.Episode.Count
            $i=0
            if ($count -eq 0) {
                break
            }
        } `
        -Process {
            Write-Progress `
                -activity "Parsing Episodes" `
                -status "Complete $i from $count"  `
                -PercentComplete (($i / $count)  * 100);

            $i++;
            if((Test-TvShowExists $_.Series) -eq $true) {
                $episode = (Get-TvDbEpisode $_.id).Data.Episode
                Store-TvDbEpisode $episode
            }
        }
}

#.Synopsis
#Renews all shows/series in the local database
function Update-TvShowsAll() {
    Get-AllTvShows `
    | Update-TvShow
}

#.Synopsis
#Update the single show/series data
function Update-TvShow() {
    param(
        [parameter(Mandatory=$true, HelpMessage="TvShow Id", ValueFromPipelineByPropertyName=$true)]
        [int]$id
    )
    Process {
        $data = get-TvDbSeries -Id $id  -WithEpisodes $true
        if ($data -ne $null) {
            $data.Episode | ForEach-Object {
                $h = @{
                    id = $_.id;
                    seriesid = $_.seriesid;
                    SeasonNumber = $_.SeasonNumber;
                    title = $_.EpisodeName;
                    EpisodeNumber = $_.EpisodeNumber;
                    FirstAired = [string]$_.FirstAired
                }
                
                if ((Test-TvShowEpisodeExists $_.id) -eq $false) {
                    $h.watched = $false
                    New-SqliteRow "episodes" $h
                } else {
                    Set-SqliteRow "episodes" $h @{ id=$_.id}
                }
            }
        }
    }
}


#ORM functions 

function Get-TvShow($id) {
    Execute-SqliteQuery "SELECT * FROM series WHERE id = @id" @{'@id'=$id}
}

function Get-AllTvShows() {
    Execute-SqliteQuery "SELECT * FROM series"
}

function Get-Episode($id) {
    Execute-SqliteQuery "SELECT * FROM episodes WHERE id = @id" @{'@id'=$id}
}

function Get-TvShowEpisodes($id) {
    Execute-SqliteQuery "SELECT * FROM episodes WHERE seriesid = @id" @{'@id'=$id }
}


#.Synopsis
#Wrapper for searching a tvshow by title from the local database
#.Parameter title
#Title of the tvshow to search
function Search-TvShow($title) {
    return Execute-SqliteQuery "SELECT * FROM series WHERE title LIKE @title" @{'@title'=$title}
}

#.Synopsis
#Removes the tvshow and all episodes from the local database
function Remove-TvShow() {
    param(
        [parameter(Mandatory=$true, HelpMessage="Id of the tv show to remove")]
        [int]$Id
    )
    Execute-SqliteCommand "DELETE FROM episodes WHERE seriesid=@id" @{'@id'=$Id} | Out-Null
    Execute-SqliteCommand "DELETE FROM series WHERE id=@id" @{'@id'=$Id} | Out-Null
}

function Test-TvShowExists($id) {
    #Rows[0][0] - first column of the first row
    return 0 -lt (Execute-SqliteQuery "SELECT COUNT(*) FROM series WHERE id=@id" @{ id=$id })[0][0]
}

function Test-TvShowEpisodeExists($id) {
    return 0 -lt (Execute-SqliteQuery "SELECT COUNT(*) FROM episodes WHERE id=@id" @{ id=$id })[0][0]
}