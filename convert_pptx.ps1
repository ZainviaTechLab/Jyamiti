<#
.SYNOPSIS
  One-Click High-Fidelity PPTX to Jyamiti SlideDeck Converter
.DESCRIPTION
  Uses Windows native PowerPoint to export 1080p slide images and builds a ready-to-import Jyamiti SlideDeck JSON file.
.EXAMPLE
  .\convert_pptx.ps1 -PptxPath "C:\path\to\presentation.pptx"
  .\convert_pptx.ps1 -PptxPath "C:\path\to\presentation.pptx" -EmbedBase64
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$PptxPath,

    [string]$OutputDir = ".\converted_slides",
    [string]$CourseName = "Mathematics",
    [string]$CourseId = "course_101",
    [string]$Theme = "darkGlass",
    [switch]$EmbedBase64
)

$resolvedPptx = Resolve-Path $PptxPath
if (-not (Test-Path $resolvedPptx)) {
    Write-Error "File not found: $PptxPath"
    exit 1
}

$fileItem = Get-Item $resolvedPptx
$deckTitle = [System.IO.Path]::GetFileNameWithoutExtension($fileItem.Name) -replace "[_-]", " "
$deckId = "deck_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

$resolvedOut = New-Item -ItemType Directory -Force -Path $OutputDir
$imgDir = New-Item -ItemType Directory -Force -Path (Join-Path $resolvedOut "$($fileItem.BaseName)_slides")

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " Jyamiti High-Fidelity PPTX Converter" -ForegroundColor Cyan
Write-Host " Converting: $($fileItem.Name)" -ForegroundColor Yellow
Write-Host "======================================================="

Write-Host "-> Initializing Windows PowerPoint COM Engine..." -ForegroundColor Gray
$ppApp = New-Object -ComObject PowerPoint.Application
$ppApp.Visible = [Microsoft.Office.Core.MsoTriState]::msoFalse

$slidesList = @()

try {
    $pres = $ppApp.Presentations.Open($resolvedPptx, [Microsoft.Office.Core.MsoTriState]::msoTrue, [Microsoft.Office.Core.MsoTriState]::msoFalse, [Microsoft.Office.Core.MsoTriState]::msoFalse)
    $slideIndex = 0
    $totalCount = $pres.Slides.Count
    Write-Host "-> Exporting $totalCount slides in 1080p resolution..." -ForegroundColor Green

    foreach ($slide in $pres.Slides) {
        $slideIndex++
        $imgName = "slide_$slideIndex.png"
        $imgPath = Join-Path $imgDir.FullName $imgName
        $slide.Export($imgPath, 'PNG', 1920, 1080)

        # Extract title text if available
        $slideTitle = "Slide $slideIndex"
        $texts = @()
        foreach ($shape in $slide.Shapes) {
            if ($shape.HasTextFrame -and $shape.TextFrame.HasText) {
                $t = $shape.TextFrame.TextRange.Text.Trim()
                if ($t.Length -gt 0) {
                    if ($shape.Type -eq 14 -or ($slideTitle -eq "Slide $slideIndex" -and $t.Length -lt 80)) {
                        $slideTitle = $t
                    } else {
                        $texts += $t
                    }
                }
            }
        }

        $imgUrl = $imgPath
        if ($EmbedBase64) {
            $bytes = [System.IO.File]::ReadAllBytes($imgPath)
            $b64 = [System.Convert]::ToBase64String($bytes)
            $imgUrl = "data:image/png;base64,$b64"
        }

        $blocks = @()
        foreach ($para in ($texts | Select-Object -First 3)) {
            $blocks += @{
                id = "b_${slideIndex}_" + [guid]::NewGuid().ToString().Substring(0, 6)
                type = "paragraph"
                content = $para
                extra = $null
                caption = $null
            }
        }

        $slidesList += @{
            id = "s_${deckId}_$($slideIndex - 1)"
            slideIndex = ($slideIndex - 1)
            title = $slideTitle
            theme = $Theme
            imageUrl = $imgUrl
            enableWhiteboard = $true
            blocks = $blocks
            quiz = $null
        }
        Write-Host "   [Slide $slideIndex/$totalCount] Exported: $slideTitle" -ForegroundColor Gray
    }
    $pres.Close()
} finally {
    $ppApp.Quit()
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

$deckObject = @{
    id = $deckId
    courseId = $CourseId
    courseName = $CourseName
    title = $deckTitle
    description = "Imported high-fidelity presentation converted from $($fileItem.Name)."
    createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")
    isPublished = $true
    isDownloadedOffline = $true
    slides = $slidesList
}

$jsonFile = Join-Path $resolvedOut "$($fileItem.BaseName)_deck.json"
$deckObject | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonFile -Encoding UTF8

Write-Host "`n[SUCCESS] SlideDeck JSON generated successfully!" -ForegroundColor Green
Write-Host "Output File: $jsonFile" -ForegroundColor Yellow
Write-Host "You can now open the Jyamiti App and tap 'Import Deck' in Slide Decks CMS to load it instantly!`n"
