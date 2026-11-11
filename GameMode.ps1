# GAME MODE / ИГРОВОЙ РЕЖИМ  v2 - portable
# Игры: Steam + Epic Games + локальные/торрент-игры. Чистый рабочий стол на время игры. Всё возвращается при выходе.
# Games: Steam + Epic Games + local/torrent games. Clean desktop while gaming. Everything is restored on exit.
param([string]$Preview = '', [switch]$PreviewSettings, [switch]$Restore)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$ru = ((Get-UICulture).Name -like 'ru*') -or ((Get-Culture).Name -like 'ru*')
function L($r, $e) { if ($ru) { $r } else { $e } }

$TelegramUrl  = 'https://t.me/baqdesignTeam'
$TelegramText = 'Telegram'

# ---------------- C# helpers ----------------
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text; using System.Collections.Generic;
public class AppInfoReader {
    static string[] strs;
    public static List<string[]> Read(string path) {
        var res = new List<string[]>();
        var b = File.ReadAllBytes(path);
        long strOff = BitConverter.ToInt64(b,8);
        int p = (int)strOff; uint cnt = BitConverter.ToUInt32(b,p); p += 4;
        strs = new string[cnt];
        for (uint i=0;i<cnt;i++){ int s=p; while(b[p]!=0)p++; strs[i]=Encoding.UTF8.GetString(b,s,p-s); p++; }
        p = 16;
        while (p < strOff) {
            uint appid = BitConverter.ToUInt32(b,p); p+=4;
            if (appid==0) break;
            uint size = BitConverter.ToUInt32(b,p); p+=4;
            int end = p + (int)size;
            int q = p + 4+4+8+20+4+20;
            string name=null, type=null;
            try { int qq=q; Walk(b, ref qq, new List<string>(), ref name, ref type); } catch {}
            res.Add(new string[]{ appid.ToString(), name, type });
            p = end;
        }
        return res;
    }
    static void Walk(byte[] b, ref int p, List<string> path, ref string name, ref string type) {
        while (true) {
            byte t = b[p++];
            if (t==8) return;
            int ki = BitConverter.ToInt32(b,p); p+=4;
            string key = strs[ki];
            if (t==0) { path.Add(key); Walk(b, ref p, path, ref name, ref type); path.RemoveAt(path.Count-1); }
            else if (t==1) { int s=p; while(b[p]!=0)p++; string v=Encoding.UTF8.GetString(b,s,p-s); p++;
                if (path.Count==2 && path[1]=="common") { if(key=="name") name=v; else if(key=="type") type=v; } }
            else if (t==2||t==3||t==4||t==6) p+=4;
            else if (t==7||t==10) p+=8;
            else if (t==5) { while(!(b[p]==0&&b[p+1]==0))p+=2; p+=2; }
            else throw new Exception("bad type "+t);
        }
    }
}
public class Shell {
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern IntPtr FindWindow(string cls, string wnd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string cls, string wnd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);

    public static void SetTaskbar(bool show) {
        int cmd = show ? 5 : 0;
        IntPtr h = FindWindow("Shell_TrayWnd", null);
        if (h != IntPtr.Zero) ShowWindow(h, cmd);
        IntPtr s = IntPtr.Zero;
        while ((s = FindWindowEx(IntPtr.Zero, s, "Shell_SecondaryTrayWnd", null)) != IntPtr.Zero) ShowWindow(s, cmd);
    }
    static IntPtr DesktopList() {
        IntPtr def = FindWindowEx(FindWindow("Progman", null), IntPtr.Zero, "SHELLDLL_DefView", null);
        if (def == IntPtr.Zero) {
            IntPtr w = IntPtr.Zero;
            while ((w = FindWindowEx(IntPtr.Zero, w, "WorkerW", null)) != IntPtr.Zero) {
                def = FindWindowEx(w, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (def != IntPtr.Zero) break;
            }
        }
        if (def == IntPtr.Zero) return IntPtr.Zero;
        return FindWindowEx(def, IntPtr.Zero, "SysListView32", null);
    }
    public static void SetIcons(bool show) { IntPtr l = DesktopList(); if (l != IntPtr.Zero) ShowWindow(l, show ? 5 : 0); }
    public static bool IconsVisible() { IntPtr l = DesktopList(); return l != IntPtr.Zero && IsWindowVisible(l); }
    public static bool TaskbarVisible() { IntPtr h = FindWindow("Shell_TrayWnd", null); return h != IntPtr.Zero && IsWindowVisible(h); }
}
'@

# Аварийное восстановление: GameMode.ps1 -Restore  (вернуть значки рабочего стола и панель задач)
if ($Restore) { [Shell]::SetTaskbar($true); [Shell]::SetIcons($true); exit }

# ---------------- settings ----------------
$cfgDir  = Join-Path $env:APPDATA 'GameMode'
$cfgPath = Join-Path $cfgDir 'settings.json'
$cfg = [ordered]@{
    ConfirmStart = $true; CloseApps = 'ask'; PauseServices = $true
    HideTaskbar = $true;  HideIcons = $true
    ShowSteam = $true; ShowEpic = $true; ShowLocal = $true; ShowNotInstalled = $true; AutoScan = $true
    ExtraFolders = @(); Hidden = @()
    CloseList = @('firefox','chrome','msedge','brave','opera','Telegram','Discord','Spotify','OneDrive','Teams','Skype',
                  'Slack','Dropbox','Notion','ChatGPT','Viber','WhatsApp')
}
if (Test-Path $cfgPath) {
    try {
        $saved = [IO.File]::ReadAllText($cfgPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($k in @($cfg.Keys)) { if ($null -ne $saved.$k) { $cfg[$k] = $saved.$k } }
    } catch {}
}
foreach ($k in 'ExtraFolders','Hidden','CloseList') { $cfg[$k] = @($cfg[$k]) }
function Save-Config {
    try { New-Item $cfgDir -ItemType Directory -Force | Out-Null
          [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $true)) } catch {}
}

# ---------------- admin (only for pausing services) ----------------
if (-not $Preview) {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
        exit
    }
}

