# INTRO
# this is stage 2
# This script parses the newly loaded files every day, and adds any episodes that aren't in the database.

using namespace System.Net

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

# Azure Storage account details
$storageAccountName = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "storageAccountName").SecretValue | ConvertFrom-SecureString -AsPlainText
$storageAccountKey = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "storageAccountKey").SecretValue | ConvertFrom-SecureString -AsPlainText
$containerName = "xml"

# SQL database connection details
$server =  (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "SQLServerName").SecretValue | ConvertFrom-SecureString -AsPlainText
$database = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "DBName").SecretValue | ConvertFrom-SecureString -AsPlainText
$table = "rss_schema.rss_feed"
$user = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "SQLUserName").SecretValue | ConvertFrom-SecureString -AsPlainText
$password = (Get-AzKeyVaultSecret -VaultName "language-app-key-vault" -Name "SQLPass").SecretValue | ConvertFrom-SecureString -AsPlainText

# Set the context for the storage account
try {
    $context = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    Write-Host "Storage context created successfully."
} catch {
    Write-Host "Failed to create storage context. Error: $_"
    throw $_
}

# Retrieve all blobs in the container
$blobs = Get-AzStorageBlob -Container $containerName -Context $context

foreach ($blob in $blobs) {
    # Download the blob content
    try {
        $blobContent = Get-AzStorageBlobContent -Blob $blob.Name -Container $containerName -Context $context -Destination $blob.Name -Force
        Write-Host "Blob content downloaded successfully for: $($blob.Name)"
    } catch {
        Write-Host "Failed to download blob content for: $($blob.Name). Error: $_"
        continue
    }

    # Load the XML file
    try {
        [xml]$rss = Get-Content -Path $blob.Name
        Write-Host "XML file loaded successfully for: $($blob.Name)"
    } catch {
        Write-Host "Failed to load XML file for: $($blob.Name). Error: $_"
        continue
    }

    # Extract podcast title and language
    $podcastTitle = $rss.rss.channel.title
    $language = $rss.rss.channel.language

    # Access the items in the RSS feed
    $items = $rss.rss.channel.item

    # Function to insert RSS item into SQL table if it doesn't exist
    function Insert-RssItem {
        param (
            $title, $description, $pubDate, $enclosureUrl, $duration, $podcastTitle, $language
        )

        # Escape single quotes by replacing them with double single quotes
        $title = $title -replace "'", "''"
        $description = $description -replace "'", "''"
        $podcastTitle = $podcastTitle -replace "'", "''"

        # Create SQL query to check if the item exists
        $checkQuery = @"
        IF NOT EXISTS (SELECT 1 FROM $table WHERE link = '$enclosureUrl')
        BEGIN
            INSERT INTO $table (title, description, pubDate, link, parse_dt, download_flag, podcast_title, language)
            VALUES ('$title', '$description', '$pubDate', '$enclosureUrl', GETDATE(), 'N', '$podcastTitle', '$language')
        END
"@

        # Execute the query
        try {
            Invoke-Sqlcmd -ServerInstance $server -Database $database -Username $user -Password $password -Query $checkQuery
            Write-Host "Item inserted or already exists: $title"
        } catch {
            Write-Host "Failed to insert item: $title. Error: $_"
        }
    }

    # Loop through each item and insert into the database if it doesn't exist
    foreach ($item in $items) {
        $title = [string]$item.title
        $description = [string]$item.description
        $pubDate = [datetime]::Parse($item.pubDate, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
        $enclosureUrl = [string]$item.enclosure.url
        $duration = [int]$item.'itunes:duration'

        # Insert the item into the SQL table
        Insert-RssItem -title $title -description $description -pubDate $pubDate -enclosureUrl $enclosureUrl -duration $duration -podcastTitle $podcastTitle -language $language
    }
    # Attempt to delete the XML file after processing
    try {
        Remove-Item -Path $blob.Name -Force
        Write-Host "Temporary file deleted successfully: $($blob.Name)"
    } catch {
        Write-Host "Failed to delete temporary file: $($blob.Name). Error: $_"
    }
}

Write-Host "Function completed for all files in the container."
