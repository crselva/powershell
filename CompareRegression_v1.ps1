# script path is generated based on the location where the script is placed
# both input files must be placed in the same path as the script
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

#region UTILITIES

#To prompt and store credentials to access Unix
function capture_credentials{

    $Credentials = Get-Credential

    $Global:username = $Credentials.UserName

    $Global:password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credentials.Password))

}

#Function to execute command in Unix and return data
function getFromUnix($param1, $param2)

{

    $Global:serverName = 'xxxxxx'

    $plinkPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

    #Construct the command based on parameters recieved
    $Command = $param1 + " " + $param2

    Write-Host 'Command: ' $Command

    #Execute SSH Command
    $Global:CommandOutput =(echo y | &($scriptPath + '\PLINK.EXE') -pw $password $username@$serverName $command)

    if($param1 -eq 'ls -ltr') {

        $commandOutput += $Error[0].ToString()

    }

    return $commandOutput

}


filter Convert-DateTimeFormat { param($OutputFormat = 'yyyy-MM-dd')

    try{

        ([DateTime]$_).ToString($OutputFormat)

    }
    catch{ }

}
#endregion UTILITIES

#region FUNCTIONS

#Functions to create HTML file
function createHTMLFile($dataTable, $outFilePath ,$outFileName) {

    $dataTable | Format-Table

    #HTML Output table - Timestamp
    $reportCreationTime = " Report created: " + (Get-Date)

    #HTML table component
    $html = $dataTable | ConvertTo-Html -As Table -Title 'dataTable' -PreContent "Executed by $env:username" -PostContent $reportCreationTime

    #attribute to adjust the HTML Table border
    $html = $html -replace '<table>' , '<table border=1>'

    #To remove the issue with Convertto-HTML cmdlet changing link structure
    $html  = $html -replace '&lt;', '<'; $html = $html -replace '&quot;' , '"'; $html = $html -replace '&gt;', '>'

    #name for the HTML file
    $outFile = $outFilePath + '\' + $outFileName+ '.html'

    #save the HTML file
    $html | Out-File $outFile

    #To open the HTML file : Invoke-Item $outFile

}

#Primary function used here
function captureMismatch ($file1, $file2)
{

    #extract headers from the csv files
    $headers1 = $file1[0].psobject.Properties.Name

    $headers1 = $file2[0].psobject.Properties.Name

    #Array to store compare failed record/fields
    $fieldsMismatch = @()

    #Check number of Records and header between both files and record type
    if(($file1.Length -eq $file2.Length) -and ($headers1.ToString() -eq $headers2.ToString()) -and ($headers1[0] -eq $headers2[0])){

        #Variable to capture number of compare failures for curret record type
        $failedLine = 0

        for($i=0; $i -lt $file1.length; $i++){

            #Check each line matches between 2 files
            if($file1[$i] -eq $file2[$i]){

            #Success record - no updates required

            }
            else{

                #compare failed for the line -add count-
                $failedLine+=1

                #compare line failed- identify fields failing compare
                for($j=0 ; $j -lt $headers1.Length ; $j++){

                    if($file1[$i].($headers1[$j].ToString()) -eq $file2[$i].($headers2[$j].ToString())){
                        <#Field matches - no need to add error#>
                    }
                    elseif($headers1[$j] -notmatch 'Run Time'){

                        #field mismatch - create a error row
                        $failRow = [PSCustomObject]@{
                            RecordType = $headers1[0]
                            $headers1[1] = $file1[$i].($headers1[1].ToString())
                            $headers1[2] = $file1[$i].($headers1[2].ToString())
                            $headers1[3] = $file1[$i].($headers1[3].ToString())
                            Mismatch_header = $headers1[$j]
                            Test_File_Value = $file1[$i].($headers1[$j].ToString())
                            Prod_File_Value = $file2[$i].($headers2[$j].ToString())
                        }

                        $fieldsMismatch+= $failRow

                    }           

                }

            }

        }

    }

    Elseif($headers1[0] -ne $headers2[0]){

        <#Place Holder to update mismatch between record type#>

    } 

    Elseif($file1.Length -ne $file2.Length){

        <#Place Holder to update mismatch between record count#>

    }

    Elseif($headers1.ToString() -ne $headers2.ToString()){

        <#Place Holder to update mismatch headers between files#>
        Write-Host 'Headers not equal'

    }

    if($fieldsMismatch.length -gt 0){

        createHTMLFile -dataTable $fieldsMismatch -outFilePath $htmlPath -outFileName $headers1[0]

        $linesMismatched = [PSCustomObject]@{
            RecordType = $headers1[0]
            NumberOfFieldMismatches = $fieldsMismatch.length
            LinkToResult  = '<a href = " '+ $htmlPath +'\'+ $headers1[0]+'.html">Click here</a>'
        }

        $Global:linesMismatchTable+= $linesMismatched

    }

}

