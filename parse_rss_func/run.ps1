param($Timer)

Write-Host "Function started..."

# Import Az.Storage module
try {
    Write-Host "Attempting to import Az.Storage module..."
    Import-Module Az.Storage -ErrorAction Stop
    Write-Host "Az.Storage module imported successfully."
} catch {
    Write-Host "Failed to import Az.Storage module. Error: $_"
    throw $_
}

# Azure Storage account details
$storageAccountName = "n/a"
$storageAccountKey = "n/a"
$containerName = "mp3files-test"
$blobName = "ROCKETBEANSENTERTAINMENT4437801693.mp3"
$fileUrl = "https://traffic.megaphone.fm/ROCKETBEANSENTERTAINMENT4437801693.mp3?updated=1719596856"

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "AAAAAAAAAAAAAAAAAAAAAHH! TIME: $currentUTCtime"
Write-Host "two! TIME: $currentUTCtime"
Write-Host "three! TIME: $currentUTCtime"

# Download the MP3 file
try {
    Write-Host "Downloading MP3 file from URL: $fileUrl"
    $localFilePath = [System.IO.Path]::GetTempFileName() + ".mp3"
    Invoke-WebRequest -Uri $fileUrl -OutFile $localFilePath
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
    Set-AzStorageBlobContent -File $localFilePath -Container $containerName -Blob $blobName -Context $storageContext
    Write-Host "MP3 file has been uploaded to blob storage successfully."
} catch {
    Write-Host "Failed to upload MP3 file to blob storage. Error: $_"
    throw $_
}

# Cleanup the local file
try {
    Remove-Item -Path $localFilePath -Force
    Write-Host "Local MP3 file cleaned up successfully."
} catch {
    Write-Host "Failed to clean up local MP3 file. Error: $_"
    throw $_
}

Write-Host "Function completed successfully."
