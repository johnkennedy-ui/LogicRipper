$ErrorActionPreference = 'Stop'

Describe 'LogicRipper offline-only production boundary' {
    It 'does not contain banned live API commands in production code' {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
        $productionRoots = @(
            Join-Path $repoRoot 'src'
            Join-Path $repoRoot 'scripts'
        )
        $productionFiles = foreach ($root in $productionRoots) {
            if (Test-Path -LiteralPath $root) {
                Get-ChildItem -LiteralPath $root -Recurse -File |
                    Where-Object { $_.Extension -in @('.ps1','.psm1','.psd1','.xaml','.sh') }
            }
        }
        $productionFiles += Get-Item -LiteralPath (Join-Path $repoRoot 'build.ps1')

        $bannedPatterns = @(
            'Connect-AzAccount',
            '\bGet-Az[A-Za-z0-9]*\b',
            '\bNew-Az[A-Za-z0-9]*\b',
            '\bSet-Az[A-Za-z0-9]*\b',
            '\bRemove-Az[A-Za-z0-9]*\b',
            'Connect-MgGraph',
            '\bGet-Mg[A-Za-z0-9]*\b',
            'Invoke-MgGraphRequest',
            'Invoke-RestMethod',
            'Invoke-WebRequest',
            '\baz\s+login\b',
            '\baz\s+account\b',
            '\baz\s+deployment\b',
            'graph\.microsoft\.com',
            'management\.azure\.com'
        )

        $matches = foreach ($file in $productionFiles) {
            $text = Get-Content -Raw -LiteralPath $file.FullName
            foreach ($pattern in $bannedPatterns) {
                if ($text -match $pattern) {
                    [pscustomobject]@{ file = $file.FullName.Substring($repoRoot.Path.Length + 1); pattern = $pattern }
                }
            }
        }

        $matches | Should -BeNullOrEmpty
    }
}
