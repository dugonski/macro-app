# Macro App: terminal para executar macros do SAP GUI.
# Abra pelo macro.cmd. Compatível com o Windows PowerShell 5.1, que já vem no Windows.
param(
    [string]$Raiz,
    [switch]$Simular  # executa as macros sem o SAP, para testar o app
)

$ErrorActionPreference = 'Stop'
$Bits = 32
if ([Environment]::Is64BitProcess) { $Bits = 64 }
$Versao = "0.1.2 ($Bits bits)"
if (-not $Raiz) { $Raiz = $PSScriptRoot }

$Destaque = 'DarkYellow'
$Fraco = 'DarkGray'
$Bom = 'Green'
$Ruim = 'Red'

# ============================================================================
# SAP: funções usadas pelas macros (equivalentes ao SAP GUI Scripting do VBA)
# ============================================================================

$script:Sessao = $null
$script:MaterialSimulado = ''

$ModosDeChamada = @('InvokeMethod', 'GetProperty', 'InvokeMethod,GetProperty')

# Chama um método ou propriedade pelo nome (IDispatch), como o VBA faz.
# $Modos lista as formas de chamada a tentar, em ordem. A vírgula no retorno
# impede o PowerShell de desmontar objetos do SAP que são coleções.
function Invoke-Com($Alvo, [string]$Nome, [object[]]$Argumentos = @(), [string[]]$Modos = @('InvokeMethod')) {
    $tipo = $Alvo.GetType()
    $ultimoErro = ''
    foreach ($modo in $Modos) {
        try {
            $resultado = $tipo.InvokeMember($Nome, [System.Reflection.BindingFlags]$modo, $null, $Alvo, $Argumentos)
            return , $resultado
        }
        catch {
            $erro = $_.Exception
            while ($erro.InnerException) { $erro = $erro.InnerException }
            $ultimoErro = $erro.Message
        }
    }
    throw "$Nome falhou: $ultimoErro"
}

# Equivale a GetObject("SAPGUI").GetScriptingEngine.Children(0).Children(0).
function Conectar-Sap {
    if ($Simular) { return }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
        throw 'o SAP GUI só está disponível no Windows (use --simular para testar)'
    }

    # Duas formas de achar o SAP aberto; a segunda é o utilitário que o próprio SAP GUI instala.
    $fontes = @(
        { , [System.Runtime.InteropServices.Marshal]::BindToMoniker('SAPGUI') },
        {
            $rot = New-Object -ComObject 'SapROTWr.SapROTWrapper'
            , (Invoke-Com $rot 'GetROTEntry' @('SAPGUI') $ModosDeChamada)
        }
    )
    $motor = $null
    $achouSap = $false
    $detalhes = [System.Collections.Generic.List[string]]::new()
    foreach ($fonte in $fontes) {
        $gui = $null
        try { $gui = & $fonte } catch { }
        if ($null -eq $gui) { continue }
        $achouSap = $true
        try { $motor = Invoke-Com $gui 'GetScriptingEngine' @() $ModosDeChamada }
        catch { $detalhes.Add($_.Exception.Message) }
        if ($null -ne $motor) { break }
    }
    if (-not $achouSap) { throw 'SAP não encontrado: abra o SAP e faça login antes de executar' }
    if ($null -eq $motor) {
        if ($detalhes.Count -eq 0) { $detalhes.Add('GetScriptingEngine não devolveu nada') }
        # TYPE_E_CANTLOADLIBRARY: o SAP GUI e o PowerShell não têm o mesmo número de bits.
        if (($detalhes -join ' ') -match '80029C4A') {
            if ($Bits -eq 64) { throw 'o SAP GUI instalado é de 32 bits e o app abriu em 64 bits: abra pelo macro.cmd, sem --64' }
            throw 'o SAP GUI instalado é de 64 bits e o app abriu em 32 bits: abra com macro.cmd --64'
        }
        throw ('SAP GUI Scripting indisponível (' + ($detalhes -join ' | ') + ')')
    }

    $sessao = $null
    try {
        $conexao = Invoke-Com $motor 'Children' @(0) $ModosDeChamada
        if ($null -eq $conexao) { throw 'nenhuma conexão aberta' }
        $sessao = Invoke-Com $conexao 'Children' @(0) $ModosDeChamada
        if ($null -eq $sessao) { throw 'nenhuma sessão aberta' }
    }
    catch { throw "SAP aberto, mas sem sessão logada ($($_.Exception.Message))" }
    $script:Sessao = $sessao
}

