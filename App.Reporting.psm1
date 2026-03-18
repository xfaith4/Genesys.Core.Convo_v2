#Requires -Version 5.1
Set-StrictMode -Version Latest

function New-ImpactReport {
    <#
    .SYNOPSIS
        Generates aggregate impact rollups for the currently filtered run index.
    #>
    param(
        [Parameter(Mandatory)][object[]]$FilteredIndex,
        [string]$ReportTitle = 'Conversation Impact Report'
    )

    if ($null -eq $FilteredIndex) { $FilteredIndex = @() }
    $rows = @($FilteredIndex)
    $generatedAt = (Get-Date).ToString('o')

    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            ReportTitle         = $ReportTitle
            GeneratedAt         = $generatedAt
            TotalConversations  = 0
            Message             = 'No conversations found in the current filter to generate a report.'
            TimeWindow          = $null
            ImpactByDivision    = @()
            ImpactByQueue       = @()
            AffectedAgents      = @()
            DirectionBreakdown  = @()
            MediaTypeBreakdown  = @()
        }
    }

    $impactByDivision = $rows |
        Where-Object { $_.divisionIds } |
        ForEach-Object { @($_.divisionIds) } |
        Group-Object |
        Sort-Object Count -Descending, Name |
        ForEach-Object {
            [pscustomobject]@{
                DivisionId = $_.Name
                Count      = $_.Count
            }
        }

    $impactByQueue = $rows |
        Where-Object { $_.queueIds } |
        ForEach-Object { @($_.queueIds) } |
        Group-Object |
        Sort-Object Count -Descending, Name |
        ForEach-Object {
            [pscustomobject]@{
                QueueId = $_.Name
                Count   = $_.Count
            }
        }

    $affectedAgents = $rows |
        Where-Object { $_.userIds } |
        ForEach-Object { @($_.userIds) } |
        Group-Object |
        Sort-Object Count -Descending, Name |
        ForEach-Object {
            [pscustomobject]@{
                AgentId = $_.Name
                Count   = $_.Count
            }
        }

    $directionBreakdown = $rows |
        Where-Object { $_.direction } |
        Group-Object direction |
        Sort-Object Count -Descending, Name |
        ForEach-Object {
            [pscustomobject]@{
                Direction = $_.Name
                Count     = $_.Count
            }
        }

    $mediaTypeBreakdown = $rows |
        Where-Object { $_.mediaType } |
        Group-Object mediaType |
        Sort-Object Count -Descending, Name |
        ForEach-Object {
            [pscustomobject]@{
                MediaType = $_.Name
                Count     = $_.Count
            }
        }

    $conversationStarts = $rows |
        Where-Object { $_.conversationStart } |
        ForEach-Object {
            try { [datetime]::Parse([string]$_.conversationStart) } catch { $null }
        } |
        Where-Object { $null -ne $_ } |
        Sort-Object

    $timeWindow = $null
    if ($conversationStarts.Count -gt 0) {
        $timeWindow = [pscustomobject]@{
            Start = $conversationStarts[0].ToString('o')
            End   = $conversationStarts[$conversationStarts.Count - 1].ToString('o')
        }
    }

    return [pscustomobject]@{
        ReportTitle         = $ReportTitle
        GeneratedAt         = $generatedAt
        TotalConversations  = $rows.Count
        TimeWindow          = $timeWindow
        ImpactByDivision    = @($impactByDivision)
        ImpactByQueue       = @($impactByQueue)
        AffectedAgents      = @($affectedAgents)
        DirectionBreakdown  = @($directionBreakdown)
        MediaTypeBreakdown  = @($mediaTypeBreakdown)
    }
}

Export-ModuleMember -Function New-ImpactReport
