$json = Get-Content ".\survey.json" -Raw -Encoding utf8 | ConvertFrom-Json

function Get-DimensionWeights($data) {
  $baseWeights = @{ discipline = 1.08; weapon = 1.1; breakthrough = 1.14; setup = 1.18; tactics = 1.22; clutch = 1.14; economy = 1.08 }
  $teams = @($data.teams)
  $teamCount = [Math]::Max($teams.Count, 1)
  $result = @{}
  foreach ($dimension in $data.dimensions) {
    $values = @()
    foreach ($team in $teams) { $values += [double]$team.profile.($dimension.id) }
    $mean = ($values | Measure-Object -Average).Average
    $variance = 0.0
    foreach ($value in $values) { $variance += [Math]::Pow(($value - $mean), 2) }
    $variance = $variance / $teamCount
    $varianceBonus = [Math]::Min(0.45, $variance / 80.0)
    $result[$dimension.id] = [double]$baseWeights[$dimension.id] + $varianceBonus
  }
  return $result
}

function Get-TotalQuestionWeight($data, $extraQuestions) {
  $sum = 0.0
  foreach ($q in $data.questions) { $sum += [double]($(if ($null -ne $q.weight) { $q.weight } else { 1 })) }
  foreach ($q in $extraQuestions) { $sum += [double]($(if ($null -ne $q.weight) { $q.weight } else { 1 })) }
  return $sum
}

function Get-NormalizedScores($data, $answers, $extraQuestions, $extraAnswers) {
  $dimensionScores = @{}
  foreach ($dimension in $data.dimensions) { $dimensionScores[$dimension.id] = 0.0 }
  $sets = @(@{ questions = $data.questions; answers = $answers }, @{ questions = $extraQuestions; answers = $extraAnswers })
  foreach ($set in $sets) {
    $qs = @($set.questions)
    $ans = @($set.answers)
    for ($i = 0; $i -lt $qs.Count; $i++) {
      if ($i -ge $ans.Count) { continue }
      $answerIndex = $ans[$i]
      if ($null -eq $answerIndex -or $answerIndex -lt 0) { continue }
      $question = $qs[$i]
      $option = $question.options[$answerIndex]
      $weight = [double]($(if ($null -ne $question.weight) { $question.weight } else { 1 }))
      foreach ($dimension in $data.dimensions) {
        $scoreValue = 0.0
        if ($null -ne $option.scores -and $null -ne $option.scores.($dimension.id)) { $scoreValue = [double]$option.scores.($dimension.id) }
        $dimensionScores[$dimension.id] += $scoreValue * $weight
      }
    }
  }
  $maxPerQuestion = [double]($(if ($null -ne $data.questionMaxScore) { $data.questionMaxScore } else { 5 }))
  $responseScale = [double]($(if ($null -ne $data.responseScale) { $data.responseScale } else { $maxPerQuestion }))
  $totalPossible = (Get-TotalQuestionWeight $data $extraQuestions) * $maxPerQuestion
  $normalized = @{}
  foreach ($dimension in $data.dimensions) {
    $normalized[$dimension.id] = ([double]$dimensionScores[$dimension.id] / $totalPossible) * $responseScale
  }
  return $normalized
}

function Get-TeamBonuses($data, $answers, $extraQuestions, $extraAnswers) {
  $bonusMap = @{}
  $defaultScale = [double]($(if ($null -ne $data.teamBonusScale) { $data.teamBonusScale } else { 1 }))
  $questionScale = [double]($(if ($null -ne $data.questionTeamBonusScale) { $data.questionTeamBonusScale } else { $defaultScale }))
  $tiebreakerScale = [double]($(if ($null -ne $data.tiebreakerTeamBonusScale) { $data.tiebreakerTeamBonusScale } else { $defaultScale }))
  $sets = @(@{ questions = $data.questions; answers = $answers; scale = $questionScale }, @{ questions = $extraQuestions; answers = $extraAnswers; scale = $tiebreakerScale })
  foreach ($set in $sets) {
    $qs = @($set.questions)
    $ans = @($set.answers)
    for ($i = 0; $i -lt $qs.Count; $i++) {
      if ($i -ge $ans.Count) { continue }
      $answerIndex = $ans[$i]
      if ($null -eq $answerIndex -or $answerIndex -lt 0) { continue }
      $question = $qs[$i]
      $option = $question.options[$answerIndex]
      $weight = [double]($(if ($null -ne $question.weight) { $question.weight } else { 1 }))
      if ($null -ne $option.teamBonus) {
        foreach ($p in $option.teamBonus.PSObject.Properties) {
          if (-not $bonusMap.ContainsKey($p.Name)) { $bonusMap[$p.Name] = 0.0 }
          $bonusMap[$p.Name] += [double]$p.Value * $weight * [double]$set.scale
        }
      }
    }
  }
  return $bonusMap
}

