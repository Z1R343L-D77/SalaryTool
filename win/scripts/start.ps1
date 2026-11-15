#requires -Version 5.1
<#
    当月薪水到手计算器 —— 一键启动（独立桌面程序）

    行为：
      1. 检查 Rust / MSVC 编译环境；缺失时给出安装指引（或加 -Install 自动安装）
      2. 首次运行或源码有改动时，编译出原生 exe
      3. 直接启动 exe，不经过浏览器

    用法：
        start.bat                 双击：确保已编译最新版本，然后启动桌面程序
        start.bat -Dev            开发模式：启动热更新窗口（Tauri dev）
        start.bat -Rebuild        强制重新编译
        start.bat -Installer      额外生成安装包（.msi / .exe 安装程序）
        start.bat -Install        自动安装缺失的 Rust 与 VS 生成工具（需要管理员授权）
        start.bat -Reinstall      强制重新安装前端依赖
#>
param(
    [switch]$Dev,
    [switch]$Rebuild,
    [switch]$Installer,
    [switch]$Install,
    [switch]$Reinstall
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ProjectRoot

# Tauri 可能把 exe 重命名为 productName（SalaryTool.exe），两种都认
function Resolve-ExePath {
    $candidates = @(
        (Join-Path $ProjectRoot 'src-tauri\target\release\salarytool.exe'),
        (Join-Path $ProjectRoot 'src-tauri\target\release\SalaryTool.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

# rustup 刚装好时 PATH 还没刷新，把默认安装目录补进本次会话
$cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
if ((Test-Path -LiteralPath $cargoBin) -and ($env:Path -notlike "*$cargoBin*")) {
    $env:Path = "$cargoBin;$env:Path"
}

function Write-Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host "    $Text" -ForegroundColor DarkGray }
function Write-Warn([string]$Text) { Write-Host "!   $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host "x   $Text" -ForegroundColor Red }

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-NpmPath {
    foreach ($candidate in @('npm.cmd', 'npm')) {
        $found = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }
    return $null
}

function Find-Cargo {
    $found = Get-Command cargo -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    # rustup 刚安装完时 PATH 可能还没刷新
    $fallback = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return $null
}

function Test-Msvc {
    return [bool](Find-VsInstallPath)
}

# 返回 VS 的安装路径（含 VC 生成工具时）
function Find-VsInstallPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }

    # 首选：官方推荐的「按组件过滤」查询
    $install = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    if ($install) { return $install.Trim() }

    # 兜底：逐个实例检查 vcvars64.bat，应对组件清单注册不完整的情况
    $all = & $vswhere -all -products * -property installationPath 2>$null
    foreach ($path in @($all)) {
        if (-not $path) { continue }
        $trimmed = $path.Trim()
        if (Test-Path -LiteralPath (Join-Path $trimmed 'VC\Auxiliary\Build\vcvars64.bat')) {
            return $trimmed
        }
    }
    return $null
}

# 把 MSVC 和 Windows SDK 的路径补进当前会话的环境变量。
#
# 需要处理两件事：
#   1. PATH 里可能有 Git for Windows 自带的 link.exe（GNU 的 link 工具），
#      rustc 会误用它并报 "link: extra operand"。
#   2. 没在 VS 开发者命令行里运行时，LIB / INCLUDE 是空的，
#      链接器会报 "LNK1181: 无法打开输入文件 kernel32.lib"。
#
# 最稳的做法是直接复用官方的 vcvars64.bat：它会算出正确的 PATH / LIB / INCLUDE。
function Enable-MsvcEnvironment {
    $vsPath = Find-VsInstallPath
    if (-not $vsPath) { return }

    $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path -LiteralPath $vcvars)) { return }

    # 只导回真正需要的变量，避免污染当前会话
    $wanted = @(
        'PATH', 'LIB', 'LIBPATH', 'INCLUDE',
        'VCINSTALLDIR', 'VSINSTALLDIR', 'VCToolsInstallDir',
        'VCToolsVersion', 'WindowsSdkDir', 'WindowsSDKVersion', 'UCRTVersion'
    )

    try {
        $lines = & cmd.exe /c "`"$vcvars`" >nul 2>&1 && set"
    } catch {
        return
    }

    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') {
            $name = $matches[1]
            $value = $matches[2]
            # cmd 的 `set` 输出里路径变量可能写作 Path，统一按大写比较
            if ($wanted -contains $name.ToUpperInvariant()) {
                $target = if ($name -ieq 'PATH') { 'Path' } else { $name }
                Set-Item -Path "env:$target" -Value $value
            }
        }
    }
}

function Assert-Toolchain {
    $cargo = Find-Cargo
    $msvc = Test-Msvc
    if ($cargo -and $msvc) { return $true }

    Write-Step '缺少编译环境'
    if (-not $cargo) { Write-Warn '未检测到 Rust（cargo）' }
    if (-not $msvc) { Write-Warn '未检测到 Visual Studio C++ 生成工具（MSVC）' }
    Write-Host ''
    Write-Info '桌面程序需要编译器才能生成 exe，安装方式：'
    Write-Info '  Rust   https://rustup.rs/'
    Write-Info '  MSVC   https://aka.ms/vs/17/release/vs_BuildTools.exe'
    Write-Info '         （安装时勾选「使用 C++ 的桌面开发」）'
    Write-Host ''
    Write-Info '或者用一条命令自动安装（会弹出管理员授权）：'
    Write-Info '  start.bat -Install'
    Write-Host ''
    Write-Info '安装完成后重新双击 start.bat 即可。'
    return $false
}

function Install-Toolchain {
    Write-Step '安装 Rust（rustup）'
    # 国内直连 static.rust-lang.org 很慢，优先走 rsproxy 镜像
    $env:RUSTUP_DIST_SERVER = 'https://rsproxy.cn'
    $env:RUSTUP_UPDATE_ROOT = 'https://rsproxy.cn/rustup'
    $rustupInit = Join-Path $env:TEMP 'salarytool-rustup-init.exe'
    try {
        Write-Info '下载 rustup-init.exe ...'
        Invoke-WebRequest -Uri 'https://rsproxy.cn/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe' `
            -OutFile $rustupInit -UseBasicParsing
        & $rustupInit -y --default-toolchain stable-x86_64-pc-windows-msvc --profile default
        if ($LASTEXITCODE -ne 0) { Write-Warn "rustup 返回码 $LASTEXITCODE" }
    } catch {
        Write-Warn "Rust 安装失败：$($_.Exception.Message)"
        Write-Info '可手动安装：https://rustup.rs/'
    } finally {
        Remove-Item -LiteralPath $rustupInit -Force -ErrorAction SilentlyContinue
    }

    Write-Step '安装 Visual Studio C++ 生成工具'
    Write-Info '体积约 2-3 GB，请耐心等待，可能需要 10-30 分钟'
    $vsInstaller = Join-Path $env:TEMP 'salarytool-vs_buildtools.exe'
    try {
        Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_buildtools.exe' `
            -OutFile $vsInstaller -UseBasicParsing
        $process = Start-Process -FilePath $vsInstaller -PassThru -Wait -ArgumentList @(
            '--quiet', '--wait', '--norestart', '--nocache',
            '--add', 'Microsoft.VisualStudio.Workload.VCTools',
            '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.22621',
            '--includeRecommended'
        )
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            Write-Warn "生成工具安装返回码 $($process.ExitCode)"
            Write-Info '可手动安装：https://aka.ms/vs/17/release/vs_BuildTools.exe'
        }
    } catch {
        Write-Warn "生成工具安装失败：$($_.Exception.Message)"
    } finally {
        Remove-Item -LiteralPath $vsInstaller -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Info '安装结束。请关闭并重新打开终端（刷新 PATH），再运行 start.bat'
    return $false
}

