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

function Export-SqlServerJobs
{
    param(
    [ Microsoft.SqlServer.Management.SMO.Server]$srv
    ,
    [string]$outpath_job 
    
    )
    #Export-SqlServerJobsLog $srv $outpath_job 

    
    $jobs = $srv.JobServer.Jobs 
    $scripter = get-SqlServerScripter $srv 'definition'
    $scripterDrop = get-SqlServerScripter $srv 'drop'
    
    Write-SqlSmoObject    $jobs "$outpath_job\definition\"   $scripter $scripterDrop
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
    }
    Finally
    { 
        
        $conn.Close()
        $conn.Dispose()
    }
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
    
     $scripter    = Get-SqlServerScripter $srv 'definition'
     $scripterDrop = Get-SqlServerScripter $srv  'drop'
     
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
    $views          = $db.Views | Where-object $schemaFiltrator    
    $udfs           = $db.UserDefinedFunctions | Where-object $schemaFiltrator 
    $catlog         = $db.FullTextCatalogs 
    $udtts          = $db.UserDefinedTableTypes | Where-object $schemaFiltrator  
    
    # Output the scripts
    Write-SqlSmoObject $tbl $table_path $scripter $scripterDrop 
    Write-SqlSmoObject $storedProcs $storedProcs_path $scripter $scripterDrop  
    Write-SqlSmoObject $views $views_path $scripter  $scripterDrop 
    Write-SqlSmoObject $catlog $textCatalog_path $scripter $scripterDrop 
    Write-SqlSmoObject $udtts $udtts_path $scripter  $scripterDrop 
    Write-SqlSmoObject $udfs $udfs_path $scripter  $scripterDrop 
    
    $scripter 
}


function Export-SqlServerDataInserts
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
    
     $scripterData    = Get-SqlServerScripter $srv 'data'
     
    $insertData_output_path = "$output_path\$schema\inserts\"

    $tbl  = $db.tables | Where-object {$_.schema -eq $schema  -and -not $_.IsSystemObject  }
    
    Write-SqlSmoObject $tbl $insertData_output_path $scripterData  
    $scripter 
}



function Write-SqlSmoObject
{
[CmdletBinding()]
param(
[ValidateNotNull()]
$objects
, 
[ValidateNotNullOrEmpty()]
[string]
$outDir
, 
[ValidateNotNull()]
[Microsoft.SqlServer.Management.SMO.Scripter]
$scripter
, 
[Microsoft.SqlServer.Management.SMO.Scripter]
$scripterDrop = $null
) 


    if(Test-Path $outDir)
    {
        Remove-Item $outDir* -Force -Recurse 
    }
    
    if (-not (Test-Path $outDir)) {
        $cOutDir = [System.IO.Directory]::CreateDirectory($outDir) 
        Write-Host "Dir $cOutDir is creted"
    }

    foreach ($o in $objects) { 
        if ($o -ne $null) {
            try
            {
                $schemaPrefix = ""

                if ($o.Schema -ne $null -and $o.Schema -ne "") {
                    $schemaPrefix = $o.Schema + "."
                }

                $scripter.Options.FileName = $outDir + $schemaPrefix + $o.Name + ".sql"
                Write-Host "Writing " $scripter.Options.FileName
                
                
                if($scripterDrop -ne $null)
                {
                    $scripterDrop.Options.FileName = $scripter.Options.FileName 
                    $resultDrop = $scripterDrop.Script($o)
                }
                
                if($scripter.Options.ScriptData)
                {
                    $result = $scripter.EnumScript($o)
                }
                else
                {
                    $result = $scripter.Script($o) 
                } 
             }
             catch{
                $ErrorMessage = $_.Exception.Message
                $FailedItem = $_.Exception.ItemName
             }            
        }
    }
}

