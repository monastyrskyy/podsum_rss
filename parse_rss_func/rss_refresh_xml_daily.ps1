param($Timer)

Write-Host "Function started..."

# Import Az modules
try {
    Write-Host "Attempting to import Az modules..."
    Import-Module Az.Storage -ErrorAction Stop
    Import-Module Az.KeyVault -ErrorAction Stop
    Import-Module SqlServer -ErrorAction Stop
    Write-Host "Az modules imported successfully."
} catch {
    Write-Host "Failed to import Az modules. Error: $_"
    throw $_
}

# Get the access token using the managed identity
try {
    $AzContext = (Get-AzContext)
    if (-not $AzContext) {
        Connect-AzAccount -Identity
    }
    Write-Host "Authenticated successfully using managed identity."
} catch {
    Write-Host "Failed to authenticate using managed identity. Error: $_"
    throw $_
}

# Fetch environment variables for SQL Database connection details
try {
    $serverName = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "SQLServerName").SecretValue | ConvertFrom-SecureString -AsPlainText
    $databaseName = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "DBName").SecretValue | ConvertFrom-SecureString -AsPlainText
    $username = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "SQLUserName").SecretValue | ConvertFrom-SecureString -AsPlainText
    $password = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "SQLPass").SecretValue | ConvertFrom-SecureString -AsPlainText
    $connectionString = "Server=$serverName;Database=$databaseName;User Id=$username;Password=$password;"

    Write-Host "Fetched database connection details from Key Vault successfully."
} catch {
    Write-Host "Failed to fetch database connection details from Key Vault. Error: $_"
    throw $_
}

# Connect to SQL Database and fetch RSS URLs and podcast names
try {
    Write-Host "Connecting to SQL Database..."
    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = $connectionString
    $sqlConnection.Open()

    $sqlCommand = $sqlConnection.CreateCommand()
    $sqlCommand.CommandText = "SELECT podcast_name, rss_url FROM dbo.rss_urls"
    $sqlDataReader = $sqlCommand.ExecuteReader()

    $podcasts = @()
    while ($sqlDataReader.Read()) {
        $podcast = @{
            Name = $sqlDataReader["podcast_name"]
            Url = $sqlDataReader["rss_url"]
        }
        $podcasts += $podcast
    }

    $sqlConnection.Close()
    Write-Host "RSS URLs and podcast names fetched from SQL Database successfully."
} catch {
    Write-Host "Failed to fetch RSS URLs and podcast names from SQL Database. Error: $_"
    throw $_
}

# Download the most recent XML file from each URL and include the podcast name in the filename
foreach ($podcast in $podcasts) {
    $rssUrl = $podcast.Url
    $podcastName = $podcast.Name -replace ' ', '_'

    try {
        Write-Host "Downloading XML file from URL: $rssUrl"
        $localTempPath = [System.IO.Path]::GetTempPath()
        $localFilePath = [System.IO.Path]::Combine($localTempPath, "$podcastName.xml")
        Invoke-WebRequest -Uri $rssUrl -OutFile $localFilePath
        Write-Host "XML file downloaded to $localFilePath"
    } catch {
        Write-Host "Failed to download XML file from $rssUrl. Error: $_"
        continue
    }

    # Optionally, upload the XML file to Azure Storage
    try {
        Write-Host "Uploading XML file to blob storage..."
        $storageAccountName = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "storageAccountName").SecretValue | ConvertFrom-SecureString -AsPlainText
        $storageAccountKey = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "storageAccountKey").SecretValue | ConvertFrom-SecureString -AsPlainText
        $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
        $blobName = "$podcastName.xml"
        Set-AzStorageBlobContent -File $localFilePath -Container "xml" -Blob $blobName -Context $storageContext -Force
        Write-Host "XML file has been uploaded to blob storage successfully."
    } catch {
        Write-Host "Failed to upload XML file to blob storage. Error: $_"
    }

    # Cleanup the local file
    try {
        Remove-Item -Path $localFilePath -Force
        Write-Host "Local XML file cleaned up successfully."
    } catch {
        Write-Host "Failed to clean up local XML file. Error: $_"
    }
}

Write-Host "Function completed successfully."