# ---------------- find Steam ----------------
$steam = $null
foreach ($k in 'HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam') {
    $v = Get-ItemProperty $k -ErrorAction SilentlyContinue
    $p = $null
    if ($v.SteamPath) { $p = $v.SteamPath } elseif ($v.InstallPath) { $p = $v.InstallPath }
    if ($p) { $p = $p -replace '/','\'; if (Test-Path "$p\steam.exe") { $steam = $p; break } }
}
$cache = if ($steam) { "$steam\appcache\librarycache" } else { '' }
$epicDir = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"

# ---------------- helpers ----------------
function Set-DB($c) { $c.GetType().GetProperty('DoubleBuffered',[Reflection.BindingFlags]'Instance,NonPublic').SetValue($c,$true,$null) }
function Load-Img($path) {
    if ($path -and (Test-Path $path)) {
        try { $ms = New-Object IO.MemoryStream (,[IO.File]::ReadAllBytes($path)); return [Drawing.Image]::FromStream($ms) } catch {}
    }
    return $null
}
function Find-Cover($appid) {
    if (-not $cache) { return $null }
    $p = "$cache\$appid\library_600x900.jpg"
    if (Test-Path $p) { return Load-Img $p }
    $h = Get-ChildItem "$cache\$appid" -Recurse -Filter 'header.jpg' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($h) { return Load-Img $h.FullName }
    return $null
}
function Round-Path($x,$y,$w,$h,$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $r*2
    $p.AddArc($x,$y,$d,$d,180,90); $p.AddArc($x+$w-$d,$y,$d,$d,270,90)
    $p.AddArc($x+$w-$d,$y+$h-$d,$d,$d,0,90); $p.AddArc($x,$y+$h-$d,$d,$d,90,90)
    $p.CloseFigure(); return $p
}
# Запуск через проводник: игра стартует с обычными правами пользователя, а не от администратора
function Open-Target($t) {
    try { Start-Process explorer.exe -ArgumentList "`"$t`"" } catch { try { Start-Process $t } catch {} }
}

# ---------------- libraries ----------------
function Get-SteamItems {
    $res = @()
    if (-not $steam) { return $res }
    $inst = @{}
    $libs = @($steam)
    $vdf = "$steam\steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        $libs += [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }
    }
    foreach ($l in ($libs | Select-Object -Unique)) {
        Get-ChildItem "$l\steamapps" -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue | ForEach-Object {
            $t = Get-Content $_.FullName -Raw
            $a = [regex]::Match($t,'"appid"\s+"(\d+)"').Groups[1].Value
            $n = [regex]::Match($t,'"name"\s+"([^"]+)"').Groups[1].Value
            if ($a -and $n -and $a -ne '228980' -and $n -notmatch 'Steamworks|Proton|Runtime') { $inst[$a] = $n }
        }
    }
    $list = @()
    try {
        $cacheIds = @(Get-ChildItem $cache -Directory | ForEach-Object Name)
        foreach ($r in [AppInfoReader]::Read("$steam\appcache\appinfo.vdf")) {
            if ($r[2] -eq 'game' -and $r[1] -and $r[0] -ne '730' -and ($cacheIds -contains $r[0])) {
                $list += [pscustomobject]@{ Id=$r[0]; Name=$r[1]; Installed=$inst.ContainsKey($r[0]) }
            }
        }
    } catch {}
    foreach ($k in $inst.Keys) {
        if ($k -ne '730' -and -not ($list | Where-Object Id -eq $k)) { $list += [pscustomobject]@{ Id=$k; Name=$inst[$k]; Installed=$true } }
    }
    # pinned: CS2 + Steam client
    $res += [pscustomobject]@{ Key='steam:730'; Name='Counter-Strike 2'; Source='steam'; Id='730'; Installed=$inst.ContainsKey('730')
        Target=$(if ($inst.ContainsKey('730')) { 'steam://rungameid/730' } else { 'steam://install/730' }); IconPath=$null
        Accent=[Drawing.Color]::FromArgb(255,150,30); Pinned=$true; IsCs2=$true; Order=0 }
    $res += [pscustomobject]@{ Key='steam:client'; Name='Steam'; Source='steam'; Id=$null; Installed=$true
        Target="$steam\steam.exe"; IconPath="$steam\steam.exe"
        Accent=[Drawing.Color]::FromArgb(70,150,230); Pinned=$true; IsCs2=$false; Order=1 }
    foreach ($g in $list) {
        $res += [pscustomobject]@{ Key="steam:$($g.Id)"; Name=$g.Name; Source='steam'; Id=$g.Id; Installed=$g.Installed
            Target=$(if ($g.Installed) { "steam://rungameid/$($g.Id)" } else { "steam://install/$($g.Id)" }); IconPath=$null
            Accent=$(if ($g.Installed) { [Drawing.Color]::FromArgb(110,200,255) } else { [Drawing.Color]::FromArgb(150,150,170) })
            Pinned=$false; IsCs2=$false; Order=5 }
    }
    return $res
}

function Get-EpicItems {
    $res = @()
    if (Test-Path $epicDir) {
        foreach ($f in (Get-ChildItem $epicDir -Filter *.item -ErrorAction SilentlyContinue)) {
            try { $j = [IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
            if (-not $j.DisplayName) { continue }
            $cats = @($j.AppCategories)
            if (-not ($cats -contains 'games')) { continue }
            if ($cats -contains 'addons' -or $cats -contains 'plugins' -or $j.bIsIncompleteInstall) { continue }
            $exe = $null
            if ($j.LaunchExecutable) { $exe = Join-Path $j.InstallLocation $j.LaunchExecutable }
            $name = ($j.DisplayName -replace "[®™]",'').Trim()
            $uri = "com.epicgames.launcher://apps/$($j.CatalogNamespace)%3A$($j.CatalogItemId)%3A$($j.AppName)?action=launch&silent=true"
            $res += [pscustomobject]@{ Key="epic:$($j.AppName)"; Name=$name; Source='epic'; Id=$null; Installed=$true
                Target=$uri; IconPath=$exe; Accent=[Drawing.Color]::FromArgb(180,190,210); Pinned=$false; IsCs2=$false; Order=4 }
        }
    }
    foreach ($lp in @("${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe",
                      "${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe")) {
        if (Test-Path $lp) {
            $res += [pscustomobject]@{ Key='epic:client'; Name='Epic Games'; Source='epic'; Id=$null; Installed=$true
                Target=$lp; IconPath=$lp; Accent=[Drawing.Color]::FromArgb(180,190,210); Pinned=$true; IsCs2=$false; Order=2 }
            break
        }
    }
    return $res
}

function Clean-Name($n) {
    $n = $n -replace '\[[^\]]*\]|\([^\)]*\)',''
    $n = $n -replace '(?i)[\s\._-]+v?\d+(\.\d+){2,}.*$',''
    if ($n -notmatch '\s') { $n = $n -replace '[\._]',' ' } else { $n = $n -replace '_',' ' }
    $n = $n -replace '(?i)\b(repack|fitgirl|gog|portable|multi\d*|build\s*\d+)\b',''
    return ($n -replace '\s{2,}',' ').Trim(' ','-','.')
}
function Test-FolderSize($dir, $bytes) {
    $sum = 0; $n = 0
    try {
        foreach ($f in [IO.Directory]::EnumerateFiles($dir,'*',[IO.SearchOption]::AllDirectories)) {
            try { $sum += (New-Object IO.FileInfo $f).Length } catch {}
            if ($sum -ge $bytes) { return $true }
            if (++$n -gt 20000) { return $false }   # много мелких файлов - это не игра (проекты, node_modules)
        }
    } catch {}
    return ($sum -ge $bytes)
}
function Find-MainExe($dir) {
    $bad = '(?i)unins|setup|install|redist|dxsetup|dotnet|vcredist|crash|report|helper|updater|bootstrap|webview|cef|easyanticheat|battleye|benchmark|7z|winrar|launcherhelper'
    $exes = @(Get-ChildItem $dir.FullName -Filter *.exe -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $bad })
    if ($exes.Count -eq 0) { return $null }
    $key = ($dir.Name -replace '[^A-Za-z0-9]','').ToLower()
    $m = $exes | Where-Object { $b = ($_.BaseName -replace '[^A-Za-z0-9]','').ToLower(); $b.Length -ge 3 -and $key.Contains($b) } | Sort-Object Length -Descending | Select-Object -First 1
    if ($m) { return $m }
    return ($exes | Sort-Object Length -Descending | Select-Object -First 1)
}
function Get-LocalRoots {
    $roots = @()
    if ($cfg.AutoScan) {
        foreach ($d in [IO.DriveInfo]::GetDrives()) {
            if ($d.DriveType -eq 'Fixed' -and $d.IsReady) {
                foreach ($n in 'Games','Game','Игры','Torrent','Torrents','Торренты') { $p = Join-Path $d.RootDirectory.FullName $n; if (Test-Path $p) { $roots += $p } }
            }
        }
        $dl = Join-Path $env:USERPROFILE 'Downloads'; if (Test-Path $dl) { $roots += $dl }
        # qBittorrent: папки загрузок
        $ini = Join-Path $env:APPDATA 'qBittorrent\qBittorrent.ini'
        if (Test-Path $ini) {
            foreach ($line in (Get-Content $ini -ErrorAction SilentlyContinue)) {
                if ($line -match '^(Session\\DefaultSavePath|Downloads\\SavePath|Downloads\\SavePathHistory|SavePathHistory)=(.*)$') {
                    foreach ($pp in ($Matches[2] -replace '\\\\','\' -split ',')) { $pp = $pp.Trim().Trim('"'); if ($pp -and (Test-Path $pp)) { $roots += $pp } }
                }
            }
        }
        $bt = Join-Path $env:LOCALAPPDATA 'qBittorrent\BT_backup'
        if (Test-Path $bt) {
            foreach ($fr in (Get-ChildItem $bt -Filter *.fastresume -ErrorAction SilentlyContinue)) {
                try {
                    $b = [IO.File]::ReadAllBytes($fr.FullName)
                    $s = [Text.Encoding]::GetEncoding(28591).GetString($b)
                    $m = [regex]::Match($s,'save_path(\d+):')
                    if ($m.Success) {
                        $pp = [Text.Encoding]::UTF8.GetString($b, $m.Index+$m.Length, [int]$m.Groups[1].Value) -replace '/','\'
                        if ($pp -and (Test-Path $pp)) { $roots += $pp }
                    }
                } catch {}
            }
        }
    }
    foreach ($x in @($cfg.ExtraFolders)) { if ($x -and (Test-Path $x)) { $roots += $x } }
    return @($roots | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)
}
function Get-LocalItems {
    $res = @()
    $skip = @()
    if ($steam) { $skip += "$steam\steamapps".ToLower() }
    $skip += "${env:ProgramFiles}\Epic Games".ToLower()
    $seen = @{}
    foreach ($root in (Get-LocalRoots)) {
        if ($skip | Where-Object { $root.ToLower().StartsWith($_) }) { continue }
        foreach ($dir in (Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)) {
            if ($dir.Name -match '(?i)^(telegram|\$|system volume|windows|program files|node_modules|\.)') { continue }
            if (-not (Test-FolderSize $dir.FullName 300MB)) { continue }
            $exe = Find-MainExe $dir
            if (-not $exe) { continue }
            $k = $exe.FullName.ToLower()
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $nm = Clean-Name $dir.Name
            if (-not $nm) { $nm = $dir.Name }
            $res += [pscustomobject]@{ Key="local:$k"; Name=$nm; Source='local'; Id=$null; Installed=$true
                Target=$exe.FullName; IconPath=$exe.FullName; Accent=[Drawing.Color]::FromArgb(120,220,160); Pinned=$false; IsCs2=$false; Order=4 }
        }
    }
    return $res
}
function Get-AllItems {
    $all = @()
    if ($cfg.ShowSteam)  { $all += Get-SteamItems }
    if ($cfg.ShowEpic)   { $all += Get-EpicItems }
    if ($cfg.ShowLocal)  { $all += Get-LocalItems }
    $hidden = @($cfg.Hidden)
    $all = @($all | Where-Object { $_.Pinned -or ($hidden -notcontains $_.Key) })
    if (-not $cfg.ShowNotInstalled) { $all = @($all | Where-Object { $_.Installed }) }
    # CS2 / Steam / Epic first, then installed (A-Z), then not installed (A-Z)
    return @($all | Sort-Object @{Expression={ if ($_.Pinned) { 0 } else { 1 } }}, Order, @{Expression={ -not $_.Installed }}, Name)
}

# ---------------- card rendering (once, cached as bitmap) ----------------
$badgeText = (L '⬇ Не установлена' '⬇ Not installed')
function Render-Card($it) {
    $w = 230; $h = 340
    $bmp = New-Object Drawing.Bitmap $w, $h
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.TextRenderingHint = 'ClearTypeGridFit'
    $path = Round-Path 8 8 ($w-17) ($h-17) 20
    $g.SetClip($path)
    $rect = New-Object Drawing.Rectangle 8,8,($w-16),($h-16)
    $img = $null; $icon = $null
    if ($it.Source -eq 'steam' -and $it.Id) { $img = Find-Cover $it.Id }
    if (-not $img -and $it.IconPath -and (Test-Path $it.IconPath)) { try { $icon = [Drawing.Icon]::ExtractAssociatedIcon($it.IconPath).ToBitmap() } catch {} }
    if ($it.Id -eq '730' -and -not $img -and -not $icon) { }
    if ($img) {
        $sc = [Math]::Max($rect.Width/$img.Width, $rect.Height/$img.Height)
        $sw = $rect.Width/$sc; $sh = $rect.Height/$sc
        $g.DrawImage($img, $rect, [single](($img.Width-$sw)/2), [single](($img.Height-$sh)/2), [single]$sw, [single]$sh, [Drawing.GraphicsUnit]::Pixel)
        $img.Dispose()
    } else {
        $b = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, ([Drawing.Color]::FromArgb(48,56,80)), ([Drawing.Color]::FromArgb(22,26,40)), 60
        $g.FillRectangle($b,$rect)
        if ($icon) { $g.DrawImage($icon, [int]($w/2-44), [int]($h/2-92), 88, 88); $icon.Dispose() }
    }
    $ov = New-Object Drawing.Rectangle 8,($h-120),($w-16),112
    $g.FillRectangle((New-Object Drawing.Drawing2D.LinearGradientBrush $ov, ([Drawing.Color]::FromArgb(0,0,0,0)), ([Drawing.Color]::FromArgb(235,0,0,0)), 90), $ov)
    $f = New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)
    $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Far'
    $g.DrawString($it.Name, $f, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 16,($h-80),($w-32),62), $sf)
    if (-not $it.Installed) {
        $g.FillRectangle((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(120,0,0,0))),$rect)
        $bf = New-Object Drawing.Font('Segoe UI',9.5,[Drawing.FontStyle]::Bold)
        $bw = 160; $bx = [int](($w-$bw)/2); $by = 22
        $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(210,30,34,48))), (Round-Path $bx $by $bw 26 13))
        $bsf = New-Object Drawing.StringFormat; $bsf.Alignment = 'Center'; $bsf.LineAlignment = 'Center'
        $g.DrawString($badgeText, $bf, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF $bx,$by,$bw,26), $bsf)
    }
    if ($it.Source -ne 'steam' -and -not $it.Pinned -or $it.Key -eq 'epic:client') {
        $chip = if ($it.Source -eq 'epic') { 'EPIC' } else { (L 'ЛОКАЛЬНАЯ' 'LOCAL') }
        $cf = New-Object Drawing.Font('Segoe UI',8.5,[Drawing.FontStyle]::Bold)
        $cw = if ($it.Source -eq 'epic') { 52 } else { 82 }
        $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(220,20,24,36))), (Round-Path 20 20 $cw 22 11))
        $csf = New-Object Drawing.StringFormat; $csf.Alignment = 'Center'; $csf.LineAlignment = 'Center'
        $g.DrawString($chip, $cf, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 20,20,$cw,22), $csf)
    }
    $g.ResetClip()
    $g.DrawPath((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(70,255,255,255)), 1), $path)
    $g.Dispose()
    return $bmp
}

# ---------------- settings dialog ----------------
function Show-Settings($owner) {
    $dark = [Drawing.Color]::FromArgb(24,27,38); $field = [Drawing.Color]::FromArgb(40,45,62)
    $f = New-Object Windows.Forms.Form
    $f.Text = (L 'Настройки игрового режима' 'Game mode settings')
    $f.StartPosition = 'CenterParent'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.ShowInTaskbar = $false; $f.ClientSize = New-Object Drawing.Size(640,800)
    $f.BackColor = $dark; $f.ForeColor = 'White'; $f.Font = New-Object Drawing.Font('Segoe UI',10)
    $script:sy = 14
    function Sec($t) {
        $l = New-Object Windows.Forms.Label; $l.Text = $t; $l.AutoSize = $true
        $l.Font = New-Object Drawing.Font('Segoe UI',11.5,[Drawing.FontStyle]::Bold); $l.ForeColor = [Drawing.Color]::FromArgb(255,150,30)
        $l.Location = New-Object Drawing.Point(24,$script:sy); $f.Controls.Add($l); $script:sy += 32
    }
    function Chk($t,$v) {
        $c = New-Object Windows.Forms.CheckBox; $c.Text = $t; $c.Checked = [bool]$v; $c.AutoSize = $true
        $c.Location = New-Object Drawing.Point(30,$script:sy); $f.Controls.Add($c); $script:sy += 28; return $c
    }
    Sec (L 'Запуск' 'Start-up')
    $cbConfirm = Chk (L 'Спрашивать «Включить игровой режим?» при запуске' 'Ask "Turn on game mode?" on start') $cfg.ConfirmStart
    $lb = New-Object Windows.Forms.Label; $lb.Text = (L 'Закрывать фоновые программы:' 'Close background programs:'); $lb.AutoSize = $true
    $lb.Location = New-Object Drawing.Point(30,($script:sy+4)); $f.Controls.Add($lb)
    $cmb = New-Object Windows.Forms.ComboBox; $cmb.DropDownStyle = 'DropDownList'; $cmb.FlatStyle = 'Flat'; $cmb.BackColor = $field; $cmb.ForeColor = 'White'
    [void]$cmb.Items.AddRange(@((L 'Спрашивать каждый раз' 'Ask every time'), (L 'Всегда закрывать' 'Always close'), (L 'Не закрывать' 'Never close')))
    $cmb.SelectedIndex = @{ ask=0; always=1; never=2 }[[string]$cfg.CloseApps]
    $cmb.Location = New-Object Drawing.Point(300,$script:sy); $cmb.Width = 300; $f.Controls.Add($cmb); $script:sy += 38
    $cbServ = Chk (L 'Останавливать лишние службы Windows на время игры' 'Pause extra Windows services while gaming') $cfg.PauseServices
    $script:sy += 6
    Sec (L 'Экран' 'Screen')
    $cbTask = Chk (L 'Скрывать панель задач' 'Hide the taskbar') $cfg.HideTaskbar
    $cbIcons = Chk (L 'Скрывать значки рабочего стола (они только прячутся, не удаляются)' 'Hide desktop icons (only hidden, never deleted)') $cfg.HideIcons
    $script:sy += 6
    Sec (L 'Библиотека игр' 'Game library')
    $cbSteam = Chk 'Steam' $cfg.ShowSteam
    $cbEpic  = Chk 'Epic Games' $cfg.ShowEpic
    $cbLocal = Chk (L 'Локальные и торрент-игры' 'Local and torrent games') $cfg.ShowLocal
    $cbNot   = Chk (L 'Показывать нескачанные игры Steam' 'Show not-installed Steam games') $cfg.ShowNotInstalled
    $cbAuto  = Chk (L 'Искать игры автоматически (Games, Downloads, папки qBittorrent)' 'Auto-search for games (Games, Downloads, qBittorrent folders)') $cfg.AutoScan
    $script:sy += 4
    $l2 = New-Object Windows.Forms.Label; $l2.Text = (L 'Свои папки с играми (каждая игра в своей подпапке):' 'Your game folders (one sub-folder per game):'); $l2.AutoSize = $true
    $l2.Location = New-Object Drawing.Point(30,$script:sy); $f.Controls.Add($l2); $script:sy += 26
    $lst = New-Object Windows.Forms.ListBox; $lst.BackColor = $field; $lst.ForeColor = 'White'; $lst.BorderStyle = 'FixedSingle'
    $lst.Location = New-Object Drawing.Point(30,$script:sy); $lst.Size = New-Object Drawing.Size(450,86)
    foreach ($x in @($cfg.ExtraFolders)) { [void]$lst.Items.Add($x) }
    $f.Controls.Add($lst)
    function Btn($t,$x,$y,$w) {
        $b = New-Object Windows.Forms.Button; $b.Text = $t; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(90,100,130)
        $b.BackColor = $field; $b.ForeColor = 'White'; $b.Location = New-Object Drawing.Point($x,$y); $b.Size = New-Object Drawing.Size($w,34); $f.Controls.Add($b); return $b
    }
    $bAdd = Btn (L 'Добавить…' 'Add…') 490 $script:sy 120
    $bDel = Btn (L 'Удалить' 'Remove') 490 ($script:sy+42) 120
    $bAdd.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog($f) -eq 'OK') { [void]$lst.Items.Add($d.SelectedPath) } }.GetNewClosure())
    $bDel.Add_Click({ if ($lst.SelectedIndex -ge 0) { $lst.Items.RemoveAt($lst.SelectedIndex) } }.GetNewClosure())
    $script:sy += 100
    $hid = @($cfg.Hidden).Count
    $bHid = Btn ((L 'Показать скрытые игры' 'Unhide hidden games') + " ($hid)") 30 $script:sy 300
    $script:resetHidden = $false
    $hidMsg = (L 'Скрытые игры будут показаны' 'Hidden games will be shown')
    $bHid.Add_Click({ $script:resetHidden = $true; $bHid.Text = $hidMsg; $bHid.Enabled = $false }.GetNewClosure())
    $note = New-Object Windows.Forms.Label; $note.Text = (L '(правый клик по игре в панели - скрыть её)' '(right-click a game in the panel to hide it)')
    $note.AutoSize = $true; $note.ForeColor = [Drawing.Color]::FromArgb(150,160,180); $note.Location = New-Object Drawing.Point(340,($script:sy+8)); $f.Controls.Add($note)
    $script:sy += 50
    Sec (L 'Программы, которые закрываются (по одной в строке)' 'Programs to close (one per line)')
    $tb = New-Object Windows.Forms.TextBox; $tb.Multiline = $true; $tb.ScrollBars = 'Vertical'; $tb.BackColor = $field; $tb.ForeColor = 'White'; $tb.BorderStyle = 'FixedSingle'
    $tb.Location = New-Object Drawing.Point(30,$script:sy); $tb.Size = New-Object Drawing.Size(580,96)
    $tb.Text = (@($cfg.CloseList) -join "`r`n"); $f.Controls.Add($tb); $script:sy += 106
    $hint = New-Object Windows.Forms.Label; $hint.Text = (L 'Имена процессов без .exe. Службы и закрытие программ применяются при следующем запуске.' 'Process names without .exe. Services and closing apply on next start.')
    $hint.AutoSize = $true; $hint.ForeColor = [Drawing.Color]::FromArgb(150,160,180); $hint.Location = New-Object Drawing.Point(30,$script:sy); $f.Controls.Add($hint)

    $ok = Btn (L 'Сохранить' 'Save') 380 750 110
    $ok.BackColor = [Drawing.Color]::FromArgb(40,165,235); $ok.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(40,165,235)
    $cancel = Btn (L 'Отмена' 'Cancel') 500 750 110
    $ok.DialogResult = 'OK'; $cancel.DialogResult = 'Cancel'; $f.AcceptButton = $ok; $f.CancelButton = $cancel

    if ($PreviewSettings -and $Preview) {
        $f.StartPosition = 'Manual'; $f.Location = New-Object Drawing.Point(([int](($owner.Width-640)/2)),([int](($owner.Height-800)/2)))
        $f.TopMost = $true; $f.Show(); $f.Activate()
        1..10 | ForEach-Object { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 120 }
        $scr0 = [Windows.Forms.Screen]::PrimaryScreen.Bounds
        $shot = New-Object Drawing.Bitmap $scr0.Width, $scr0.Height
        $sg = [Drawing.Graphics]::FromImage($shot); $sg.CopyFromScreen($scr0.Location, [Drawing.Point]::Empty, $scr0.Size)
        $shot.Save(($Preview -replace '\.png$','_settings.png'), [Drawing.Imaging.ImageFormat]::Png)
        $f.Close(); return $false
    }
    if ($f.ShowDialog($owner) -ne 'OK') { return $false }

    $cfg.ConfirmStart = $cbConfirm.Checked
    $cfg.CloseApps = @('ask','always','never')[$cmb.SelectedIndex]
    $cfg.PauseServices = $cbServ.Checked
    $cfg.HideTaskbar = $cbTask.Checked; $cfg.HideIcons = $cbIcons.Checked
    $cfg.ShowSteam = $cbSteam.Checked; $cfg.ShowEpic = $cbEpic.Checked; $cfg.ShowLocal = $cbLocal.Checked
    $cfg.ShowNotInstalled = $cbNot.Checked; $cfg.AutoScan = $cbAuto.Checked
    $cfg.ExtraFolders = @($lst.Items | ForEach-Object { [string]$_ })
    $cfg.CloseList = @($tb.Text -split "[\r\n,;]+" | ForEach-Object { $_.Trim() -replace '\.exe$','' } | Where-Object { $_ })
    if ($script:resetHidden) { $cfg.Hidden = @() }
    Save-Config
    return $true
}

# ---------------- start: confirmations ----------------
$running = @()
$doClose = $false
if (-not $Preview) {
    if ($cfg.ConfirmStart) {
        $q = (L "Включить игровой режим?`n`nВременно будут скрыты значки рабочего стола и панель задач (значки не удаляются), остановлены лишние службы." "Turn on game mode?`n`nDesktop icons and the taskbar will be hidden for a while (icons are not deleted) and some extra services paused.")
        if ([Windows.Forms.MessageBox]::Show($q, (L 'Игровой режим' 'Game Mode'), 'YesNo', 'Question') -ne 'Yes') { exit }
    }
    if (@($cfg.CloseList).Count -gt 0) { $running = @(Get-Process -Name @($cfg.CloseList) -ErrorAction SilentlyContinue) }
    if ($running.Count -gt 0 -and $cfg.CloseApps -ne 'never') {
        if ($cfg.CloseApps -eq 'always') { $doClose = $true }
        else {
            $names = ($running | Group-Object Name | ForEach-Object { $_.Name }) -join ', '
            $q = (L "Закрыть все эти программы для максимального FPS?`n`n$names`n`nНесохранённые данные в них пропадут." "Close all these programs for maximum FPS?`n`n$names`n`nUnsaved data in them will be lost.")
            if ([Windows.Forms.MessageBox]::Show($q, (L 'Закрыть программы?' 'Close programs?'), 'YesNo', 'Question') -eq 'Yes') { $doClose = $true }
        }
    }
}

$stopped = @(); $prevPlan = $null
$services = @('WSearch','SysMain','DiagTrack','Spooler','Fax','MapsBroker')
try {
    if (-not $Preview) {
        if ($doClose) { $running | Stop-Process -Force -ErrorAction SilentlyContinue }
        if ($cfg.PauseServices) {
            foreach ($s in $services) {
                $svc = Get-Service $s -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq 'Running') { Stop-Service $s -Force -ErrorAction SilentlyContinue; $stopped += $s }
            }
        }
        $m = [regex]::Match((powercfg /getactivescheme | Out-String), '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}')
        if ($m.Success) { $prevPlan = $m.Value }
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    }

    $script:items = @(Get-AllItems)
    foreach ($it in $script:items) { $it | Add-Member -NotePropertyName Bmp -NotePropertyValue (Render-Card $it) -Force }

    # ---------------- main window ----------------
    $scr = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Game Mode'; $form.FormBorderStyle = 'None'; $form.StartPosition = 'Manual'
    $form.Location = $scr.Location; $form.Size = $scr.Size
    $form.BackColor = [Drawing.Color]::FromArgb(10,12,18); $form.KeyPreview = $true
    Set-DB $form
    # выход ТОЛЬКО по кнопке (Esc / Alt+F4 отключены)
    $script:allowClose = $false
    $form.Add_FormClosing({ param($s,$e) if (-not $script:allowClose -and -not $Preview -and $e.CloseReason -ne 'WindowsShutDown') { $e.Cancel = $true } })

    # фон: арт CS2 с затемнением
    $bg = New-Object Drawing.Bitmap $scr.Width, $scr.Height
    $g = [Drawing.Graphics]::FromImage($bg)
    $g.Clear([Drawing.Color]::FromArgb(10,12,18))
    $hero = if ($cache) { Load-Img "$cache\730\library_hero.jpg" } else { $null }
    if (-not $hero -and $cache) {
        $any = Get-ChildItem $cache -Recurse -Filter 'library_hero.jpg' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($any) { $hero = Load-Img $any.FullName }
    }
    if ($hero) {
        $sc = [Math]::Max($scr.Width/$hero.Width, $scr.Height/$hero.Height)
        $sw = $scr.Width/$sc; $sh = $scr.Height/$sc
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($hero, (New-Object Drawing.Rectangle 0,0,$scr.Width,$scr.Height), [single](($hero.Width-$sw)/2), [single](($hero.Height-$sh)/2), [single]$sw, [single]$sh, [Drawing.GraphicsUnit]::Pixel)
    }
    $g.FillRectangle((New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.Rectangle 0,0,$scr.Width,$scr.Height), ([Drawing.Color]::FromArgb(215,8,10,16)), ([Drawing.Color]::FromArgb(250,8,10,16)), 90), 0, 0, $scr.Width, $scr.Height)
    $g.Dispose()
    $form.BackgroundImage = $bg; $form.BackgroundImageLayout = 'Stretch'

    $title = New-Object Windows.Forms.Label
    $title.Text = (L 'ИГРОВОЙ РЕЖИМ' 'GAME MODE'); $title.ForeColor = 'White'; $title.BackColor = 'Transparent'
    $title.Font = New-Object Drawing.Font('Segoe UI',30,[Drawing.FontStyle]::Bold)
    $title.AutoSize = $true; $title.Location = '70,40'; $form.Controls.Add($title)
    $sub = New-Object Windows.Forms.Label
    $sub.Text = (L 'Всё лишнее остановлено. Выберите игру.' 'Everything extra is paused. Pick a game.')
    $sub.ForeColor = [Drawing.Color]::FromArgb(160,170,190); $sub.BackColor = 'Transparent'; $sub.Font = New-Object Drawing.Font('Segoe UI',13)
    $sub.AutoSize = $true; $sub.Location = '74,106'; $form.Controls.Add($sub)

    # ---------- сетка игр: ОДИН элемент, рисует сам (без мерцания при прокрутке) ----------
    $view = New-Object Windows.Forms.Panel
    $view.Location = New-Object Drawing.Point(60,170)
    $view.Size = New-Object Drawing.Size(($scr.Width-120),($scr.Height-170-80))
    $view.BackColor = [Drawing.Color]::FromArgb(10,12,18)
    Set-DB $view
    $form.Controls.Add($view)

    $script:offset = 0.0; $script:target = 0.0; $script:maxOff = 0.0; $script:hover = -1
    $script:cols = 1; $script:padX = 0; $script:contentH = 0; $script:drag = $false; $script:lastLaunch = [DateTime]::MinValue
    $CW = 230; $CH = 340

    function Update-Layout {
        $script:cols = [Math]::Max(1, [int][Math]::Floor(($view.Width - 30) / $CW))
        $script:padX = [int](($view.Width - 30 - $script:cols * $CW) / 2) + 4
        $rows = [Math]::Ceiling($script:items.Count / $script:cols)
        $script:contentH = $rows * $CH + 24
        $script:maxOff = [Math]::Max(0, $script:contentH - $view.Height)
        $script:target = [Math]::Min($script:target, $script:maxOff); $script:offset = [Math]::Min($script:offset, $script:maxOff)
    }
    function Hit-Test($x,$y) {
        if ($x -ge $view.Width - 24) { return -1 }
        $cx = $x - $script:padX; $cy = $y + $script:offset - 8
        if ($cx -lt 0 -or $cy -lt 0) { return -1 }
        $col = [int][Math]::Floor($cx / $CW); $row = [int][Math]::Floor($cy / $CH)
        $ix = $cx - $col*$CW; $iy = $cy - $row*$CH
        if ($col -ge $script:cols -or $ix -lt 8 -or $ix -gt ($CW-8) -or $iy -lt 8 -or $iy -gt ($CH-8)) { return -1 }
        $i = $row * $script:cols + $col
        if ($i -lt $script:items.Count) { return $i } else { return -1 }
    }
    Update-Layout

    $emptyText = (L 'Игры не найдены. Откройте ⚙ Настройки и включите источники игр.' 'No games found. Open ⚙ Settings and enable game sources.')
    $view.Add_Paint({
        param($s,$e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
        $g.DrawImage($bg, (New-Object Drawing.Rectangle 0,0,$s.Width,$s.Height), $s.Left, $s.Top, $s.Width, $s.Height, [Drawing.GraphicsUnit]::Pixel)
        if ($script:items.Count -eq 0) {
            $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
            $g.DrawString($emptyText, (New-Object Drawing.Font('Segoe UI',14)), [Drawing.Brushes]::Gray, (New-Object Drawing.RectangleF 0,0,$s.Width,$s.Height), $sf)
            return
        }
        $off = $script:offset
        for ($i = 0; $i -lt $script:items.Count; $i++) {
            $col = $i % $script:cols; $row = [int][Math]::Floor($i / $script:cols)
            $x = $script:padX + $col*$CW; $y = [int]([Math]::Round(8 + $row*$CH - $off))
            if ($y + $CH -lt 0 -or $y -gt $s.Height) { continue }
            $g.DrawImageUnscaled($script:items[$i].Bmp, $x, $y)
            if ($i -eq $script:hover) {
                $path = Round-Path ($x+8) ($y+8) ($CW-17) ($CH-17) 20
                $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(36,255,255,255))), $path)
                $g.DrawPath((New-Object Drawing.Pen $script:items[$i].Accent, 4), $path)
            }
        }
        if ($script:maxOff -gt 0) {
            $th = [Math]::Max(50, $s.Height * $s.Height / $script:contentH)
            $ty = ($s.Height - $th) * ($off / $script:maxOff)
            $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(40,255,255,255))), (Round-Path ($s.Width-14) 0 8 $s.Height 4))
            $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(170,255,255,255))), (Round-Path ($s.Width-14) $ty 8 $th 4))
        }
    })
    function Set-ScrollFromY($y) {
        $th = [Math]::Max(50, $view.Height * $view.Height / $script:contentH)
        $r = ($y - $th/2) / [Math]::Max(1, ($view.Height - $th))
        $v = [Math]::Max(0, [Math]::Min($script:maxOff, $r * $script:maxOff))
        $script:target = $v; $script:offset = $v; $view.Invalidate()
    }
    $view.Add_MouseEnter({ $view.Focus() | Out-Null })
    $view.Add_MouseWheel({ param($s,$e) $script:target = [Math]::Max(0, [Math]::Min($script:maxOff, $script:target - $e.Delta * 0.9)) })
    $view.Add_MouseDown({ param($s,$e)
        if ($e.Button -eq 'Left' -and $e.X -ge $s.Width - 24 -and $script:maxOff -gt 0) { $script:drag = $true; Set-ScrollFromY $e.Y } })
    $view.Add_MouseMove({ param($s,$e)
        if ($script:drag) { Set-ScrollFromY $e.Y; return }
        $i = Hit-Test $e.X $e.Y
        if ($i -ne $script:hover) { $script:hover = $i; $s.Cursor = $(if ($i -ge 0) { 'Hand' } else { 'Default' }); $s.Invalidate() } })
    $view.Add_MouseLeave({ if ($script:hover -ne -1) { $script:hover = -1; $view.Invalidate() } })
    $ctx = New-Object Windows.Forms.ContextMenuStrip
    $ctxHide = $ctx.Items.Add((L 'Скрыть эту игру' 'Hide this game'))
    $script:ctxIdx = -1
    $ctxHide.Add_Click({
        $it = $script:items[$script:ctxIdx]
        if ($it -and -not $it.Pinned) {
            $cfg.Hidden = @($cfg.Hidden) + $it.Key; Save-Config
            $script:items = @($script:items | Where-Object { $_.Key -ne $it.Key }); $script:hover = -1
            Update-Layout; $view.Invalidate()
        } })
    $view.Add_MouseUp({ param($s,$e)
        $script:drag = $false
        $i = Hit-Test $e.X $e.Y
        if ($i -lt 0) { return }
        if ($e.Button -eq 'Right') { $script:ctxIdx = $i; if (-not $script:items[$i].Pinned) { $ctx.Show($s, $e.Location) } }
        elseif ($e.Button -eq 'Left') {
            if (([DateTime]::Now - $script:lastLaunch).TotalSeconds -lt 1.5) { return }
            $script:lastLaunch = [DateTime]::Now
            $it = $script:items[$i]
            Open-Target $it.Target
            if ($it.IsCs2) { $script:cs2done = $false }
        } })
    $form.Add_KeyDown({ param($s,$e)
        switch ($e.KeyCode) {
            'PageDown' { $script:target = [Math]::Min($script:maxOff, $script:target + $view.Height * 0.8) }
            'PageUp'   { $script:target = [Math]::Max(0, $script:target - $view.Height * 0.8) }
            'Down'     { $script:target = [Math]::Min($script:maxOff, $script:target + 120) }
            'Up'       { $script:target = [Math]::Max(0, $script:target - 120) }
            'Home'     { $script:target = 0 }
            'End'      { $script:target = $script:maxOff }
        } })

    # плавная прокрутка
    $anim = New-Object Windows.Forms.Timer; $anim.Interval = 15
    $anim.Add_Tick({
        $d = $script:target - $script:offset
        if ([Math]::Abs($d) -gt 0.5) { $script:offset += $d * 0.3; $view.Invalidate() }
        elseif ($d -ne 0) { $script:offset = $script:target; $view.Invalidate() }
    })
    $anim.Start()

    # ---------- кнопки-пилюли ----------
    function New-Pill($text,$w,$x,$y,$c1,$c2,$h1,$h2,$onClick) {
        $p = New-Object Windows.Forms.Panel
        $p.Size = New-Object Drawing.Size($w,56); $p.Location = New-Object Drawing.Point($x,$y); $p.Cursor = 'Hand'; $p.BackColor = 'Transparent'
        Set-DB $p
        $p.Tag = [pscustomobject]@{ Hover=$false; Text=$text; C1=$c1; C2=$c2; H1=$h1; H2=$h2 }
        $p.Add_Paint({
            param($s,$e)
            $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
            $t = $s.Tag
            $r = New-Object Drawing.Rectangle 2,2,($s.Width-5),($s.Height-5)
            $path = Round-Path 2 2 ($s.Width-5) ($s.Height-5) 26
            if ($t.Hover) { $a = $t.H1; $b = $t.H2 } else { $a = $t.C1; $b = $t.C2 }
            $g.FillPath((New-Object Drawing.Drawing2D.LinearGradientBrush $r, $a, $b, 90), $path)
            $g.DrawPath((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(90,255,255,255)),1.5), $path)
            $sf = New-Object Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
            $g.DrawString($t.Text, (New-Object Drawing.Font('Segoe UI',13,[Drawing.FontStyle]::Bold)), [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0,0,$s.Width,$s.Height), $sf)
        })
        $p.Add_MouseEnter({ param($s,$e) $s.Tag.Hover = $true; $s.Invalidate() })
        $p.Add_MouseLeave({ param($s,$e) $s.Tag.Hover = $false; $s.Invalidate() })
        $p.Add_Click($onClick)
        $form.Controls.Add($p); $p.BringToFront(); return $p
    }
    $exX = $scr.Width - 310 - 70
    $exit = New-Pill ("✕   " + (L 'Выйти из игрового режима' 'Exit game mode')) 310 $exX 44 `
        ([Drawing.Color]::FromArgb(230,60,70)) ([Drawing.Color]::FromArgb(160,25,45)) ([Drawing.Color]::FromArgb(255,90,90)) ([Drawing.Color]::FromArgb(200,30,50)) `
        { $script:allowClose = $true; $form.Close() }
    $setBtn = New-Pill ("⚙   " + (L 'Настройки' 'Settings')) 210 ($exX - 16 - 210) 44 `
        ([Drawing.Color]::FromArgb(70,78,105)) ([Drawing.Color]::FromArgb(40,46,66)) ([Drawing.Color]::FromArgb(95,105,140)) ([Drawing.Color]::FromArgb(58,66,92)) `
        {
            if (Show-Settings $form) {
                [Shell]::SetTaskbar(-not $cfg.HideTaskbar); [Shell]::SetIcons(-not $cfg.HideIcons)
                $old = $script:items
                $script:items = @(Get-AllItems)
                foreach ($it in $script:items) { $it | Add-Member -NotePropertyName Bmp -NotePropertyValue (Render-Card $it) -Force }
                foreach ($o in $old) { if ($o.Bmp) { $o.Bmp.Dispose() } }
                $script:hover = -1; $script:target = 0; $script:offset = 0
                Update-Layout; $view.Invalidate()
            }
        }

    # ---------- нижняя плашка (вместо панели задач) + Telegram ----------
    $hint = (L 'Игровой режим вкл.' 'Game mode on')
    $dockX = [int](($scr.Width - (520 + 16 + 190)) / 2)
    $dock = New-Object Windows.Forms.Panel
    $dock.Size = '520,48'; $dock.BackColor = 'Transparent'; $dock.Location = New-Object Drawing.Point($dockX,($scr.Height-62))
    Set-DB $dock; $dock.Tag = $hint
    $dock.Add_Paint({
        param($s,$e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
        $path = Round-Path 1 1 ($s.Width-3) ($s.Height-3) 24
        $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(200,20,24,36))), $path)
        $g.DrawPath((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(70,255,255,255)),1), $path)
        $now = Get-Date
        $f1 = New-Object Drawing.Font('Segoe UI',14,[Drawing.FontStyle]::Bold); $f2 = New-Object Drawing.Font('Segoe UI',10.5)
        $sf = New-Object Drawing.StringFormat; $sf.LineAlignment = 'Center'
        $g.DrawString($now.ToString('HH:mm'), $f1, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 24,0,90,$s.Height), $sf)
        $gray = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(170,180,200))
        $g.DrawString($now.ToString('d MMMM, dddd'), $f2, $gray, (New-Object Drawing.RectangleF 110,0,220,$s.Height), $sf)
        $sf.Alignment = 'Far'
        $g.DrawString($s.Tag, $f2, $gray, (New-Object Drawing.RectangleF 300,0,($s.Width-324),$s.Height), $sf)
    })
    $form.Controls.Add($dock); $dock.BringToFront()

    $tg = New-Object Windows.Forms.Panel
    $tg.Size = '190,48'; $tg.Cursor = 'Hand'; $tg.BackColor = 'Transparent'
    $tg.Location = New-Object Drawing.Point(($dockX + 520 + 16),($scr.Height-62))
    Set-DB $tg
    $tg.Tag = [pscustomobject]@{ Hover=$false; Text=$TelegramText; Url=$TelegramUrl }
    $tg.Add_Paint({
        param($s,$e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
        $path = Round-Path 1 1 ($s.Width-3) ($s.Height-3) 24
        $r = New-Object Drawing.Rectangle 1,1,($s.Width-3),($s.Height-3)
        if ($s.Tag.Hover) { $c1 = [Drawing.Color]::FromArgb(70,190,250); $c2 = [Drawing.Color]::FromArgb(20,130,210) }
        else { $c1 = [Drawing.Color]::FromArgb(40,165,235); $c2 = [Drawing.Color]::FromArgb(15,110,185) }
        $g.FillPath((New-Object Drawing.Drawing2D.LinearGradientBrush $r, $c1, $c2, 90), $path)
        $g.DrawPath((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(90,255,255,255)),1.2), $path)
        $pts = @( @(26,3), @(2,13), @(9,16), @(21,9), @(11,18), @(11,24), @(15,20), @(21,25) )
        $poly = [Drawing.PointF[]]($pts | ForEach-Object { New-Object Drawing.PointF ([single](22 + $_[0])), ([single](10 + $_[1])) })
        $g.FillPolygon([Drawing.Brushes]::White, $poly)
        $sf = New-Object Drawing.StringFormat; $sf.LineAlignment = 'Center'
        $g.DrawString($s.Tag.Text, (New-Object Drawing.Font('Segoe UI',12,[Drawing.FontStyle]::Bold)), [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 62,0,($s.Width-70),$s.Height), $sf)
    })
    $tg.Add_MouseEnter({ param($s,$e) $s.Tag.Hover = $true; $s.Invalidate() })
    $tg.Add_MouseLeave({ param($s,$e) $s.Tag.Hover = $false; $s.Invalidate() })
    $tg.Add_Click({ param($s,$e) Open-Target $s.Tag.Url })
    $form.Controls.Add($tg); $tg.BringToFront()

    # ---------- предпросмотр: сделать снимок и выйти, ничего не меняя ----------
    if ($Preview) {
        $form.TopMost = $true; $form.Show(); $form.Activate(); $form.BringToFront()
        1..10 | ForEach-Object { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 120 }
        if ($PreviewSettings) { [void](Show-Settings $form) }
        else {
            # прокрутим вниз, чтобы проверить сетку
            $script:target = [Math]::Min($script:maxOff, 700); 1..40 | ForEach-Object { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
            $script:hover = 3; $view.Invalidate(); [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 200
        }
        $shot = New-Object Drawing.Bitmap $scr.Width, $scr.Height
        $sg = [Drawing.Graphics]::FromImage($shot); $sg.CopyFromScreen($scr.Location, [Drawing.Point]::Empty, $scr.Size)
        if (-not $PreviewSettings) { $shot.Save($Preview, [Drawing.Imaging.ImageFormat]::Png) }
        $form.Close()
        $by = $script:items | Group-Object Source | ForEach-Object { "$($_.Name)=$($_.Count)" }
        "items: $($script:items.Count) ($($by -join ', ')); steam: $steam; maxOff=$($script:maxOff)"
        $script:items | Where-Object { $_.Source -ne 'steam' } | ForEach-Object { "  [$($_.Source)] $($_.Name)  ->  $($_.Target)" }
        return
    }

    # ---------- применить скрытие и показать панель ----------
    if ($cfg.HideTaskbar) { [Shell]::SetTaskbar($false) }
    if ($cfg.HideIcons)   { [Shell]::SetIcons($false) }

    $script:cs2done = $false
    $timer = New-Object Windows.Forms.Timer; $timer.Interval = 3000
    $timer.Add_Tick({
        if ($cfg.HideTaskbar) { [Shell]::SetTaskbar($false) }
        if ($cfg.HideIcons)   { [Shell]::SetIcons($false) }
        $dock.Invalidate()
        if (-not $script:cs2done) {
            $p = Get-Process cs2 -ErrorAction SilentlyContinue
            if ($p) { $p.PriorityClass = 'High'; $script:cs2done = $true }
        }
    })
    $timer.Start()

    [void]$form.ShowDialog()
}
finally {
    # ВОССТАНОВЛЕНИЕ: проводник не трогаем, значки не удаляем - только показываем обратно
    if (-not $Preview) {
        try { [Shell]::SetTaskbar($true) } catch {}
        try { [Shell]::SetIcons($true) } catch {}
        foreach ($s in $stopped) { Start-Service $s -ErrorAction SilentlyContinue }
        if ($prevPlan) { powercfg /setactive $prevPlan 2>$null }
    }
}
