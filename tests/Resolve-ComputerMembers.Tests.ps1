BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..' 'gMSA Audit'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors) { throw ($parseErrors | Out-String) }
    $funcAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-ComputerMembers' }, $true)
    . ([ScriptBlock]::Create($funcAst.Extent.Text))
}

Describe 'Resolve-ComputerMembers' {
    It 'returns unique computer names from nested group hierarchy' {
        $directory = @{
            'CN=GroupA,DC=example,DC=com' = @{ ObjectClass = 'group'; Members = @('CN=GroupB,DC=example,DC=com','CN=Comp1,DC=example,DC=com','CN=Comp2,DC=example,DC=com') }
            'CN=GroupB,DC=example,DC=com' = @{ ObjectClass = 'group'; Members = @('CN=GroupC,DC=example,DC=com','CN=Comp2,DC=example,DC=com') }
            'CN=GroupC,DC=example,DC=com' = @{ ObjectClass = 'group'; Members = @('CN=Comp3,DC=example,DC=com') }
            'CN=Comp1,DC=example,DC=com' = @{ ObjectClass = 'computer'; DNSHostName = 'comp1.example.com' }
            'CN=Comp2,DC=example,DC=com' = @{ ObjectClass = 'computer'; DNSHostName = 'comp2.example.com' }
            'CN=Comp3,DC=example,DC=com' = @{ ObjectClass = 'computer'; DNSHostName = 'comp3.example.com' }
        }

        Mock Get-ADObject {
            param($Identity)
            if ($Identity -isnot [string]) { $Identity = $Identity.DistinguishedName }
            $entry = $directory[$Identity]
            [pscustomobject]@{
                DistinguishedName = $Identity
                objectClass = $entry.ObjectClass
            }
        }

        Mock Get-ADGroupMember {
            param($Identity)
            $directory[$Identity].Members
        }

        Mock Get-ADComputer {
            param($Identity)
            $entry = $directory[$Identity]
            [pscustomobject]@{
                DNSHostName = $entry.DNSHostName
                Name = $entry.DNSHostName.Split('.')[0]
            }
        }

        $results = Resolve-ComputerMembers -Principals @('CN=GroupA,DC=example,DC=com')

        $results | Should -Be @('comp1.example.com','comp2.example.com','comp3.example.com')
    }
}
