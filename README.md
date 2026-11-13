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

Feito em C# para .NET Framework 4.8, que já vem no Windows 10 e 11. Para compilar
basta o SDK do .NET 8 ou mais novo, em qualquer sistema:

```bash
dotnet build -c Release -o dist
```

O resultado é o `dist/macro.exe`.

Para testar sem SAP, abra com `macro.exe --simular` (qualquer item contendo "erro" falha).

### Estrutura

- `Sap/`: conexão com a sessão aberta do SAP GUI (SAP GUI Scripting).
- `Macros/`: uma classe por macro.
- `Ui/`: o terminal.

### Nova macro

Crie em `Macros/` uma classe que herda de `Macro` e adicione-a em `Macro.All`
(`Macros/Macro.cs`). Ela aparece sozinha na lista de comandos.
