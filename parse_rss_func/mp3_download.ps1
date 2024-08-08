# Input bindings are passed in via param block.
param($Timer)

Write-Host "Function started..."

# Import Az.Storage module
try {
    Write-Host "Attempting to import Az.Storage module..."
    Import-Module Az.Storage -ErrorAction Stop
    Import-Module Az.KeyVault -ErrorAction Stop
    Write-Host "Az.Storage module imported successfully."
} catch {
    Write-Host "Failed to import Az.Storage module. Error: $_"
    throw $_
}

# Import SqlServer module
try {
    Write-Host "Attempting to import SqlServer module..."
    Import-Module SqlServer -ErrorAction Stop
    Write-Host "SqlServer module imported successfully."
} catch {
    Write-Host "Failed to import SqlServer module. Error: $_"
    throw $_
}

# Define connection details
$storageAccountName = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "storageAccountName").SecretValue | ConvertFrom-SecureString -AsPlainText
$storageAccountKey = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "storageAccountKey").SecretValue | ConvertFrom-SecureString -AsPlainText
$containerName = "mp3"
$sqlServerName = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "SQLServerName").SecretValue | ConvertFrom-SecureString -AsPlainText
$sqlDatabaseName = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "DBName").SecretValue | ConvertFrom-SecureString -AsPlainText
$sqlUserName = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "SQLUserName").SecretValue | ConvertFrom-SecureString -AsPlainText
$sqlPassword = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "SQLPass").SecretValue | ConvertFrom-SecureString -AsPlainText

# Connect to Azure Storage
$ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    
# Ensure the container exists
if (-not (Get-AzStorageContainer -Name $containerName -Context $ctx)) {
    New-AzStorageContainer -Name $containerName -Context $ctx
}

# Query to get the most recent episodes with download_flag set to "N"
$query = @"
SELECT TOP 1 *
FROM rss_schema.rss_feed
WHERE download_flag = 'N'
ORDER BY pubDate DESC;
"@

# Execute the query
$episodes = Invoke-Sqlcmd -ServerInstance $sqlServerName -Database $sqlDatabaseName -Username $sqlUserName -Password $sqlPassword -Query $query

foreach ($episode in $episodes) {
    $podcastTitle = $episode.podcast_title -replace ' ', '-'
    $episodeTitle = $episode.title -replace ' ', '-'
    $rssUrl = $episode.link
    $folderPath = "mp3/$podcastTitle"
    $blobPath = "$folderPath/$episodeTitle.mp3"

    Write-Host "podcastTitle: $podcastTitle"
    Write-Host "episodeTitle: $episodeTitle"
    Write-Host "rssUrl: $rssUrl"
    Write-Host "folderPath: $folderPath"
    Write-Host "blobPath: $blobPath"

    # Sanitize file name
    $sanitizedEpisodeTitle = $episodeTitle -replace '[^a-zA-Z0-9\-]', ''
    $localFilePath = Join-Path $env:TEMP "$sanitizedEpisodeTitle.mp3"
    Write-Host "sanitizedEpisodeTitle: $sanitizedEpisodeTitle"
    Write-Host "localFilePath: $localFilePath"

    # Download the MP3 file
    try {
        Write-Host "Downloading MP3 file from URL: $rssUrl"
        Invoke-WebRequest -Uri $rssUrl -OutFile $localFilePath
        Write-Host "MP3 file downloaded to $localFilePath"
    } catch {
        Write-Host "Failed to download MP3 file. Error: $_"
        throw $_
    }

    # Create a storage context
    try {
        Write-Host "Creating storage context..."
        $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
        Write-Host "Storage context created successfully."
    } catch {
        Write-Host "Failed to create storage context. Error: $_"
        throw $_
    }

    # Upload the MP3 file to the blob
    try {
        Write-Host "Uploading MP3 file to blob storage..."
        Set-AzStorageBlobContent -File $localFilePath -Container $containerName -Blob $blobPath -Context $storageContext
        Write-Host "MP3 file has been uploaded to blob storage successfully."

        
        # Cleanup the local file
        try {
            Remove-Item -Path $localFilePath -Force
            Write-Host "Local MP3 file cleaned up successfully."
        } catch {
            Write-Host "Failed to clean up local MP3 file. Error: $_"
            throw $_
        }
    } catch {
        Write-Host "Failed to upload MP3 file to blob storage. Error: $_"
        throw $_
    }
    # Update the SQL database
    try {
        $updateQuery = "UPDATE rss_schema.rss_feed SET download_flag = 'Y', download_dt = GETDATE() WHERE link = '$rssUrl';"
        Write-Host "Updating SQL database..."
        Invoke-Sqlcmd -ServerInstance $sqlServerName -Database $sqlDatabaseName -Username $sqlUserName -Password $sqlPassword -Query $updateQuery
        Write-Host "SQL database updated successfully."
    } catch {
        Write-Host "Failed to update SQL database. Error: $_"
        throw $_
    }

}
