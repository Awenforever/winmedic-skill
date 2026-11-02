#Requires -Version 5.1
BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repo 'engine\probes\media.ps1')
}

Describe '媒体时间偏移计算' {
    It '正常时间返回接近 0 的偏移' {
        $ft = Get-Date '2026-11-01 13:01:49'
        $off = Convert-MediaOffsetHours -FileTime $ft -MetaText '2026/11/1 13:01:00'
        [math]::Abs([double]$off) | Should -BeLessThan 0.1
    }
    It '元数据 +8 小时能识别' {
        $ft = Get-Date '2026-11-01 13:01:49'
        $off = Convert-MediaOffsetHours -FileTime $ft -MetaText '2026/11/1 21:01:00'
        [double]$off | Should -BeGreaterThan 7
    }
    It '无法解析返回 null' {
        $ft = Get-Date
        Convert-MediaOffsetHours -FileTime $ft -MetaText '' | Should -BeNullOrEmpty
        Convert-MediaOffsetHours -FileTime $ft -MetaText 'not-a-date' | Should -BeNullOrEmpty
    }
}

Describe 'MP4 自解析' {
    BeforeAll {
        function New-BeBox([string]$Type, [byte[]]$Payload) {
            $size = 8 + $Payload.Length
            $b = New-Object byte[] $size
            $b[0] = [byte](($size -shr 24) -band 0xFF); $b[1] = [byte](($size -shr 16) -band 0xFF)
            $b[2] = [byte](($size -shr 8) -band 0xFF); $b[3] = [byte]($size -band 0xFF)
            [Text.Encoding]::ASCII.GetBytes($Type).CopyTo($b, 4)
            $Payload.CopyTo($b, 8)
            return $b
        }
    }
    It '从 mdat 之后的 moov 读出 creation_time' {
        $utc = [datetime]::SpecifyKind([datetime]::Parse('2026-11-01 11:41:04'), 'Utc')
        $sec = [uint32]($utc - [datetime]'1904-01-01').TotalSeconds
        $payload = New-Object byte[] 100
        $payload[0] = 0; $payload[1] = 0; $payload[2] = 0; $payload[3] = 0
        $payload[4] = [byte](($sec -shr 24) -band 0xFF); $payload[5] = [byte](($sec -shr 16) -band 0xFF)
        $payload[6] = [byte](($sec -shr 8) -band 0xFF); $payload[7] = [byte]($sec -band 0xFF)
        $mvhd = New-BeBox 'mvhd' $payload
        $moov = New-BeBox 'moov' $mvhd
        $ftyp = New-BeBox 'ftyp' ([Text.Encoding]::ASCII.GetBytes('isom0000'))
        $mdat = New-BeBox 'mdat' ([byte[]](1,2,3,4))
        $all = New-Object byte[] ($ftyp.Length + $mdat.Length + $moov.Length)
        $ftyp.CopyTo($all, 0); $mdat.CopyTo($all, $ftyp.Length); $moov.CopyTo($all, $ftyp.Length + $mdat.Length)
        $f = Join-Path $TestDrive 'sample.mp4'
        [IO.File]::WriteAllBytes($f, $all)
        $r = Get-Mp4CreationTimeUtc -Path $f
        $r.ok | Should -BeTrue
        [math]::Abs(($r.utc - $utc).TotalSeconds) | Should -BeLessThan 2
    }
    It '无 moov 时返回 null' {
        $f = Join-Path $TestDrive 'nomp4.bin'
        [IO.File]::WriteAllBytes($f, [byte[]](0,0,0,8,65,66,67,68))
        Get-Mp4CreationTimeUtc -Path $f | Should -BeNullOrEmpty
    }
}

Describe '媒体时间探针' {
    It '空目录返回 0 样本而不是报错' {
        $tmp = Join-Path $TestDrive 'empty-media'
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $p = Get-MediaTimestampProbe -Paths @($tmp) -MaxFiles 5 -TimeBudgetSeconds 5
        $p.id | Should -Be 'probe.media-timestamps'
        $p.ok | Should -BeTrue
        [int]$p.data.sampled | Should -Be 0
        [int]$p.data.shifted | Should -Be 0
    }
}