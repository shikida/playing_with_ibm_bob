# Bob Slack Monitor
# Executes Bob command every 10 seconds to read Slack messages from the last 10 seconds
# and react with a single message

param(
    [int]$IntervalSeconds = 10,
    [string]$Channel = "<YOUR SLACK CHANNEL HERE>",
    [string]$SlackToken = "<YOUR SLACK TOKEN HERE>"
)

Write-Host "=== Bob Slack Monitor ===" -ForegroundColor Cyan
Write-Host "Canal: $Channel" -ForegroundColor Green
Write-Host "Interval: $IntervalSeconds seconds" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

$iteration = 0
$lastProcessedTimestamp = [double]0

function Get-SlackMessages {
    param(
        [string]$ChannelId,
        [string]$Token,
        [double]$OldestTimestamp
    )
    
    try {
        $headers = @{
            Authorization = "Bearer $Token"
        }
        
        $params = @{
            channel = $ChannelId
            limit = 100
        }
        
        if ($OldestTimestamp -gt 0) {
            $params.oldest = $OldestTimestamp
        }
        
        $uri = "https://slack.com/api/conversations.history?" + (($params.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&")
        
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        
        if ($response.ok) {
            return $response.messages
        }
        else {
            Write-Host "Slack API Error: $($response.error)" -ForegroundColor Red
            return @()
        }
    }
    catch {
        Write-Host "Error fetching messages: $_" -ForegroundColor Red
        return @()
    }
}

function Save-MessagesToFile {
    param(
        [array]$Messages,
        [string]$FilePath = "chat.txt",
        [bool]$Append = $true
    )
    
    if ($Messages.Count -eq 0) {
        return
    }
    
    # Read existing content if append mode
    $existingContent = @()
    $existingTimestamps = @{}
    
    if ($Append -and (Test-Path $FilePath)) {
        $existingLines = Get-Content $FilePath -ErrorAction SilentlyContinue
        foreach ($line in $existingLines) {
            if ($line -match '^\[(\d{2}:\d{2}:\d{2})\]') {
                $existingTimestamps[$line] = $true
            }
            $existingContent += $line
        }
    }
    
    # Prepare new messages
    $newMessages = @()
    foreach ($msg in $Messages) {
        $timestamp = [double]$msg.ts
        $dateTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$timestamp).LocalDateTime
        $user = if ($msg.user) { $msg.user } else { "Unknown" }
        $text = if ($msg.text) { $msg.text } else { "(no text)" }
        
        $line = "[$($dateTime.ToString('HH:mm:ss'))] $user : $text"
        
        # Add only if it doesn't exist
        if (-not $existingTimestamps.ContainsKey($line)) {
            $newMessages += $line
        }
    }
    
    # Build final content
    $content = @()
    
    if ($Append -and $existingContent.Count -gt 0) {
        # Keep existing content
        $content += $existingContent
        
        # Add new messages
        if ($newMessages.Count -gt 0) {
            $content += ""
            $content += "# New messages added at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $content += $newMessages
        }
    }
    else {
        # Create new file
        $content += "# Complete Slack History"
        $content += "# Started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $content += ""
        $content += $newMessages
    }
    
    $content | Out-File -FilePath $FilePath -Encoding UTF8 -Force
}

while ($true) {
    $iteration++
    $timestamp = Get-Date -Format "HH:mm:ss"
    $currentUnixTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    
    Write-Host "`n[$timestamp] === Iteration $iteration ===" -ForegroundColor Cyan
    
    # Calculate timestamp from 10 seconds ago
    $tenSecondsAgo = $currentUnixTime - 10
    
    # If first iteration, use timestamp from 10 seconds ago
    if ($lastProcessedTimestamp -eq 0) {
        $lastProcessedTimestamp = [double]$tenSecondsAgo
    }
    
    Write-Host "[$timestamp] Fetching messages since timestamp $lastProcessedTimestamp..." -ForegroundColor Cyan
    
    # Fetch Slack messages since the last processed timestamp
    $messages = Get-SlackMessages -ChannelId $Channel -Token $SlackToken -OldestTimestamp $lastProcessedTimestamp
    
    # Filter new messages (since last processed timestamp)
    $newMessages = $messages | Where-Object {
        $msgTimestamp = [double]$_.ts
        $msgTimestamp -gt $lastProcessedTimestamp
    } | Sort-Object { [double]$_.ts }
    
    # Filter messages from the last 10 seconds to react to
    $recentMessages = $newMessages | Where-Object {
        $msgTimestamp = [double]$_.ts
        $msgTimestamp -gt $tenSecondsAgo
    }
    
    if ($newMessages.Count -eq 0) {
        Write-Host "[$timestamp] No new messages" -ForegroundColor DarkGray
        Write-Host "[$timestamp] Waiting $IntervalSeconds seconds..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }
    
    Write-Host "[$timestamp] Found $($newMessages.Count) new message(s)" -ForegroundColor Yellow
    
    # Save ALL new messages to complete history
    Save-MessagesToFile -Messages $newMessages -FilePath "conversa.txt" -Append $true
    Write-Host "[$timestamp] History updated in conversa.txt ($($newMessages.Count) messages added)" -ForegroundColor Green
    
    # Check if there are recent messages to react to
    if ($recentMessages.Count -eq 0) {
        Write-Host "[$timestamp] No messages in the last 10 seconds to react to" -ForegroundColor DarkGray
        
        # Update timestamp even without reacting
        $latestTimestamp = ($newMessages | ForEach-Object { [double]$_.ts } | Measure-Object -Maximum).Maximum
        $lastProcessedTimestamp = $latestTimestamp
        
        Write-Host "[$timestamp] Waiting $IntervalSeconds seconds..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }
    
    Write-Host "[$timestamp] $($recentMessages.Count) message(s) from the last 10 seconds to react to" -ForegroundColor Yellow
    
    # Update last processed timestamp
    $latestTimestamp = ($recentMessages | ForEach-Object { [double]$_.ts } | Measure-Object -Maximum).Maximum
    $lastProcessedTimestamp = $latestTimestamp
    
    # Execute Bob to react to messages
    Write-Host "[$timestamp] Executing Bob to react to messages..." -ForegroundColor Magenta
    
    try {
        $bobCommand = "read the conversa.txt file to understand the full context, read the personalidade.txt file to determine your behavior and send a single message reacting to messages with timestamps from the last 10 seconds to the #hackathon channel on slack"
        
        bob $bobCommand --allowed-mcp-server-names slack-mcp
        
        Write-Host "[$timestamp] Bob command executed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "[$timestamp] Error executing Bob: $_" -ForegroundColor Red
    }
    
    # Wait for next cycle
    Write-Host "[$timestamp] Waiting $IntervalSeconds seconds..." -ForegroundColor DarkGray
    Start-Sleep -Seconds $IntervalSeconds
}

# Made with Bob
