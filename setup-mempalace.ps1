# Automacao MemPalace.
# Uso simples:  .\setup-mempalace.ps1 -Menu
# Uso direto:  .\setup-mempalace.ps1 -Action Full -ProjectPath "C:\meu\app"
# Apos git pull no MemPalace:  .\setup-mempalace.ps1 -Menu -ForceInstall
# Full + SearchQuery default: o teste de busca usa o wing do projeto (mais util que "mcp setup" noutros repos).
# Cursor MCP sem menu:  .\setup-mempalace.ps1 -Action CursorMcp
param(
    [string]$ProjectPath = "",
    [ValidateSet("Full", "Update", "Status", "WakeUp", "InitOnly", "Search", "CursorMcp")]
    [string]$Action = "Full",
    [string]$SearchQuery = "mcp setup",
    [string]$Palace = "",
    [switch]$SkipSearch,
    [switch]$SkipInstall,
    [switch]$ForceInstall,
    [switch]$InteractiveInit,
    [switch]$Menu
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-YesAnswer {
    param([string]$Raw)
    $t = $Raw.Trim()
    return @("S", "s", "Y", "y", "SIM", "sim", "YES", "yes") -contains $t
}

function Get-RepoRoot {
    return $PSScriptRoot
}

function Resolve-ProjectPath {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return [System.IO.Path]::GetFullPath((Get-Location).Path)
    }
    return [System.IO.Path]::GetFullPath($Raw)
}

function Get-ExpectedWing {
    param([string]$ProjectDir)
    $yaml = Join-Path $ProjectDir "mempalace.yaml"
    $legacy = Join-Path $ProjectDir "mempal.yaml"
    $cfg = $null
    if (Test-Path -LiteralPath $yaml) { $cfg = $yaml }
    elseif (Test-Path -LiteralPath $legacy) { $cfg = $legacy }

    if ($cfg) {
        foreach ($line in Get-Content -LiteralPath $cfg -Encoding UTF8) {
            $t = $line.TrimStart()
            if ($t.StartsWith("#")) { continue }
            if ($t -match '^\s*wing:\s*["''](.+)["'']\s*$') { return $Matches[1].Trim() }
            if ($t -match '^\s*wing:\s*(.+)$') {
                $v = ($Matches[1] -split '#')[0].Trim().Trim('"').Trim("'")
                if ($v) { return $v }
            }
        }
    }
    $leaf = Split-Path -Path $ProjectDir -Leaf
    return $leaf
}

function Apply-PalaceEnv {
    param([string]$PalaceArg)
    if ([string]::IsNullOrWhiteSpace($PalaceArg)) { return }
    $full = [System.IO.Path]::GetFullPath($PalaceArg)
    $env:MEMPALACE_PALACE_PATH = $full
    Write-Step "MEMPALACE_PALACE_PATH=$full"
}

function Ensure-Venv {
    param(
        [string]$RepoPath,
        [string]$VenvPath,
        [string]$ActivateScript
    )
    Write-Step "Criando venv (se necessario)"
    if (-not (Test-Path $ActivateScript)) {
        py -m venv $VenvPath
    }
    Write-Step "Ativando venv"
    . $ActivateScript
}

function Ensure-MempalaceEditable {
    param(
        [string]$RepoPath,
        [switch]$SkipInstall,
        [switch]$ForceInstall
    )
    if ($SkipInstall) {
        Write-Step "Pulando pip install (-SkipInstall)"
        return
    }
    if (-not $ForceInstall) {
        python -c "import mempalace" 2>$null
        if ($?) {
            Write-Step "MemPalace ja no venv (sem correr pip de novo). Use -ForceInstall se atualizou o codigo do repo."
            return
        }
    }
    Write-Step "Instalacao: pip + mempalace em modo editable (só quando falta ou com -ForceInstall)"
    python -m pip install -q -U pip
    pip install -e $RepoPath
}

function Read-ProjectFolder {
    param([string]$Hint)
    Write-Host ""
    Write-Host "  --- Pasta do projeto ---" -ForegroundColor White
    Write-Host "  Isto e a pasta do codigo ou docs que quer na memoria (nao e obrigatorio ser o MemPalace)." -ForegroundColor DarkGray
    if ($Hint) {
        Write-Host "  Sugestao: $Hint" -ForegroundColor DarkGray
    }
    Write-Host "  Pasta atual se carregar Enter: " -NoNewline -ForegroundColor DarkGray
    Write-Host (Get-Location).Path -ForegroundColor Gray
    $in = Read-Host "  Caminho (ou Enter)"
    if ([string]::IsNullOrWhiteSpace($in)) {
        return [System.IO.Path]::GetFullPath((Get-Location).Path)
    }
    return [System.IO.Path]::GetFullPath($in.Trim('"'))
}