function Sap-Elemento([string]$Id) {
    $elemento = $null
    try { $elemento = Invoke-Com $script:Sessao 'findById' @($Id) } catch { }
    if ($null -eq $elemento) { throw "elemento `"$Id`" não encontrado na tela do SAP" }
    return , $elemento
}

# Preenche um campo:  session.findById(id).Text = texto
function Sap-Texto([string]$Id, [string]$Texto) {
    if ($Simular) {
        if ($Id.EndsWith('MATNR')) { $script:MaterialSimulado = $Texto }
        return
    }
    $null = Invoke-Com (Sap-Elemento $Id) 'Text' @($Texto) @('SetProperty')
}

# Envia uma tecla virtual:  session.findById(janela).sendVKey tecla
function Sap-Tecla([string]$Janela, [int]$Tecla) {
    if ($Simular) { Start-Sleep -Milliseconds 150; return }
    $null = Invoke-Com (Sap-Elemento $Janela) 'sendVKey' @($Tecla)
}

# Clica em um botão:  session.findById(id).press
function Sap-Clicar([string]$Id, [switch]$IgnorarErro) {
    if ($Simular) { return }
    try { $null = Invoke-Com (Sap-Elemento $Id) 'press' }
    catch { if (-not $IgnorarErro) { throw } }
}

# Aperta um botão de uma barra:  session.findById(id).pressButton botao
function Sap-Botao([string]$Id, [string]$Botao) {
    if ($Simular) { Start-Sleep -Milliseconds 300; return }
    $null = Invoke-Com (Sap-Elemento $Id) 'pressButton' @($Botao)
}

function Sap-Maximizar([string]$Janela) {
    if ($Simular) { return }
    try { $null = Invoke-Com (Sap-Elemento $Janela) 'maximize' } catch { }
}

# Lança erro com o texto da barra de status se o SAP recusou a última ação.
function Sap-ConferirStatus {
    if ($Simular) {
        if ($script:MaterialSimulado -match 'erro') { throw "Material $script:MaterialSimulado não existe (simulado)" }
        return
    }
    $barra = Sap-Elemento 'wnd[0]/sbar'
    $tipo = [string](Invoke-Com $barra 'MessageType' @() @('GetProperty'))
    if ($tipo -eq 'E' -or $tipo -eq 'A') {
        $texto = [string](Invoke-Com $barra 'Text' @() @('GetProperty'))
        if (-not $texto) { $texto = 'o SAP recusou o item' }
        throw $texto
    }
}

# ============================================================================
# Tela: o histórico rola normalmente; a área viva no fim (caixa de entrada,
# sugestões, progresso) é redesenhada. Uma linha é uma lista texto, cor, texto, cor...
# ============================================================================

$script:Topo = -1   # primeira linha da área viva
$script:Altura = 0  # linhas ocupadas pela área viva

# Uma coluna a menos para o console nunca quebrar a linha sozinho.
function Largura { [Math]::Max(24, [Console]::WindowWidth) - 1 }

function Escrever-Partes([object[]]$Partes, [int]$Limite) {
    $escrito = 0
    for ($i = 0; $i -lt $Partes.Count; $i += 2) {
        $texto = [string]$Partes[$i]
        $cor = $null
        if ($i + 1 -lt $Partes.Count) { $cor = $Partes[$i + 1] }
        if ($Limite -gt 0 -and $escrito + $texto.Length -gt $Limite) { $texto = $texto.Substring(0, $Limite - $escrito) }
        if ($texto.Length -eq 0) { continue }
        if ($cor) { [Console]::ForegroundColor = [ConsoleColor]$cor }
        [Console]::Write($texto)
        [Console]::ResetColor()
        $escrito += $texto.Length
    }
    if ($Limite -gt $escrito) { [Console]::Write(' ' * ($Limite - $escrito)) }
}

function Limpar-Faixa([int]$Linha) {
    if ($Linha -ge [Console]::BufferHeight) { return }
    [Console]::SetCursorPosition(0, $Linha)
    [Console]::Write(' ' * (Largura))
}

# Escreve uma linha no histórico, acima da área viva.
function Imprimir([object[]]$Partes = @('')) {
    try {
        [Console]::CursorVisible = $false
        if ($script:Topo -lt 0) { $script:Topo = [Console]::CursorTop }
        for ($i = 0; $i -lt $script:Altura; $i++) { Limpar-Faixa ($script:Topo + $i) }
        [Console]::SetCursorPosition(0, $script:Topo)
    }
    catch [System.ArgumentOutOfRangeException] { }
    Escrever-Partes $Partes 0
    [Console]::WriteLine()
    $script:Topo = [Console]::CursorTop
    $script:Altura = 0
}

# Redesenha a área viva. $CursorLinha negativo esconde o cursor.
function Desenhar($Linhas, [int]$CursorLinha = -1, [int]$CursorColuna = 0) {
    try {
        [Console]::CursorVisible = $false
        if ($script:Topo -lt 0) { $script:Topo = [Console]::CursorTop }

        # Sem espaço abaixo: rola o console para abrir.
        $sobra = $script:Topo + $Linhas.Count - [Console]::BufferHeight
        if ($sobra -gt 0) {
            [Console]::SetCursorPosition(0, [Console]::BufferHeight - 1)
            for ($i = 0; $i -lt $sobra; $i++) { [Console]::WriteLine() }
            $script:Topo = [Math]::Max(0, $script:Topo - $sobra)
        }

        $largura = Largura
        for ($i = 0; $i -lt $Linhas.Count; $i++) {
            [Console]::SetCursorPosition(0, $script:Topo + $i)
            Escrever-Partes $Linhas[$i] $largura
        }
        for ($i = $Linhas.Count; $i -lt $script:Altura; $i++) { Limpar-Faixa ($script:Topo + $i) }
        $script:Altura = $Linhas.Count

        if ($CursorLinha -ge 0) {
            [Console]::SetCursorPosition([Math]::Min($CursorColuna, $largura), $script:Topo + $CursorLinha)
            [Console]::CursorVisible = $true
        }
    }
    catch [System.ArgumentOutOfRangeException] {
        # A janela mudou de tamanho no meio do desenho: recomeça de onde o cursor está.
        $script:Topo = -1
        $script:Altura = 0
    }
}

function Imprimir-Faixa {
    $dica = 'Digite / para ver os comandos · /ajuda para ajuda'
    $titulo = [System.Collections.Generic.List[object]]::new()
    $titulo.AddRange(@('│ ', $Destaque, '* Macro App', $Destaque, "  v$Versao", $Fraco))
    $usado = 14 + $Versao.Length
    if ($Simular) { $titulo.AddRange(@('  [simulação]', $Ruim)); $usado += 13 }
    $titulo.AddRange(@((' ' * ($dica.Length - $usado) + ' │'), $Destaque))

    $barra = '─' * ($dica.Length + 2)
    Imprimir @("┌$barra┐", $Destaque)
    Imprimir $titulo.ToArray()
    Imprimir @('│ ', $Destaque, $dica, $Fraco, ' │', $Destaque)
    Imprimir @("└$barra┘", $Destaque)
    Imprimir
}

# ============================================================================
# Comandos e macros
# ============================================================================

$Comandos = [System.Collections.Generic.List[object]]::new()

# Cada arquivo em macros\ devolve a definição de uma macro. Eles são lidos como
# texto para funcionar mesmo com a execução de .ps1 restrita.
$pastaMacros = Join-Path $Raiz 'macros'
if (Test-Path -LiteralPath $pastaMacros) {
    foreach ($arquivo in Get-ChildItem -LiteralPath $pastaMacros -Filter '*.ps1' | Sort-Object Name) {
        $definicao = & ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 -LiteralPath $arquivo.FullName)))
        $Comandos.Add(@{ Nome = $definicao.Comando; Descricao = $definicao.Descricao; Macro = $definicao })
    }
}
$Comandos.Add(@{ Nome = 'ajuda'; Descricao = 'Mostra os comandos disponíveis' })
$Comandos.Add(@{ Nome = 'limpar'; Descricao = 'Limpa a tela' })
$Comandos.Add(@{ Nome = 'sair'; Descricao = 'Fecha o app' })

$script:Modo = 'Comando'   # Comando | Lista
$script:Sair = $false
$script:Texto = ''
$script:Cursor = 0
$script:Escolhida = 0      # sugestão destacada
$script:Ativa = $null      # macro recebendo a lista
$script:Itens = [System.Collections.Generic.List[string]]::new()

function Definir-Texto([string]$Novo) {
    $script:Texto = $Novo
    $script:Cursor = $Novo.Length
    $script:Escolhida = 0
}

function Voltar-AoComando {
    $script:Modo = 'Comando'
    $script:Ativa = $null
    $script:Itens = [System.Collections.Generic.List[string]]::new()
    Definir-Texto ''
}

function Obter-Sugestoes {
    $lista = [System.Collections.Generic.List[object]]::new()
    if ($script:Modo -eq 'Comando' -and $script:Texto.StartsWith('/') -and $script:Texto -notmatch '\s') {
        $prefixo = $script:Texto.Substring(1).ToLowerInvariant()
        foreach ($c in $Comandos) { if ($c.Nome.StartsWith($prefixo)) { $lista.Add($c) } }
    }
    return , $lista
}

# Separa por espaço, vírgula, ponto e vírgula ou quebra de linha, sem repetir.
function Adicionar-Itens([string]$Texto) {
    foreach ($item in ($Texto -split '[\s,;]+')) {
        if ($item -and -not $script:Itens.Contains($item)) { $script:Itens.Add($item) }
    }
}

function Executar-Comando([string]$Linha) {
    Imprimir @('> ', $Destaque, $Linha)
    $partes = $Linha -split '\s+', 2
    if (-not $partes[0].StartsWith('/')) {
        Imprimir @('  Os comandos começam com /. Digite /ajuda para ver a lista.', $Fraco)
        Imprimir
        return
    }

    $nome = $partes[0].Substring(1).ToLowerInvariant()
    $comando = $null
    foreach ($c in $Comandos) { if ($c.Nome -eq $nome) { $comando = $c } }

    if ($null -eq $comando) {
        Imprimir @("  Comando desconhecido: $($partes[0])", $Ruim, ' · /ajuda mostra a lista', $Fraco)
        Imprimir
    }
    elseif ($comando.Macro) {
        $script:Ativa = $comando.Macro
        $script:Modo = 'Lista'
        if ($partes.Count -gt 1) { Adicionar-Itens $partes[1] }
        if ($script:Itens.Count -gt 0) { Executar-Macro }
    }
    elseif ($nome -eq 'ajuda') {
        foreach ($c in $Comandos) { Imprimir @(('  /' + $c.Nome.PadRight(8)), $Destaque, "  $($c.Descricao)") }
        Imprimir
        Imprimir @('  Dica: a lista pode ir junto do comando, ex.: /pdfs 12345 67890', $Fraco)
        Imprimir
    }
    elseif ($nome -eq 'limpar') {
        [Console]::Clear()
        $script:Topo = -1
        $script:Altura = 0
        Imprimir-Faixa
    }
    elseif ($nome -eq 'sair') {
        $script:Sair = $true
    }
}

function Mostrar-Andamento([string]$Texto) {
    $linhas = [System.Collections.Generic.List[object]]::new()
    $linhas.Add(@('  » ', $Destaque, $Texto, $null, '   Esc para cancelar', $Fraco))
    Desenhar $linhas
}

# Esc cancela entre um item e outro; Ctrl+C fecha o app.
function Pediu-Cancelamento {
    $cancelar = $false
    while ([Console]::KeyAvailable) {
        $tecla = [Console]::ReadKey($true)
        if ($tecla.Key -eq 'Escape') { $cancelar = $true }
        if ($tecla.Key -eq 'C' -and ($tecla.Modifiers -band [ConsoleModifiers]::Control)) { $cancelar = $true; $script:Sair = $true }
    }
    return $cancelar
}

function Executar-Macro {
    $macro = $script:Ativa
    $itens = $script:Itens.ToArray()
    $total = $itens.Count
    $abertos = 0
    $falhas = [System.Collections.Generic.List[string]]::new()
    $cancelado = $false
    $erroGeral = $null

    Imprimir @("  $($macro.Titulo)", $null, " · $total $($macro.Rotulo)", $Fraco)
    Mostrar-Andamento 'Conectando ao SAP...'
    try {
        Conectar-Sap
        if ($macro.Inicio) { & $macro.Inicio }
    }
    catch { $erroGeral = $_.Exception.Message }

    if (-not $erroGeral) {
        for ($i = 0; $i -lt $total; $i++) {
            if (Pediu-Cancelamento) { $cancelado = $true; break }
            $item = $itens[$i]
            Mostrar-Andamento "Processando $($i + 1)/$total · $item"
            try {
                & $macro.PorItem $item
                $abertos++
                Imprimir @('  √ ', $Bom, $item, $null, "  $($macro.Sucesso)", $Fraco)
            }
            catch {
                $falhas.Add($item)
                Imprimir @('  × ', $Ruim, $item, $null, "  $($_.Exception.Message)", $Ruim)
            }
        }
    }

    if ($erroGeral) { Imprimir @("  × $erroGeral", $Ruim) }
    elseif ($cancelado) { Imprimir @("  Cancelado · $abertos concluídos de $total", $Fraco) }
    elseif ($falhas.Count -eq 0) { Imprimir @("  Concluído · $abertos de $total", $Bom) }
    else {
        Imprimir @('  Concluído · ', $null, "$abertos com sucesso", $Bom, ' · ', $null, "$($falhas.Count) com falha", $Ruim)
        Imprimir @(('  Falharam: ' + ($falhas -join ', ')), $Fraco)
    }
    Imprimir
    $script:Sessao = $null
    Voltar-AoComando
}

# ============================================================================
# Teclado
# ============================================================================

# Edição básica da linha. Devolve $true se o texto mudou.
function Editar-Texto($Tecla) {
    switch ($Tecla.Key) {
        'LeftArrow' { $script:Cursor = [Math]::Max(0, $script:Cursor - 1); return $false }
        'RightArrow' { $script:Cursor = [Math]::Min($script:Texto.Length, $script:Cursor + 1); return $false }
        'Home' { $script:Cursor = 0; return $false }
        'End' { $script:Cursor = $script:Texto.Length; return $false }
        'Backspace' {
            if ($script:Cursor -eq 0) { return $false }
            $script:Texto = $script:Texto.Remove($script:Cursor - 1, 1)
            $script:Cursor--
            return $true
        }
        'Delete' {
            if ($script:Cursor -ge $script:Texto.Length) { return $false }
            $script:Texto = $script:Texto.Remove($script:Cursor, 1)
            return $true
        }
    }
    $letra = $Tecla.KeyChar
    if ($letra -eq [char]0 -or [char]::IsControl($letra)) { return $false }
    $script:Texto = $script:Texto.Insert($script:Cursor, [string]$letra)
    $script:Cursor++
    return $true
}

function Tratar-TeclaComando($Tecla) {
    $sugestoes = Obter-Sugestoes
    $escolha = $null
    if ($sugestoes.Count -gt 0) { $escolha = $sugestoes[[Math]::Min($script:Escolhida, $sugestoes.Count - 1)] }
    switch ($Tecla.Key) {
        'UpArrow' { if ($escolha) { $script:Escolhida = ($script:Escolhida + $sugestoes.Count - 1) % $sugestoes.Count }; return }
        'DownArrow' { if ($escolha) { $script:Escolhida = ($script:Escolhida + 1) % $sugestoes.Count }; return }
        'Tab' { if ($escolha) { Definir-Texto "/$($escolha.Nome) " }; return }
        'Escape' { Definir-Texto ''; return }
        'Enter' {
            $linha = $script:Texto.Trim()
            if ($escolha) { $linha = "/$($escolha.Nome)" }
            Definir-Texto ''
            if ($linha) { Executar-Comando $linha }
            return
        }
    }
    if (Editar-Texto $Tecla) { $script:Escolhida = 0 }
}

function Tratar-TeclaLista($Tecla, [double]$DesdeAnteriorMs) {
    switch ($Tecla.Key) {
        'Escape' {
            Voltar-AoComando
            Imprimir @('  Cancelado.', $Fraco)
            Imprimir
            return
        }
        'Enter' {
            $linha = $script:Texto.Trim()
            Definir-Texto ''
            if ($linha) { Adicionar-Itens $linha }
            # Linha em branco no meio de uma colagem não deve disparar a macro.
            elseif ($script:Itens.Count -gt 0 -and $DesdeAnteriorMs -ge 150) { Executar-Macro }
            return
        }
    }
    $null = Editar-Texto $Tecla
}

function Desenhar-Entrada {
    $linhas = [System.Collections.Generic.List[object]]::new()
    $naLista = $script:Modo -eq 'Lista'
    if ($naLista) {
        $linhas.Add(@("  $($script:Ativa.Titulo)", $null, " · $($script:Itens.Count) $($script:Ativa.Rotulo) na lista", $Fraco))
    }

    # caixa de entrada: mostra o trecho do texto em volta do cursor
    $borda = $Fraco
    $marca = '> '
    if ($naLista) { $borda = $Destaque; $marca = '+ ' }
    $interno = (Largura) - 4
    $espaco = $interno - 2
    $inicio = [Math]::Max(0, $script:Cursor - $espaco + 1)
    $visivel = $script:Texto.Substring($inicio, [Math]::Min($espaco, $script:Texto.Length - $inicio))
    $linhaDaEntrada = $linhas.Count + 1
    $linhas.Add(@(('┌' + '─' * ($interno + 2) + '┐'), $borda))
    $linhas.Add(@('│ ', $borda, $marca, $Destaque, $visivel.PadRight($espaco), $null, ' │', $borda))
    $linhas.Add(@(('└' + '─' * ($interno + 2) + '┘'), $borda))

    $sugestoes = Obter-Sugestoes
    if ($naLista) {
        $dica = "  Cole ou digite os $($script:Ativa.Rotulo) e tecle Enter · Esc cancela"
        if ($script:Itens.Count -gt 0) { $dica = '  Enter com a linha vazia executa · Esc cancela' }
        $linhas.Add(@($dica, $Fraco))
    }
    elseif ($sugestoes.Count -eq 0) {
        $linhas.Add(@('  / para comandos · Ctrl+C para sair', $Fraco))
    }
    for ($i = 0; $i -lt $sugestoes.Count; $i++) {
        $nome = '  /' + $sugestoes[$i].Nome.PadRight(8) + '  '
        if ($i -eq [Math]::Min($script:Escolhida, $sugestoes.Count - 1)) { $linhas.Add(@($nome, $Destaque, $sugestoes[$i].Descricao)) }
        else { $linhas.Add(@(($nome + $sugestoes[$i].Descricao), $Fraco)) }
    }

    Desenhar $linhas $linhaDaEntrada (4 + $script:Cursor - $inicio)
}

# ============================================================================
# Laço principal
# ============================================================================

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
[Console]::TreatControlCAsInput = $true
try { [Console]::Title = 'Macro App' } catch { }

try {
    Imprimir-Faixa
    $relogio = [System.Diagnostics.Stopwatch]::StartNew()
    $ultimaTecla = 0.0
    $largura = 0
    $redesenhar = $true

    while (-not $script:Sair) {
        while (-not $script:Sair -and [Console]::KeyAvailable) {
            $tecla = [Console]::ReadKey($true)
            $agora = $relogio.Elapsed.TotalMilliseconds
            $desde = $agora - $ultimaTecla
            $ultimaTecla = $agora
            $redesenhar = $true

            if ($tecla.Key -eq 'C' -and ($tecla.Modifiers -band [ConsoleModifiers]::Control)) { $script:Sair = $true }
            elseif ($script:Modo -eq 'Lista') { Tratar-TeclaLista $tecla $desde }
            else { Tratar-TeclaComando $tecla }
        }
        if ($script:Sair) { break }

        if ($largura -ne (Largura)) { $largura = Largura; $redesenhar = $true }
        if ($redesenhar) { Desenhar-Entrada; $redesenhar = $false }
        Start-Sleep -Milliseconds 20
    }
}
finally {
    Desenhar ([System.Collections.Generic.List[object]]::new())
    [Console]::CursorVisible = $true
    [Console]::TreatControlCAsInput = $false
    [Console]::ResetColor()
}