function Get-SqlServerScripter
{
    [CmdletBinding()]
    param(
    
    [Parameter(Position=1,Mandatory=$true)]
    [ValidateNotNull()]
    [Microsoft.SqlServer.Management.SMO.Server]
    $srv 
    ,
    
    [Parameter(Position=2,Mandatory=$false)]
    [ValidateSet('data','definition', 'drop', 'assemblies')]
    [string]
    $scripterType = 'definition')

    $scripter   = New-Object Microsoft.SqlServer.Management.SMO.Scripter($srv)
    #https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.scriptingoptions.aspx
    $scripter.Options.IncludeDatabaseContext = $false # 'use' on top
    $scripter.Options.WithDependencies       = $false #dep. all
    $scripter.Options.AllowSystemObjects = $False #system object
    $scripter.Options.IncludeHeaders   = $True  #date and time of generation.
    $scripter.Options.NoCommandTerminator = $false #GO seperator
    $scripter.Options.AppendToFile = $True #for multiple files
    $scripter.Options.ScriptSchema     = $true #use schema
    
    $scripter.Options.ToFileOnly            = $true  # only file
    $scripter.Options.AnsiFile              = $true
    $scripter.Options.SchemaQualify         = $true


    if($scripterType -eq 'data') 
    {
        $scripter.Options.ScriptSchema             = $false #use schema
        $scripter.Options.DriAll                   = $false
        $scripter.Options.ScriptData               = $True
        $scripter.Options.NoIdentities             = $true  
        $scripter.Options.IncludeHeaders           = $false
        $scripter.Options.DriIncludeSystemNames    = $false
                
    }
    elseif ($scripterType -eq 'drop') 
    {
        $scripter.Options.ScriptDrops        = $True  #drops
        $scripter.Options.IncludeIfNotExists = $True #check if exist

    }
    elseif($scripterType -eq 'assemblies')
    {
        $scripter.Options.NoAssemblies = $false
    }
    elseif( $scripterType  -eq 'Statistics')
    {
        $scripter.Options.Statistics  = $true
    }
    elseif($scripterType  -eq  'definition')
    {
        
        $scripter.Options.DriAll                = $true
        $scripter.Options.Indexes               = $True #indexes are included in the generated script.
        $scripter.Options.Indexes               = $true
        $scripter.Options.DriIndexes            = $true
        $scripter.Options.DriClustered          = $true
        $scripter.Options.DriNonClustered       = $true
        $scripter.Options.DriAllConstraints     = $true
        $scripter.Options.NonClusteredIndexes   = $true  # non-clustered indexes are included in the generated script.
        $scripter.Options.ClusteredIndexes      = $true
        $scripter.Options.FullTextIndexes       = $true
        
        $scripter.Options.EnforceScriptingOptions = $true
        $scripter.Options.Triggers              = $true
        $scripter.Options.Permissions           = $true
        #$scripter.Options.NoTablePartitioningSchemes  = $true
        $scripter.Options.SchemaQualifyForeignKeysReferences = $true    #schema-qualified table references for foreign key constraints are included in the generated script. 
        
    }



    return $scripter
}





function Backup-SqlServer
{
    param(
        [ValidateNotNullOrEmpty()]
        [string]
        $server         =  "localhost",
         [ValidateNotNullOrEmpty()]
        [string]
        $database       = "myDb",
        [ValidateNotNullOrEmpty()]
        [string]
        $output_path    = "C:\backup\db_schema_backup",
        [ValidateNotNullOrEmpty()]
        [string]
        $login          = "SqlServerUser",
        [ValidateNotNullOrEmpty()]
        [string]
        $password       = "123",
        [ValidateNotNullOrEmpty()]
        [string]
        $schema         = "dbo"
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
    
    Export-SqlServerLogs  $srv $output_path_db
    Export-SqlServerData $srv $output_path_db $database $schema
    
    Export-SqlServerJobs $srv "$output_path\jobs"
    Export-SqlServerDefinition  $srv $output_path_db  $schema
   
    Export-SqlServerDataInserts  $srv $output_path_db $schema
    #Export-SqlServerSMO @($db,$srv) @("database", "server", )
}
Finally {
    $srv.ConnectionContext.Disconnect()
}
}


Backup-SqlServer​