function Invoke-Npm {
    param([string[]]$Arguments)
    & $npm @Arguments
    if ($LASTEXITCODE -ne 0) { throw "npm $($Arguments -join ' ') 失败（退出码 $LASTEXITCODE）" }
}

function Get-SourceTimestamp {
    $paths = @('src', 'src-tauri\src', 'index.html', 'package.json', 'vite.config.ts',
        'tsconfig.json', 'tsconfig.node.json', 'src-tauri\Cargo.toml', 'src-tauri\tauri.conf.json',
        'src-tauri\capabilities')
    $latest = [datetime]::MinValue
    foreach ($relative in $paths) {
        $full = Join-Path $ProjectRoot $relative
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $items = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
        if ($items.PSIsContainer) {
            $items = Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue
        }
        foreach ($item in $items) {
            if ($item.LastWriteTimeUtc -gt $latest) { $latest = $item.LastWriteTimeUtc }
        }
    }
    return $latest
}

function Test-NeedsBuild {
    if ($Rebuild) { return $true }
    $exe = Resolve-ExePath
    if (-not $exe) { return $true }
    $exeTime = (Get-Item -LiteralPath $exe).LastWriteTimeUtc
    return (Get-SourceTimestamp) -gt $exeTime
}

# ============ 主流程 ============

Write-Host ''
Write-Host '  当月薪水到手计算器' -ForegroundColor White
Write-Host '  ----------------------------------------' -ForegroundColor DarkGray

# 1. Node.js
Write-Step '检查 Node.js'
if (-not (Test-Command 'node')) {
    Write-Fail '未找到 Node.js，请先安装：https://nodejs.org/（建议 LTS 版本）'
    exit 1
}
$nodeVersion = (& node -v).Trim()
if ([int](($nodeVersion -replace '^v', '').Split('.')[0]) -lt 20) {
    Write-Fail "Node.js 版本过低（$nodeVersion），需要 20 或更高"
    exit 1
}
Write-Info "Node.js $nodeVersion"

