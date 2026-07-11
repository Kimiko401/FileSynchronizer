Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Configuration File Path ---
$configPath = "$PSScriptRoot\sync_config.json"
if (Test-Path $configPath) { 
    $config = Get-Content $configPath | ConvertFrom-Json 
} else { 
    $config = [PSCustomObject]@{ LocalPath = ""; RemotePath = ""; KeyPath = "" } 
}

# --- GUI Setup ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "SyncTool - AutoUpload"
$form.Size = New-Object System.Drawing.Size(580, 290) # Increased height slightly for better spacing
$form.BackColor = [System.Drawing.Color]::FromArgb(35,35,40)
$form.ForeColor = "White"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.StartPosition = "CenterScreen"

# Colors
$primary = [System.Drawing.Color]::FromArgb(0,120,215)
$success = [System.Drawing.Color]::FromArgb(30,180,90)
$danger  = [System.Drawing.Color]::FromArgb(210,70,70)
$panel   = [System.Drawing.Color]::FromArgb(45,45,50)

# GroupBox
$group = New-Object System.Windows.Forms.GroupBox
$group.Text = "Project Settings"
$group.Location = New-Object System.Drawing.Point(15, 15)
$group.Size = New-Object System.Drawing.Size(535, 150)
$group.ForeColor = "White"
$group.BackColor = $panel

# Local Path Elements
$lblLocal = New-Object System.Windows.Forms.Label; $lblLocal.Text = "Local Project Folder:"; $lblLocal.Location = New-Object System.Drawing.Point(10, 30); $lblLocal.AutoSize = $true
$txtLocal = New-Object System.Windows.Forms.TextBox; $txtLocal.Text = $config.LocalPath; $txtLocal.Location = New-Object System.Drawing.Point(150, 28); $txtLocal.Width = 300
$btnBrowse = New-Object System.Windows.Forms.Button; $btnBrowse.Text = "..."; $btnBrowse.Location = New-Object System.Drawing.Point(460, 27); $btnBrowse.Size = New-Object System.Drawing.Size(30, 25); $btnBrowse.ForeColor = "Black"
$btnBrowse.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtLocal.Text = $folderBrowser.SelectedPath }
})

# SSH Key Path
$lblKey = New-Object System.Windows.Forms.Label; $lblKey.Text = "SSH Private Key:"; $lblKey.Location = New-Object System.Drawing.Point(10, 65); $lblKey.AutoSize = $true
$txtKey = New-Object System.Windows.Forms.TextBox; $txtKey.Text = $config.KeyPath; $txtKey.Location = New-Object System.Drawing.Point(150, 63); $txtKey.Width = 300
$btnBrowseKey = New-Object System.Windows.Forms.Button; $btnBrowseKey.Text = "..."; $btnBrowseKey.Location = New-Object System.Drawing.Point(460, 62); $btnBrowseKey.Size = New-Object System.Drawing.Size(30, 25); $btnBrowseKey.ForeColor = "Black"
$btnBrowseKey.Add_Click({
    $of = New-Object System.Windows.Forms.OpenFileDialog
    $of.Filter = "SSH Keys (*)|*|All Files (*.*)|*.*"
    if ($of.ShowDialog() -eq "OK") { $txtKey.Text = $of.FileName }
})

# Remote Path Elements
$lblRemote = New-Object System.Windows.Forms.Label; $lblRemote.Text = "Remote Server Path:"; $lblRemote.Location = New-Object System.Drawing.Point(10, 100); $lblRemote.AutoSize = $true
$txtRemote = New-Object System.Windows.Forms.TextBox; $txtRemote.Text = $config.RemotePath; $txtRemote.Location = New-Object System.Drawing.Point(150, 98); $txtRemote.Width = 340
$lblRemoteHint = New-Object System.Windows.Forms.Label; $lblRemoteHint.Text = "Example: user@domain.com:/path/to/folder"; $lblRemoteHint.Location = New-Object System.Drawing.Point(150, 125); $lblRemoteHint.ForeColor = "Gray"; $lblRemoteHint.AutoSize = $true