function Get-SignatureBonus($data, $userNormalized, $item) {
  $responseScale = [double]($(if ($null -ne $data.responseScale) { $data.responseScale } else { $(if ($null -ne $data.questionMaxScore) { $data.questionMaxScore } else { 5 }) }))
  $teamScale = [double]($(if ($null -ne $data.teamScale) { $data.teamScale } else { $responseScale }))
  $maxGap = $responseScale + $teamScale
  $entries = @()
  foreach ($dimension in $data.dimensions) {
    $teamValue = [double]$item.profile.($dimension.id)
    if ([Math]::Abs($teamValue) -ge 5) { $entries += [PSCustomObject]@{ id = $dimension.id; teamValue = $teamValue } }
  }
  $entries = $entries | Sort-Object { [Math]::Abs($_.teamValue) } -Descending | Select-Object -First 3
  $sum = 0.0
  foreach ($entry in $entries) {
    $userValue = [double]$userNormalized[$entry.id]
    if ($userValue -eq 0) { continue }
    if ([Math]::Sign($userValue) -ne [Math]::Sign($entry.teamValue)) { continue }
    $closeness = 1 - [Math]::Min(1, [Math]::Abs($userValue - $entry.teamValue) / $maxGap)
    $sum += $closeness * 1.2
  }
  return $sum
}

function Get-TeamAdjustment($data, $item) {
  $profile = $item.profile
  $sum = 0.0
  foreach ($dimension in $data.dimensions) { $sum += [Math]::Abs([double]$profile.($dimension.id)) }
  $averageIntensity = $sum / $data.dimensions.Count
  return [PSCustomObject]@{
    intensityCompensation = [Math]::Max(0.0, $averageIntensity - 3.2) * 1.15
    popularityBias = [double]($(if ($null -ne $item.popularityBias) { $item.popularityBias } else { 0 }))
    resultWeight = [double]($(if ($null -ne $item.resultWeight) { $item.resultWeight } else { 1 }))
  }
}

function Get-Matches($data, $items, $userNormalized, $bonusMap) {
  $responseScale = [double]($(if ($null -ne $data.responseScale) { $data.responseScale } else { $(if ($null -ne $data.questionMaxScore) { $data.questionMaxScore } else { 5 }) }))
  $teamScale = [double]($(if ($null -ne $data.teamScale) { $data.teamScale } else { $responseScale }))
  $maxDistancePerDimension = $responseScale + $teamScale
  $dimensionWeights = Get-DimensionWeights $data
  $weightedMaxDistance = 0.0
  foreach ($dimension in $data.dimensions) { $weightedMaxDistance += [double]$dimensionWeights[$dimension.id] * $maxDistancePerDimension }

  $results = @()
  foreach ($item in $items) {
    $distance = 0.0
    foreach ($dimension in $data.dimensions) {
      $userValue = [double]$userNormalized[$dimension.id]
      $teamValue = [double]$item.profile.($dimension.id)
      $diffRatio = [Math]::Abs($userValue - $teamValue) / $maxDistancePerDimension
      $weight = [double]$dimensionWeights[$dimension.id]
      $shapedDistance = ($diffRatio * 0.45 + $diffRatio * $diffRatio * 0.55) * $maxDistancePerDimension
      $distance += $shapedDistance * $weight
    }
    $rawBonus = 0.0
    if ($bonusMap.ContainsKey($item.id)) { $rawBonus = [double]$bonusMap[$item.id] }
    $softenedBonus = [Math]::Sqrt([Math]::Max(0.0, $rawBonus)) * 1.75
    $antiPenalty = [Math]::Sqrt([Math]::Max(0.0, -$rawBonus)) * 1.35
    $signatureBonus = Get-SignatureBonus $data $userNormalized $item
    $adjustment = Get-TeamAdjustment $data $item
    $adjustedDistance = [Math]::Max(0.0, $distance - $softenedBonus - $signatureBonus - $adjustment.intensityCompensation - $adjustment.popularityBias + $antiPenalty)
    $baseSimilarity = [Math]::Max(0.0, 1 - $adjustedDistance / $weightedMaxDistance)
    $similarity = [Math]::Min(1.0, $baseSimilarity * $adjustment.resultWeight)
    $results += [PSCustomObject]@{ id = $item.id; label = $item.label; similarity = $similarity }
  }
  return $results | Sort-Object similarity -Descending
}

$counts = @{}
foreach ($team in $json.teams) { $counts[$team.label] = 0 }
$iterations = 3000
for ($iter = 0; $iter -lt $iterations; $iter++) {
  $answers = @()
  foreach ($q in $json.questions) { $answers += (Get-Random -Minimum 0 -Maximum $q.options.Count) }
  $normalized = Get-NormalizedScores $json $answers @() @()
  $bonusMap = Get-TeamBonuses $json $answers @() @()
  $matches = Get-Matches $json $json.teams $normalized $bonusMap
  $top = $matches[0].label
  $counts[$top] = [int]$counts[$top] + 1
}

$counts.GetEnumerator() |
  Sort-Object Value -Descending |
  ForEach-Object { [PSCustomObject]@{ Team = $_.Key; Probability = [Math]::Round(100.0 * $_.Value / $iterations, 2) } } |
  Format-Table -AutoSize | Out-String -Width 220
