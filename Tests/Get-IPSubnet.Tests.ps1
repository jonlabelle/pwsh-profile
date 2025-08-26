Describe 'Get-IPSubnet function' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $func = Join-Path -Path (Join-Path -Path $root -ChildPath 'Functions') -ChildPath 'Get-IPSubnet.ps1'
        . $func
    }

    It 'calculates a /24 correctly' {
        $res = Get-IPSubnet -CIDR '192.168.0.0/24'
        $res.CIDR | Should -Be '192.168.0.0/24'
        $res.PrefixLength | Should -Be 24
        $res.IPcount | Should -Be 256
        $res.Subnet | Should -Be '192.168.0.0'
        $res.Broadcast | Should -Be '192.168.0.255'
    }

    It 'GetIParray returns all addresses for small subnets' {
        $arr = (Get-IPSubnet -CIDR '192.168.99.56/30').GetIParray()
        $arr | Should -Be @('192.168.99.56','192.168.99.57','192.168.99.58','192.168.99.59')
    }

    It 'Compare method works for addresses inside subnet' {
        $obj = Get-IPSubnet -CIDR '192.168.99.56/28'
        $obj.Compare('192.168.99.50') | Should -BeTrue
    }
}
