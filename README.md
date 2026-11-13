# Macro App

App de terminal para Windows que executa macros do SAP. É um único `macro.exe`:
não precisa instalar nada, basta copiar e abrir.

## Uso

1. Abra o SAP e faça login.
2. Abra o `macro.exe`.
3. Digite `/` para ver os comandos.

| Comando   | O que faz                                                             |
|-----------|-----------------------------------------------------------------------|
| `/pdfs`   | Abre no navegador o PDF de cada part number (MD04, centro 8500)       |
| `/ajuda`  | Mostra os comandos                                                    |
| `/limpar` | Limpa a tela                                                          |
| `/sair`   | Fecha o app                                                           |

Em `/pdfs`, cole a lista de part numbers (um por linha, ou separados por espaço,
vírgula ou ponto e vírgula), tecle Enter e depois Enter de novo com a linha vazia
para executar. Também dá para passar direto: `/pdfs 12345 67890`.

O SAP GUI Scripting precisa estar habilitado, como já é exigido pelas macros VBA.

## Desenvolvimento

Requer Go 1.24+.

```bash
go run . --simular
```

`--simular` roda as macros sem SAP (qualquer item contendo "erro" falha).

Gerar o executável para Windows, a partir de qualquer sistema:

```bash
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o dist/macro.exe .
```

### Nova macro

Crie um arquivo em `internal/macro/` com um valor `Macro` e adicione-o em `All()`
(`internal/macro/macro.go`). Ela aparece sozinha na lista de comandos.