# Add Elements to GroupBox
$group.Controls.AddRange(@($lblLocal, $txtLocal, $btnBrowse, $lblKey, $txtKey, $btnBrowseKey, $lblRemote, $txtRemote, $lblRemoteHint))

# Buttons (Positioned beneath the GroupBox)
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Save Config"
$btnSave.Location = New-Object System.Drawing.Point(130, 180)
$btnSave.Size = New-Object System.Drawing.Size(140, 38)
$btnSave.FlatStyle = "Flat"
$btnSave.BackColor = $primary
$btnSave.ForeColor = "White"
$btnSave.Add_Click({
    $data = [PSCustomObject]@{ LocalPath = $txtLocal.Text; RemotePath = $txtRemote.Text; KeyPath = $txtKey.Text }
    $data | ConvertTo-Json | Set-Content $configPath
    [System.Windows.Forms.MessageBox]::Show("Configuration Saved!", "Success", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
})

$btnToggle = New-Object System.Windows.Forms.Button
$btnToggle.Text = "Start Sync"
$btnToggle.Location = New-Object System.Drawing.Point(290, 180)
$btnToggle.Size = New-Object System.Drawing.Size(140, 38)
$btnToggle.FlatStyle = "Flat"
$btnToggle.BackColor = $success
$btnToggle.ForeColor = "White"

# Status Strip
$status = New-Object System.Windows.Forms.StatusStrip
$status.BackColor = [System.Drawing.Color]::FromArgb(45,45,50)
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Status: Idle"
$statusLabel.ForeColor = "White"
$status.Items.Add($statusLabel)

# Logic
$global:watcher = $null
$global:eventSubscriber = $null

$btnToggle.Add_Click({
    if ($global:watcher -eq $null) {
        if (-not (Test-Path $txtLocal.Text)) { 
            [System.Windows.Forms.MessageBox]::Show("Invalid Local Path!", "Error", 0, [System.Windows.Forms.MessageBoxIcon]::Error)
            return 
        }
        
        # 1. Initialize Watcher
        $global:watcher = New-Object System.IO.FileSystemWatcher $txtLocal.Text, "*.*"
        $global:watcher.IncludeSubdirectories = $true
        $global:watcher.EnableRaisingEvents = $true
        
        # 2. Package Variables into MessageData
        $eventData = @{
            KeyPath = $txtKey.Text
            RemotePath = $txtRemote.Text
        }
        
        # 3. Define the Action (Using $Event.MessageData to pass variables inside)
        $action = {
            $path = $Event.SourceEventArgs.FullPath
            $key = $Event.MessageData.KeyPath
            $remote = $Event.MessageData.RemotePath
            
            # Arrays passed to ArgumentList automatically handle spaces in paths
            Start-Process scp -ArgumentList "-i", $key, "-o", "BatchMode=yes", $path, $remote -WindowStyle Hidden
        }
        
        # Register the Event
        $global:eventSubscriber = Register-ObjectEvent -InputObject $global:watcher -EventName "Changed" -MessageData $eventData -Action $action
        
        # Update UI
        $btnToggle.Text = "Stop Sync"
        $btnToggle.BackColor = $danger
        $statusLabel.Text = "Status: Monitoring for changes..."
    } else {
        # 1. Stop the events
        $global:watcher.EnableRaisingEvents = $false
        
        # 2. Unregister and cleanup
        if ($global:eventSubscriber) {
            Unregister-Event -SourceIdentifier $global:eventSubscriber.Name
            Remove-Job -Name $global:eventSubscriber.Name # Cleans up the background job created by the event
            $global:eventSubscriber = $null
        }
        
        $global:watcher.Dispose()
        $global:watcher = $null
        
        # Update UI
        $btnToggle.Text = "Start Sync"
        $btnToggle.BackColor = $success
        $statusLabel.Text = "Status: Idle"
    }
})

# Add Main Controls to Form
$form.Controls.AddRange(@($group, $btnSave, $btnToggle, $status))

# Show Form
$form.ShowDialog() | Out-Null