function Show-Banner {
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor DarkCyan
    Write-Host "    MemPalace - assistente" -ForegroundColor Cyan
    Write-Host "  =============================================" -ForegroundColor DarkCyan
}

function Show-MainMenu {
    Show-Banner
    Write-Host ""
    Write-Host "  O que pretende fazer?" -ForegroundColor White
    Write-Host ""
    Write-Host "  1  Primeira vez com este projeto" -ForegroundColor Yellow
    Write-Host "     Instala o MemPalace, prepara pastas e guarda os ficheiros na memoria." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2  Ja usei antes - quero atualizar" -ForegroundColor Yellow
    Write-Host "     Volta a ler o projeto; ficheiros novos ou alterados entram na memoria." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3  Ver o que ja esta na memoria" -ForegroundColor Yellow
    Write-Host "     Mostra um resumo (por projeto / salas)." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  4  Gerar texto para colar na IA (ex.: Cursor)" -ForegroundColor Yellow
    Write-Host "     Contexto curto (wake-up) para o chat." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  5  Procurar algo na memoria" -ForegroundColor Yellow
    Write-Host "     Busca por palavra ou frase neste projeto." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  6  Mais opcoes..." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  7  Cursor: ligar MemPalace (MCP)" -ForegroundColor Yellow
    Write-Host "     O Cursor nao descobre sozinho - mostra o JSON e o ficheiro a editar." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  0  Sair" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-AdvancedMenu {
    Show-Banner
    Write-Host ""
    Write-Host "  Mais opcoes" -ForegroundColor White
    Write-Host ""
    Write-Host "  1  So reorganizar o projeto (init)" -ForegroundColor Yellow
    Write-Host "     Atualiza salas e configuracao; nao reindexa todos os ficheiros." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2  Usar outra pasta de memoria (palacio)" -ForegroundColor Yellow
    Write-Host "     Para quem guarda a memoria noutro disco ou pasta." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  0  Voltar ao menu principal" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-CursorMcpInstructions {
    param(
        [switch]$SkipInstall,
        [switch]$ForceInstall
    )
    $RepoPath = Get-RepoRoot
    $VenvPath = Join-Path $RepoPath ".venv"
    $ActivateScript = Join-Path $VenvPath "Scripts\Activate.ps1"

    Write-Step "Python do MemPalace para o Cursor (venv deste repo)"
    Ensure-Venv -RepoPath $RepoPath -VenvPath $VenvPath -ActivateScript $ActivateScript
    . $ActivateScript
    Ensure-MempalaceEditable -RepoPath $RepoPath -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall

    $pythonExe = [System.IO.Path]::GetFullPath((Join-Path $VenvPath "Scripts\python.exe"))
    $cursorDir = Join-Path $env:USERPROFILE ".cursor"
    $cursorMcp = Join-Path $cursorDir "mcp.json"

    $argsList = @("-m", "mempalace.mcp_server")
    $palaceEnv = [Environment]::GetEnvironmentVariable("MEMPALACE_PALACE_PATH", "Process")
    if (-not [string]::IsNullOrWhiteSpace($palaceEnv)) {
        $argsList = @("-m", "mempalace.mcp_server", "--palace", $palaceEnv)
    }

    $inner = [ordered]@{
        command = $pythonExe
        args    = $argsList
    }
    $fullDoc = [ordered]@{
        mcpServers = [ordered]@{
            mempalace = $inner
        }
    }

    $jsonFull = ($fullDoc | ConvertTo-Json -Depth 8)

    Write-Host ""
    Write-Host "  --- Cursor e o MemPalace ---" -ForegroundColor Cyan
    Write-Host "  O chat do Cursor so ve ferramentas MCP se estiverem registadas (nao e automatico)." -ForegroundColor White
    Write-Host ""
    Write-Host "  1) Abra: Definicoes do Cursor - Ferramentas e MCP (ou edite o JSON)." -ForegroundColor DarkGray
    Write-Host "  2) Ficheiro tipico (Windows): " -NoNewline -ForegroundColor DarkGray
    Write-Host $cursorMcp -ForegroundColor Gray
    Write-Host "  3) Se ja tiver outros servidores, adicione so a chave ""mempalace"" dentro de ""mcpServers""." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  --- Se o ficheiro for NOVO (copie o bloco inteiro) ---" -ForegroundColor Yellow
    Write-Host $jsonFull
    Write-Host ""
    Write-Host "  --- Se ja existir mcp.json (so a entrada mempalace) ---" -ForegroundColor Yellow
    $mergeLine = '"mempalace": ' + ($inner | ConvertTo-Json -Compress)
    Write-Host "  $mergeLine"
    Write-Host ""

    $yn = (Read-Host "  Copiar o JSON completo (novo ficheiro) para a area de transferencia? (S/N ou Y)").Trim()
    if (Test-YesAnswer $yn) {
        Set-Clipboard -Value $jsonFull
        Write-Host "  Copiado. Cole no mcp.json ou na UI MCP do Cursor." -ForegroundColor Green
    }

    $yn2 = (Read-Host "  Abrir a pasta .cursor no Explorador? (S/N ou Y)").Trim()
    if (Test-YesAnswer $yn2) {
        if (-not (Test-Path -LiteralPath $cursorDir)) {
            New-Item -ItemType Directory -Path $cursorDir -Force | Out-Null
        }
        Start-Process "explorer.exe" -ArgumentList $cursorDir
    }

    Write-Host ""
    Write-Host "  Reinicie o Cursor depois de guardar o mcp.json." -ForegroundColor DarkGray
    Write-Host "  Linha de comando (referencia): mempalace mcp" -ForegroundColor DarkGray
}

