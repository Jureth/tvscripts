Add-Type -Path "C:\Program Files\System.Data.SQLite\2013\bin\System.Data.SQLite.dll" | Out-Null

function Open-SqliteConnection($file) {
    #close the old one if exists
    if (Test-Path variable:script:connection) {
        Close-SqliteConnection
    }
    $Script:connection = New-Object -TypeName System.Data.SQLite.SQLiteConnection
    $Script:connection.ConnectionString = ("Data Source=" + $file)
    $Script:connection.Open()
    return $Script:connection
}

function Close-SqliteConnection($connection = $Script:connection) {
    $connection.Close()
}

function Execute-SqliteQuery($sql, $params = @{}, $connection = $Script:connection) {
    $command = $connection.CreateCommand()
    $command.CommandText = $sql
    $params.keys | ForEach-Object {
        [void]$command.Parameters.AddWithValue($_, $params.item($_))
    }
    $adapter = New-Object -TypeName System.Data.SQLite.SQLiteDataAdapter $command
    $data = New-Object System.Data.DataSet
    [void]$adapter.Fill($data)
    Write-Output $data.Tables.Rows

    $command.Dispose()
}


function Execute-SqliteCommand($sql, $params = @{}, $connection = $Script:connection) {
    $command = $connection.CreateCommand()
    $command.CommandText = $sql
    $params.keys | ForEach-Object {
        [void]$command.Parameters.AddWithValue($_, $params.item($_))
    }
    Write-Output $command.ExecuteNonQuery()

    $command.Dispose()
}

function New-SqliteRow() {
    param(
        [Parameter(Mandatory=$true, HelpMessage="Table name")]
        [String]$table,
        [Parameter(Mandatory=$false, HelpMessage="Data to insert", ValueFromPipeline=$true)]
        [Hashtable]$data=@{}
    )
    Process {
        $data.keys | ForEach-Object `
            -Begin {
                $columns = @()
                $valueRefs = @()
            } `
            -Process {
                $columns += $_
                $valueRefs += "@$_"
            }

        $sql = "INSERT INTO $table (" + ($columns -join ", ") + ") VALUES (" + ($valueRefs -join ", ") + ")"
        Execute-SqliteCommand $sql $data |Out-Null
    }
}

function Set-SqliteRow($table, $data, $filter) {

    $data.keys | ForEach-Object `
        -Begin {
            $columns = @()
        } `
        -Process {
            $columns += "$_=@$_"
        }

    $filter.keys | ForEach-Object `
        -Begin {
            $sqlFilters = @()
        } `
        -Process {
            #add some symbols to prevent overriding keys
            $sqlFilters += "$_=@_f_$_"
            $data."_f_$_" = $filter.item($_)
        }
    $sql = "UPDATE $table SET " + ($columns -join ", ") + " WHERE " + ($sqlFilters -join " AND ")
    Execute-SqliteCommand $sql $data |Out-Null
}