#endregion FUNCTIONS

#region script flow - sequence of steps

#call function to prompt for credentials for accessing unix
if(($username -eq $null) -or ($password -eq $null)){
    capture_credentials
}

#Class - Dashboard result table #not used as of now
class dashboard_row{ [string]$recordType; [int]$record_in_testFile; [int]$record_in_prodFile; [string]$status }

$filepath = $scriptPath + '\OMNIRecTypes.csv'

$fsetpath = $scriptPath + '\FSET.csv'

$filenames = Import-Csv -Path $filepath

$fset = Import-Csv -Path $fsetpath

$currDate = Get-Date -Format 'MMdd'

$fsetCount = ($fset | Measure-Object).Count

$fileCount = ($filenames | Measure-Object).Count

for($fcnt=0; $fcnt -lt $fsetCount; $fcnt++){

    $htmlPath = $scriptPath + '\Digit' + $fset.FSET[$fcnt]

    #check if folder exist, else add folder
    if( Test-Path -Path $htmlPath){}
    else{ New-Item -ItemType Directory -Path $htmlPath}

    #initialize array variables
    $dashboard = @()

    $recordMismatchTable = @()

    $linesMismatchTable = @()

    $recordType = @()

    for($cnt=0; $cnt -lt $fileCount; $cnt++){

        $testfilename= '/Omni/data/rel595/dev/fset' + $fset.FSET[$fcnt]+ '/temp/'+ $filenames.TestFile[$cnt] + $currDate.ToString() + '*'

        $prodfilename= '/Omni/data/rel595/dev/fset' + $fset.FSET[$fcnt]+ '/temp/'+ $filenames.ProdFile[$cnt] + $currDate.ToString() + '*'

        $diffcmd = $testfilename + '' + $prodfilename

        $Diff = getFromUnix -param1 'diff' -param2 $diffcmd

        if($Diff.Length -eq 0){

            #Files are equal - No need to report

        }
        else{

            $testFile_DB = getFromUnix -param1 'cat' -param2 $testfilename # fetch the test file from Unix

            $prodFile_DB = getFromUnix -param1 'cat' -param2 $prodfilename # fetch the prod file from Unix

            $testfilepath = $scriptPath + '\test.txt' # generate path to place the test file in local machine

            $prodfilepath = $scriptPath + '\prod.txt' # generate path to place the prod file in local machine

            Set-Content -Path $testfilepath -Value $testFile_DB # save data from the unix test file to local machine

            Set-Content -Path $prodfilepath -Value $prodFile_DB # save data from the unix prod file to local machine

            #Read the saved files into variables for comparison
            $testFile = Import-csv -Path $testfilepath -Delimiter '|',

            $prodFile = Import-csv -Path $prodfilepath -Delimiter '|'

            #Call function to extract the mismatches
            captureMismatch -file1 $testFile -file2 $prodfilename

            #create record mismatch html file
            createHTMLFile -dataTable $linesMismatchTable -outFilePath $htmlPath -outFileName 'linesMismatchTable'

        }

    }

}

#calculate  the total number of mismatched rows/records across all record types
$totalRecordMismatch = 0

For($z=0; $z -lt $linesMismatchTable.length; $z++){

    $totalRecordMismatch+= $linesMismatchTable[$z].$numbersOfFieldMismatches

    $autoregfile = '/omni/data/rel595/dev/fset' + $fset.FSET[$fcnt] + '/temp/INPUT.AUTOREG'

    $File = '/omni/data/rel595/dev/fset' + $fset.FSET[$fcnt] + '/temp/OUTPUT.DATA.AUTOREG.EXTRACT.PROD'

    $inputAutoReg = getFromUnix -param1 'cat' -param2 $autoregfile

    $inputAutoRegLength = $inputAutoReg.Length

    $testOrProdFile = getFromUnix -param1 'cat' -param2 $File

    $testOrProdFileLength = $testOrProdFile.Length

    #Create a Dashboard Object table
    $dashboard = [PSCustomObject]@{
        Report_Digit = $fset.FSET[$fcnt]
        Total_Test_Scenarios_Validated = $inputAutoRegLength
        Total_Input_records_Validated = $testOrProdFileLength
        Total_Records_Mismatch = $totalRecordMismatch
        Link_to_Mismatches = '<a href = " '+ $htmlPath+ '\'+ 'linesMismatchTable'+ '.html">Click here</a>'
    }

    #Create Html for the dashboard
    createHTMLFile -dataTable $dashboard -outFilePath $htmlPath -outFileName 'Dashboard' -Charset "UTF-8"

    $dashpath = $htmlPath+ '\Dasboard.html'

    Invoke-Item -Path $dashpath

}

#endregion script flow - sequence of steps