function Show-AssistantMenu {
    $repoHint = Get-RepoRoot
    while ($true) {
        Show-MainMenu
        $c = (Read-Host "  Escolha (0-7)").Trim()
        if ($c -eq "0") {
            Write-Host "Ate logo." -ForegroundColor Green
            return
        }

        if ($c -eq "7") {
            Show-CursorMcpInstructions -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall
            Read-Host "`nEnter para continuar"
            continue
        }

        if ($c -eq "6") {
            while ($true) {
                Show-AdvancedMenu
                $a = (Read-Host "  Escolha (0-2)").Trim()
                if ($a -eq "0") { break }

                if ($a -eq "1") {
                    $pp = Read-ProjectFolder -Hint $repoHint
                    Invoke-MempalaceSetup -ProjectPath $pp -Action InitOnly -SearchQuery $SearchQuery -Palace "" `
                        -SkipSearch -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall -InteractiveInit:$InteractiveInit
                    Read-Host "`nEnter para continuar"
                    break
                }

                if ($a -eq "2") {
                    Write-Host ""
                    $pal = Read-Host "  Caminho completo da pasta do palacio"
                    if ([string]::IsNullOrWhiteSpace($pal)) {
                        Write-Host "  Cancelado." -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                        continue
                    }
                    $pal = $pal.Trim('"')
                    Write-Host ""
                    Write-Host "  Com essa pasta de memoria, o que fazer?" -ForegroundColor White
                    Write-Host "  1  Ver resumo (status)" -ForegroundColor DarkGray
                    Write-Host "  2  So atualizar o projeto (mine)" -ForegroundColor DarkGray
                    Write-Host "  3  Setup completo neste palacio (init + mine)" -ForegroundColor DarkGray
                    $subPal = (Read-Host "  Escolha (1-3)").Trim()
                    $pp = Read-ProjectFolder -Hint $repoHint
                    $actPal = switch ($subPal) {
                        "1" { "Status" }
                        "2" { "Update" }
                        "3" { "Full" }
                        default { $null }
                    }
                    if (-not $actPal) {
                        Write-Host "  Cancelado." -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                        continue
                    }
                    $skipPal = ($actPal -ne "Full")
                    Invoke-MempalaceSetup -ProjectPath $pp -Action $actPal -SearchQuery $SearchQuery -Palace $pal `
                        -SkipSearch:$skipPal -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall -InteractiveInit:$InteractiveInit
                    Write-Host "  (Palacio alternativo so nesta operacao.)" -ForegroundColor DarkGray
                    Read-Host "`nEnter para continuar"
                    break
                }

                Write-Host "  Opcao invalida." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
            continue
        }

        $map = @{
            "1" = @{ Action = "Full"; SkipSearch = $false }
            "2" = @{ Action = "Update"; SkipSearch = $true }
            "3" = @{ Action = "Status"; SkipSearch = $true }
            "4" = @{ Action = "WakeUp"; SkipSearch = $true }
            "5" = @{ Action = "Search"; SkipSearch = $true }
        }

        if (-not $map.ContainsKey($c)) {
            Write-Host "  Opcao invalida." -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }

        $sel = $map[$c]
        $pp = Read-ProjectFolder -Hint $repoHint

        $sq = $SearchQuery
        if ($sel.Action -eq "Search") {
            Write-Host ""
            $qIn = Read-Host "  O que procura? (Enter = '$SearchQuery')"
            if (-not [string]::IsNullOrWhiteSpace($qIn)) {
                $sq = $qIn.Trim()
            }
        }

        Invoke-MempalaceSetup -ProjectPath $pp -Action $sel.Action -SearchQuery $sq -Palace "" `
            -SkipSearch:$sel.SkipSearch -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall -InteractiveInit:$InteractiveInit

        Read-Host "`nEnter para voltar ao menu"
    }
}

function Invoke-MempalaceSetup {
    param(
        [string]$ProjectPath = "",
        [string]$Action = "Full",
        [string]$SearchQuery = "mcp setup",
        [string]$Palace = "",
        [switch]$SkipSearch,
        [switch]$SkipInstall,
        [switch]$ForceInstall,
        [switch]$InteractiveInit
    )

    $RepoPath = Get-RepoRoot
    $ProjectPath = Resolve-ProjectPath $ProjectPath
    $VenvPath = Join-Path $RepoPath ".venv"
    $ActivateScript = Join-Path $VenvPath "Scripts\Activate.ps1"

    Apply-PalaceEnv $Palace

    Write-Step "Operacao: $Action"
    Write-Step "Instalacao MemPalace (repo): $RepoPath"

    if ($Action -eq "CursorMcp") {
        Show-CursorMcpInstructions -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall
        Write-Step "Concluido"
        Write-Host "Feito." -ForegroundColor Green
        return
    }

    Write-Step "Projeto: $ProjectPath"

    if (-not (Test-Path -LiteralPath $ProjectPath)) {
        throw "Pasta do projeto nao existe: $ProjectPath"
    }

    $expectedWing = Get-ExpectedWing $ProjectPath
    Write-Host "  Nome do projeto na memoria (wing): $expectedWing" -ForegroundColor DarkGray

    Ensure-Venv -RepoPath $RepoPath -VenvPath $VenvPath -ActivateScript $ActivateScript

    $initArgs = @("init", $ProjectPath)
    if (-not $InteractiveInit) {
        $initArgs = @("init", "--yes", $ProjectPath)
    }

    switch ($Action) {
        "Full" {
            Ensure-MempalaceEditable -RepoPath $RepoPath -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall
            Write-Step "Preparar projeto (init)"
            & mempalace @initArgs
            Write-Step "Guardar ficheiros na memoria (pode demorar)"
            & mempalace @("mine", $ProjectPath)
            Write-Host "  Nota: se aparecer 'Files skipped' = total de ficheiros, o index ja existia (normal). Novos ou alterados sao reindexados." -ForegroundColor DarkGray
            if (-not $SkipSearch) {
                $testQuery = if ($SearchQuery -eq "mcp setup") { $expectedWing } else { $SearchQuery }
                Write-Step "Teste de busca neste projeto (consulta: $testQuery)"
                & mempalace @("search", $testQuery, "--wing", $expectedWing)
            }
        }
        "Update" {
            Ensure-MempalaceEditable -RepoPath $RepoPath -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall
            Write-Step "Atualizar memoria (so ficheiros novos ou alterados)"
            & mempalace @("mine", $ProjectPath)
            Write-Host "  Se nada mudou nos ficheiros, pode ver 0 processados e o resto skipped - e esperado." -ForegroundColor DarkGray
            Write-Host "  Quer ver totais? Menu opcao 3 (Ver o que ja esta na memoria)." -ForegroundColor DarkGray
        }
        "InitOnly" {
            Ensure-MempalaceEditable -RepoPath $RepoPath -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall
            Write-Step "Reorganizar projeto (init)"
            & mempalace @initArgs
        }
        "Status" {
            Ensure-MempalaceEditable -RepoPath $RepoPath -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall
            Write-Step ('Resumo: wing esperado para este projeto: {0}' -f $expectedWing)
            Write-Step "Lista completa do palacio (todas as wings)"
            mempalace status
        }
        "WakeUp" {
            Ensure-MempalaceEditable -RepoPath $RepoPath -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall
            Write-Step "Texto para colar no chat (wake-up)"
            & mempalace @("wake-up", "--wing", $expectedWing)
            Write-Host "  L0 'No identity': opcional - crie ~/.mempalace/identity.txt com uma linha sobre si (quem e o utilizador)." -ForegroundColor DarkGray
        }
        "Search" {
            Ensure-MempalaceEditable -RepoPath $RepoPath -SkipInstall:$SkipInstall -ForceInstall:$ForceInstall
            Write-Step "Busca: $SearchQuery"
            & mempalace @("search", $SearchQuery, "--wing", $expectedWing)
        }
    }

    Write-Step "Concluido"
    Write-Host "Feito." -ForegroundColor Green
    if ($Action -eq "Full" -or $Action -eq "Update") {
        Write-Host "Dica: no menu, opcao 4 gera o texto de contexto para o Cursor." -ForegroundColor DarkGray
    }
}

if ($Menu) {
    Show-AssistantMenu
    exit 0
}

$bp = @{}
foreach ($k in $PSBoundParameters.Keys) {
    if ($k -ne 'Menu') {
        $bp[$k] = $PSBoundParameters[$k]
    }
}
Invoke-MempalaceSetup @bp