$npm = Get-NpmPath
if (-not $npm) {
    Write-Fail '未找到 npm，请重新安装 Node.js'
    exit 1
}

# 2. 依赖
Write-Step '检查前端依赖'
$modulesDir = Join-Path $ProjectRoot 'node_modules'
$installedLock = Join-Path $modulesDir '.package-lock.json'
$packageLock = Join-Path $ProjectRoot 'package-lock.json'
$needInstall = [bool]$Reinstall
if (-not (Test-Path -LiteralPath (Join-Path $modulesDir 'vue'))) { $needInstall = $true }
if (-not (Test-Path -LiteralPath $installedLock)) {
    $needInstall = $true
} elseif ((Test-Path -LiteralPath $packageLock) -and
    (Get-Item -LiteralPath $packageLock).LastWriteTimeUtc -gt (Get-Item -LiteralPath $installedLock).LastWriteTimeUtc) {
    $needInstall = $true
}
if ($needInstall) {
    Write-Info '正在安装依赖，首次需要几分钟...'
    try { Invoke-Npm @('install') } catch {
        Write-Fail $_.Exception.Message
        Write-Info '可尝试切换镜像：npm config set registry https://registry.npmmirror.com'
        exit 1
    }
    Write-Info '依赖安装完成'
} else {
    Write-Info '依赖已就绪'
}

# 3. 编译环境
if (-not (Assert-Toolchain)) {
    if ($Install) { $null = Install-Toolchain }
    exit 1
}
Enable-MsvcEnvironment

# 4. 开发模式
if ($Dev) {
    Write-Step '启动开发模式（Tauri dev，带热更新）'
    Write-Info '关闭窗口即退出'
    Invoke-Npm @('run', 'tauri', '--', 'dev')
    exit $LASTEXITCODE
}

# 5. 按需编译
if (Test-NeedsBuild) {
    # 正在运行的 exe 被占用，无法覆盖
    $runningApp = Get-Process -Name 'salarytool' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($runningApp) {
        Write-Step '需要重新编译'
        Write-Warn "程序正在运行（进程 $($runningApp.Id)），请先关闭窗口再运行本脚本"
        $answer = Read-Host '是否现在自动关闭并继续？(y/N)'
        if ($answer -match '^[Yy]') {
            Get-Process -Name 'salarytool' -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Milliseconds 900
        } else {
            Write-Info '已取消。关闭程序后重新运行 start.bat 即可'
            exit 1
        }
    }

    Write-Step '编译桌面程序'
    Write-Info '首次编译需要下载依赖并编译 Rust，可能需要几分钟；之后增量编译很快'
    $buildArgs = @('run', 'tauri', '--', 'build')
    if (-not $Installer) { $buildArgs += '--no-bundle' }
    try {
        Invoke-Npm $buildArgs
    } catch {
        Write-Fail $_.Exception.Message
        Write-Info '常见原因：'
        Write-Info '  1. 程序仍在运行，exe 被占用 → 关闭窗口后重试'
        Write-Info '  2. 缺 C++ 生成工具 → 安装 VS Build Tools（勾选「使用 C++ 的桌面开发」）'
        Write-Info '  3. 报 LNK1181 找不到 kernel32.lib → Windows SDK 没装完整，重跑 start.bat -Install'
        Write-Info '  4. 报 link: extra operand → PATH 里混进了 Git 的 GNU link.exe，重启终端再试'
        exit 1
    }
} else {
    Write-Step '程序已是最新版本'
}

if (-not (Resolve-ExePath)) {
    Write-Fail "编译完成但未找到可执行文件（src-tauri\target\release\*.exe）"
    Write-Info '可能被安全软件拦截，或 target 目录被清理'
    exit 1
}

if ($Installer) {
    $bundleDir = Join-Path $ProjectRoot 'src-tauri\target\release\bundle'
    if (Test-Path -LiteralPath $bundleDir) {
        Write-Step '安装包位置'
        Get-ChildItem -LiteralPath $bundleDir -Recurse -File -Include *.msi, *.exe |
            ForEach-Object { Write-Info $_.FullName }
    }
}

# 6. 启动
$exe = Resolve-ExePath

$running = Get-Process -Name 'salarytool' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($running) {
    Write-Step '程序已在运行'
    Write-Info "进程 $($running.Id)，为你切换到已有窗口"
    try {
        Add-Type -Namespace SalaryTool -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
        $handle = $running.MainWindowHandle
        if ($handle -ne [IntPtr]::Zero) {
            [SalaryTool.Native]::ShowWindow($handle, 9) | Out-Null
            [SalaryTool.Native]::SetForegroundWindow($handle) | Out-Null
        }
    } catch {
        # 切窗口失败不影响使用
    }
    exit 0
}

Write-Step '启动桌面程序'
Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe)
Write-Info "已启动：$exe"
Write-Info '可以关闭本窗口'
Start-Sleep -Milliseconds 600
exit 0
