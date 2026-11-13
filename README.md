# Macro App

App de terminal para Windows que executa macros do SAP. É feito em PowerShell,
que já vem no Windows: não precisa instalar nada nem rodar nenhum `.exe`.

## Uso

1. Copie a pasta inteira (`macro.cmd`, `macro.ps1` e `macros`) para o computador.
2. Abra o SAP e faça login.
3. Dê dois cliques em `macro.cmd`.
4. Digite `/` para ver os comandos.

| Comando   | O que faz                                                             |
|-----------|-----------------------------------------------------------------------|
| `/pdfs`   | Abre no navegador o PDF de cada part number (MD04, centro 8500)       |
| `/ajuda`  | Mostra os comandos                                                    |
| `/diagnostico` | Testa a conexão com o SAP passo a passo                          |
| `/limpar` | Limpa a tela                                                          |
| `/sair`   | Fecha o app                                                           |

Em `/pdfs`, cole a lista de part numbers (um por linha, ou separados por espaço,
vírgula ou ponto e vírgula), tecle Enter e depois Enter de novo com a linha vazia
para executar. Também dá para passar direto: `/pdfs 12345 67890`.

O SAP GUI Scripting precisa estar habilitado, como já é exigido pelas macros VBA.

Se a conexão com o SAP falhar, rode `/diagnostico` para ver em que passo. Também
dá para abrir no PowerShell de 32 bits com `macro.cmd --32`.

Para testar sem SAP, abra pelo Prompt de Comando com `macro.cmd --simular`
(qualquer item contendo "erro" falha).

## Nova macro

Cada arquivo `.ps1` dentro de `macros` é uma macro e aparece sozinho na lista de
comandos. Copie `macros/pdfs-md04.ps1`, troque o comando e escreva os passos em
`PorItem`. Os passos gravados pelo SAP em VBA viram:

| VBA                                         | Aqui                          |
|---------------------------------------------|-------------------------------|
| `session.findById(id).Text = valor`         | `Sap-Texto id valor`          |
| `session.findById(janela).sendVKey n`       | `Sap-Tecla janela n`          |
| `session.findById(id).press`                | `Sap-Clicar id`               |
| `session.findById(id).pressButton botao`    | `Sap-Botao id botao`          |
| `session.findById(janela).maximize`         | `Sap-Maximizar janela`        |

`Sap-ConferirStatus` interrompe o item com a mensagem do SAP quando a barra de
status mostra erro.

Salve os arquivos `.ps1` em UTF-8 com BOM, para os acentos aparecerem certos.
