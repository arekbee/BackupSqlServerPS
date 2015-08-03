function Init-SqlServerSMO
{
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") 
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") 
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended")  
    [System.Reflection.Assembly]::LoadWithPartialName("System.Data")  
}

function CheckInit-SqlServerSMO
{
    
    $smlAss = [appdomain]::currentdomain.getassemblies() | ? {$_.FullName.ToLower().Contains("Microsoft.SqlServer.SMO".ToLower())}
    if($smlAss -eq $null)
    {
         Write-host "It will inint sql Server SMO"
         Init-SqlServerSMO | out-null
    }
}


function Export-SqlServerLogs
{
    param(
    [Microsoft.SqlServer.Management.Smo.Server]$server,
    [string]$output_path,
    [string]$delimiter =','
    
    )
    
    $log_output_path = "$output_path\Logs\Error_log.csv"
    if(Test-path $log_output_path)
    {
        Remove-Item -Path $log_output_path | Out-Null
    }else
    {
        New-Item -Path $log_output_path -ItemType file -force   | Out-Null
    }
    
    $server.ReadErrorLog() | ConvertTo-Csv -Delimiter $delimiter  -notypeinformation | Out-File  -filepath $log_output_path -encoding ASCII -Force
    
    Write-Host "Path to log file is $log_output_path"
   
}


Function Export-SqlServerJobsLog
{
     param(
        [ Microsoft.SqlServer.Management.SMO.Server]$srv
        ,
        [string]$outpath
        , 
        [string]$Delimiter = ','
        )
   
        $outpath_log = "$outpath\SQLAGENT.csv"
        if( -not( test-path $outpath_log))
        {
            new-item -type file -force -path $outpath_log
        }
        
        $srv.JobServer.ReadErrorLog() | Export-Csv -Path $outpath_log  -NoTypeInformation -Force -Delimiter $Delimiter 
        
        Write-Host "Path to job log file is $log_output_path"
}

function In-Quotes(
    [array]$arr    
    ,
    [string]$delimiter =','
    )
{
    [string]$inner = $arr -join ('"' + $delimiter + '"')
    [string]$outer = '"' + $inner + '"'
    return $outer
}



function Export-SqlServerData 
{
    param(
    [ Microsoft.SqlServer.Management.SMO.Server]$srv
    ,
    [string]$output
    ,
    [string]$database
    ,
    [string]$schema = "dbo"
    ,
    [string]$delimiter =','
    )
    
    $output_path = "$output\Data\"
    
    
    if( -not  (Test-path $output_path  ))
    {
        New-Item -type directory -path  $output_path | out-null
    }
    
    
    $db         = New-Object ("Microsoft.SqlServer.Management.SMO.Database")
    $db         = $srv.Databases[$database]
    $tables = $db.tables | Where-object {$_.schema -eq $schema  -and  -not $_.IsSystemObject } 

    try
    {
        $conn = New-Object 'System.Data.SqlClient.SqlConnection' -ArgumentList ($srv.ConnectionContext.ConnectionString)
        $cmd = New-Object System.Data.SqlClient.SqlCommand
        $cmd.Connection = $conn
        $conn.Open()
        $tables | %{
            $table = $_
            [string]$tableName =$database + "." + $table.Schema + "." + $table.Name 
            $cmd.CommandText = "SELECT * FROM $tableName"
            $cmd.CommandTimeout = 10000
            try
            {
                [System.Data.SqlClient.SqlDataReader]$reader = $cmd.ExecuteReader()
                if($reader)
                {
                    [array]$headers = @()
                    for ($i =0; $i -lt $reader.FieldCount; $i++)
                    {
                        $headers += $reader.GetName($i)
                    }
                    
                    $fileName = "$output_path\$tableName.csv"
                    WRITE-HOST "Writing data to file $fileName"
                    
                    $sw = New-Object System.IO.StreamWriter  $fileName 
                    try
                    {
                        $str = In-Quotes -arr $headers -d $delimiter
                        $sw.WriteLine($str   )
                        
                        while ($reader.Read())
                        {
                            [array]$row = @()
                            for ($i = 0; $i -lt  $reader.FieldCount; $i++)
                            {
                                $row += $reader[$i]
                            }
                            $str = In-Quotes -arr $row -d $delimiter
                            $sw.WriteLine($str  )
                        }
                    }
                    Finally
                    { 
                            $sw.Close()
                            $sw.Dispose()
                    }
                }
            }
            Finally
            { 
                $reader.Dispose()
            }
        
        }
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $adapter.SelectCommand = $cmd
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataset)
    }
    Finally
    { 
        
        $conn.Close()
        $conn.Dispose()
    }
}







function CopyObjectsToFiles($objects, $outDir, [Microsoft.SqlServer.Management.SMO.Scripter]$scripter) {
    #clear out before 

    if(Test-Path $outDir)
    {
        Remove-Item $outDir* -Force -Recurse 
    }
    
    #if (-not (Test-Path $outDir)) {
        [System.IO.Directory]::CreateDirectory($outDir) 
    #}
   

    foreach ($o in $objects) { 

        if ($o -ne $null) {
            $schemaPrefix = ""

            if ($o.Schema -ne $null -and $o.Schema -ne "") {
                $schemaPrefix = $o.Schema + "."
            }

            #removed the next line so I can use the filename to drop the stored proc 
            #on the destination and recreate it
            $scripter.Options.FileName = $outDir + $schemaPrefix + $o.Name + ".sql"
            #$scripter.Options.FileName = $outDir + $schemaPrefix + $o.Name
            Write-Host "Writing " $scripter.Options.FileName
            
            if($scripter.Options.ScriptData)
            {
                $result = $scripter.EnumScript($o)
            }
            else
            {
                $result = $scripter.Script($o) 
            }          
        }
    }
}

function Get-SqlServerScripter
{
    param([Microsoft.SqlServer.Management.SMO.Server]$srv)

    $scripter   = New-Object Microsoft.SqlServer.Management.SMO.Scripter($srv)
    #region scripter
    # Set scripter options to ensure only data is scripted
    #$scripter.Options.ScriptSchema     = $true
    $scripter.Options.ScriptData       = $True
    #$scripter.Options.ScriptDrops      = $True
    #$scripter.Options.IncludeHeaders   = $True
    $scripter.Options.WithDependencies  = $true
    $scripter.Options.IncludeDatabaseContext = $true
    $scripter.Options.NoCommandTerminator = $true


    #Exclude GOs after every line
    #$scripter.Options.NoCommandTerminator   = $false
    #$scripter.Options.ToFileOnly            = $true
    #$scripter.Options.AllowSystemObjects    = $false
    #$scripter.Options.Permissions           = $true
    #$scripter.Options.DriAllConstraints     = $true
    #$scripter.Options.SchemaQualify         = $true
    #$scripter.Options.AnsiFile              = $true

    #$scripter.Options.SchemaQualifyForeignKeysReferences = $true

    #$scripter.Options.Indexes               = $true
    #$scripter.Options.DriIndexes            = $true
    #$scripter.Options.DriClustered          = $true
    #$scripter.Options.DriNonClustered       = $true
    #$scripter.Options.NonClusteredIndexes   = $true
    #$scripter.Options.ClusteredIndexes      = $true
    #$scripter.Options.FullTextIndexes       = $true
    #$scripter.Options.ToFileOnly            =$true


    #$scripter.Options.EnforceScriptingOptions   = $true
    #endregion scripter

    return $scripter
}

function Export-SqlServerDefinition
{
    param(
        [Microsoft.SqlServer.Management.SMO.Server]$srv,
        [string]$output_path,
        #[Microsoft.SqlServer.Management.SMO.Database]$db,
        [string]$schema         = "dbo"
    )
    
    $db         = New-Object ("Microsoft.SqlServer.Management.SMO.Database")
    $tbl        = New-Object ("Microsoft.SqlServer.Management.SMO.Table")
    $db         = $srv.Databases[$database]
    
     $scripter    = Get-SqlServerScripter $srv
     
    [ScriptBlock]$schemaFiltrator = { $_.schema -eq $schema  -and -not $_.IsSystemObject }

    $output_path_schema = "$output_path\$schema"

    $table_path         = "$output_path_schema\table\"
    $storedProcs_path   = "$output_path_schema\stp\"
    $views_path         = "$output_path_schema\view\"
    $udfs_path          = "$output_path_schema\udf\"
    $textCatalog_path   = "$output_path_schema\fulltextcat\"
    $udtts_path         = "$output_path_schema\udtt\"
    
    
    $tbl            = $db.tables | Where-object $schemaFiltrator 
    $storedProcs    = $db.StoredProcedures | Where-object $schemaFiltrator  
    $views          = $db.Views | Where-object { $_.schema -eq $schema }  #checkit 
    $udfs           = $db.UserDefinedFunctions | Where-object $schemaFiltrator 
    $catlog         = $db.FullTextCatalogs
    $udtts          = $db.UserDefinedTableTypes | Where-object $schemaFiltrator  
    
    # Output the scripts
    CopyObjectsToFiles $tbl $table_path $scripter 
    CopyObjectsToFiles $storedProcs $storedProcs_path $scripter 
    CopyObjectsToFiles $views $views_path $scripter 
    CopyObjectsToFiles $catlog $textCatalog_path $scripter 
    CopyObjectsToFiles $udtts $udtts_path $scripter 
    CopyObjectsToFiles $udfs $udfs_path $scripter 
    
    $scripter 
}





function Export-SqlServerJobs
{
    param(
    [ Microsoft.SqlServer.Management.SMO.Server]$srv
    ,
    [string]$outpath_job 
    
    )
    #Export-SqlServerJobsLog $srv $outpath_job 

    
    $jobs = $srv.JobServer.Jobs | select -first 1
    $scripter = get-SqlServerScripter $srv
    CopyObjectsToFiles    $jobs "$outpath_job\definition\"   $scripter
}




function Backup-SqlServer
{
    param(
        [string]$server         = "localhost",
        [string]$database       = "myDb",
        [string]$output_path    = "C:\backup\db_schema_backup",
        [string]$login          = "SqlServerUser",
        [string]$password       = "123",
        [string]$schema         = "dbo"
    )

CheckInit-SqlServerSMO

Try {
    $srvConn = new-object Microsoft.SqlServer.Management.Common.ServerConnection
    $srvConn.ServerInstance = $server
    $srvConn.LoginSecure = $false
    $srvConn.Login = $login
    $srvConn.Password = $password

    $srv        = New-Object Microsoft.SqlServer.Management.SMO.Server($srvConn)




    $output_path_db = "$output_path\$database"

    
    #Export-SqlServerLogs  $srv $output_path_db
    #Export-SqlServerData $srv $output_path_db $database $schema
    #Export-SqlServerDataInserts 
    Export-SqlServerJobs $srv "$output_path\jobs"
    #Export-SqlServerDefinition  $srv $output_path_db  $schema
    
}
Finally {
    #$srv.ConnectionContext.Disconnect()
}

#Export-SqlServerSMO @($db,$srv) @("database", "server", )
}


Backup-SqlServer​
